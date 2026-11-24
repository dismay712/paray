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
| TUNNEL_TRANSPORT_PROTOCOL | cloudflared 到 Cloudflare 边缘的协议，可选 `http2`（默认）、`auto` 或 `quic` |
| KOMARI_ENDPOINT | 可选，Komari 面板地址 |
| KOMARI_TOKEN | 启用 Komari 时与 endpoint 一起提供 |

lite 镜像如果配置了 Komari 凭据会在初始化时报错。

两种镜像均在提供 Tunnel Token 后启动 cloudflared。full 镜像在同时提供 Komari 的 endpoint 和 token 后启动 Agent。

### 配置

#### 入口域名

| 接入方式 | 部署设置 | 客户端示例域名 |
| --- | --- | --- |
| PaaS 直连 | 在平台上启用 HTTPS 入口，将请求转发到容器的 HTTP 端口 `8488` | `paas.example.com` |
| Cloudflare Tunnel | 在 Tunnel 的公开应用路由中绑定域名，Service 选 `HTTP`，URL 填 `127.0.0.1:8488`，关闭 `HTTP/2 to origin` | `tunnel.example.com` |

当前镜像中的 cloudflared 和 Xray 通过容器内的 HTTP 连接。客户端到 Cloudflare 边缘仍可使用 TLS 和 `h2`。若要比较隧道传输性能，可在允许出站 UDP 7844 的 PaaS 上试用 `TUNNEL_TRANSPORT_PROTOCOL=auto`。cloudflared 会尝试 QUIC，无法建立 UDP 连接时回退到 HTTP/2。保持客户端、入口域名和测试目标一致，比较首字节延迟、持续上传吞吐和断流次数。[Cloudflare 运行参数](https://developers.cloudflare.com/tunnel/reference/run-parameters/#protocol) · [回源参数](https://developers.cloudflare.com/tunnel/reference/origin-parameters/#http2origin)

以下示例中，将域名的每一处替换为相应入口的实际域名，将 UUID 替换为 `WEBJS_UUID`。示例使用默认的 VLESS `encryption` 值 `none`。配置了 `WEBJS_DECR` 时，请改用与其配套的客户端加密参数。Xray 的握手和空闲超时使用内核默认值。

#### Xray 客户端 · PaaS 直连

```json
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "address": "paas.example.com",
        "port": 443,
        "id": "11111111-1111-4444-5555-111144444444",
        "encryption": "none",
        "flow": ""
      },
      "streamSettings": {
        "method": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "paas.example.com",
          "alpn": ["h2"]
        },
        "xhttpSettings": {
          "host": "paas.example.com",
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

PaaS 的 HTTPS 入口如果仅支持 HTTP/1.1，请将此示例中的 `alpn` 改为 `["http/1.1"]`。

#### Xray 客户端 · Cloudflare Tunnel

```json
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "address": "tunnel.example.com",
        "port": 443,
        "id": "11111111-1111-4444-5555-111144444444",
        "encryption": "none",
        "flow": ""
      },
      "streamSettings": {
        "method": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "tunnel.example.com",
          "alpn": ["h2"]
        },
        "xhttpSettings": {
          "host": "tunnel.example.com",
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
  server: tunnel.example.com # Cloudflare Tunnel 域名
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
