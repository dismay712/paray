# paray

运行在 PaaS 平台的 xray

![License](https://img.shields.io/badge/license-MIT-green) [![Build And Push Zig](https://github.com/dismay712/paray/actions/workflows/build-and-push.yml/badge.svg?branch=zig&event=workflow_dispatch)](https://github.com/dismay712/paray/actions/workflows/build-and-push.yml) [![Docker Pulls](https://img.shields.io/docker/pulls/znxr/paray)](https://hub.docker.com/r/znxr/paray)

`zig` 是内存对比实验分支：full 镜像使用 [luodaoyi/komari-zig-agent](https://github.com/luodaoyi/komari-zig-agent) `v0.1.53`，替代 main 中的 Go Agent。上游二进制仍名为 `komari-agent`，容器内路径、启动参数和 `KOMARI_*` 环境变量保持不变，自更新保持关闭。lite 镜像不包含 Agent。

### 构建

~~~sh
docker buildx build --target full --load -t paray:zig-full .
docker buildx build --target lite --load -t paray:zig-lite .
~~~

| 镜像 | 内容 |
| --- | --- |
| zig-full | Xray、cloudflared、Komari Zig Agent |
| zig-lite | Xray、cloudflared |

分支推送和 PR 只验证构建。在 Actions 中选择 `zig` 分支手动运行并启用 `publish`，才会发布 `sha-<完整提交 SHA>-zig-full`、`sha-<完整提交 SHA>-zig-lite` 标签，不覆盖 main 的 `full`、`lite`、`latest` 或版本标签。

支持 linux/amd64、linux/arm64。

精简 geoip.dat 单独获取，仅含 CN、PRIVATE，保留 IPv4/IPv6。

### 环境变量

| 环境变量     | 说明                                                         |
| ------------ | ------------------------------------------------------------ |
| WEBJS_UUID   | `vless` 的 `UUID` 参数                                       |
| WEBJS_DECR   | `vless` 的 `decryption` 参数，未设置或为空时使用 `none`   |
| TUNNEL_TOKEN | 可选，设置后启动 cloudflared |
| TUNNEL_ENABLED | 默认 true；false 可显式停用 Tunnel |
| KOMARI_ENDPOINT | 可选，Komari 面板地址 |
| KOMARI_TOKEN | 启用 Komari 时与 endpoint 一起提供 |

lite 镜像如果配置了 Komari 凭据会在初始化时报错。

full 镜像未提供 Token 时 Tunnel 保持停用；未提供 Komari 两项凭据时 Agent 保持停用。

### Go / Zig 内存对比

2026-11-01 在当前 Linux/amd64 开发环境中的一次快速测试：两版使用相同 JSON 配置（`interval=5`、关闭自更新），顺序连接本地 HTTP/WebSocket 模拟面板；收到 3 次上报后再预热 20 秒，每 0.5 秒读取一次 `/proc/<pid>/status`，持续 30 秒，共 60 次采样。

| Agent | 平均 RSS | 平均匿名内存 |
| --- | ---: | ---: |
| Go 1.5.11 | 14.78 MiB | 7.42 MiB |
| Zig v0.1.53 | 1.36 MiB | 0.47 MiB |

本次 RSS 降低约 **90.8%**。两版均正常上报，实际中位上报间隔约为 Go 6.00 秒、Zig 5.01 秒。测试不含 TLS、真实面板任务、完整容器或长期运行负载，不能将此比例直接当作 PaaS 的内存节省比例。

在同一台机器上顺序运行两版 full 镜像，使用相同的环境文件、资源配额、流量和配置；不要让同一个 Komari Token 同时连接两个 Agent。先确认 Agent 在面板中在线，再预热至少 5 分钟，多次采样比较。

```sh
# 在 zig 分支中执行；main 保留本轮依赖更新后的 Go Agent
git worktree add --detach ../paray-go main
docker buildx build --target full --load -t paray:go-full ../paray-go
docker buildx build --target full --load -t paray:zig-full .

# 环境文件需包含 WEBJS_UUID、KOMARI_ENDPOINT、KOMARI_TOKEN
# 两版挂载同一模板，保证采集间隔、网卡和基础信息上报间隔一致
docker run -d --name paray-go --env-file /path/to/paray.env \
  --mount "type=bind,src=$(pwd)/rootfs/etc/paray/komari.json,dst=/etc/paray/komari.json,readonly" \
  paray:go-full
# 面板在线并预热后，读取 Agent RSS、匿名内存和线程数（内存单位 kB）
docker exec paray-go sh -c 'pid=$(pidof komari-agent); grep -E "^(VmRSS|RssAnon|Threads):" "/proc/$pid/status"'
docker stats --no-stream paray-go
docker stop paray-go

docker run -d --name paray-zig --env-file /path/to/paray.env \
  --mount "type=bind,src=$(pwd)/rootfs/etc/paray/komari.json,dst=/etc/paray/komari.json,readonly" \
  paray:zig-full
# 同样在面板在线并预热后采样
docker exec paray-zig sh -c 'pid=$(pidof komari-agent); grep -E "^(VmRSS|RssAnon|Threads):" "/proc/$pid/status"'
docker stats --no-stream paray-zig
docker stop paray-zig
```

`VmRSS` 是 Agent 自身的驻留内存；`docker stats` 是包含 Xray、cloudflared 等进程的整个容器内存，两者不要混比。节省比例为 `(Go RSS - Zig RSS) / Go RSS × 100%`。上游公布的数据来自其他版本与环境，不能直接代表本项目或 PaaS 的实际收益。

本分支还将模板中的 `max-retries`、`reconnect-interval`、`info-report-interval` 改为两版均支持的下划线 JSON 键；旧键会被忽略，所以对比 Go 镜像时也需要挂载同一份修正后的模板。

### 配置

#### Xray

```json
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "address": "icook.hk",
        "port": 443,
        "id": "11111111-1111-4444-5555-111144444444",
        "encryption": "{没有就填 none}",
        "flow": ""
      },
      "streamSettings": {
        "method": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "{Cloudflare Tunnel 域名或 PaaS 平台直连域名}",
          "alpn": ["h2"]
        },
        "xhttpSettings": {
          "host": "{Cloudflare Tunnel 域名或 PaaS 平台直连域名}",
          "path": "/api/v1/chat/completions/",
          "mode": "packet-up",
          "xPaddingObfsMode": true,
          "xPaddingMethod": "tokenish",
          "xPaddingPlacement": "header",
          "xPaddingHeader": "X-Correlation-Id",
          "xPaddingKey": "_cid",
          "xPaddingBytes": "32-128"
        }
      }
    }
  ]
}
```

#### Mihomo

```yaml
- name: PaaS 直连
  type: vless
  server: paas.example.com # PaaS 平台直连域名
  port: 443
  uuid: 11111111-1111-4444-5555-111144444444
  encryption: "" # 没有就填 none
  udp: true
  packet-encoding: xudp
  tls: true
  servername: paas.example.com # PaaS 平台直连域名
  skip-cert-verify: false
  alpn: ["http/1.1"]
  network: xhttp
  xhttp-opts:
    host: paas.example.com # PaaS 平台直连域名
    path: /api/v1/chat/completions/
    mode: packet-up
    x-padding-obfs-mode: true
    x-padding-method: tokenish
    x-padding-placement: header
    x-padding-header: X-Correlation-Id
    x-padding-key: _cid
    x-padding-bytes: "32-128"

- name: Cloudflare-Tunnel
  type: vless
  server: icook.hk # 可换用其他 Cloudflare 加速域名
  port: 443
  uuid: 11111111-1111-4444-5555-111144444444
  encryption: ""
  udp: true
  packet-encoding: xudp
  tls: true
  servername: tunnel.example.com # Cloudflare Tunnel 域名
  skip-cert-verify: false
  alpn: [h2]
  network: xhttp
  xhttp-opts:
    host: tunnel.example.com # Cloudflare Tunnel 域名
    path: /api/v1/chat/completions/
    mode: packet-up
    x-padding-obfs-mode: true
    x-padding-method: tokenish
    x-padding-placement: header
    x-padding-header: X-Correlation-Id
    x-padding-key: _cid
    x-padding-bytes: "32-128"
```
