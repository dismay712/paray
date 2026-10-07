# paray

运行在 PaaS 平台的 xray

![License](https://img.shields.io/badge/license-MIT-green) [![Build And Push](https://github.com/dismay712/paray/actions/workflows/build-and-push.yml/badge.svg?branch=main&event=workflow_dispatch)](https://github.com/dismay712/paray/actions/workflows/build-and-push.yml) [![Docker Pulls](https://img.shields.io/docker/pulls/znxr/paray)](https://hub.docker.com/r/znxr/paray)

### 构建

~~~sh
docker buildx build --target full --load -t paray:full .
docker buildx build --target lite --load -t paray:lite .
~~~

| 镜像 | 内容 |
| --- | --- |
| full / latest | Xray、cloudflared、Komari |
| lite | Xray、cloudflared |

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