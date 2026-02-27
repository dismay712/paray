# paray

运行在 PaaS 平台的 xray

![License](https://img.shields.io/badge/license-MIT-green) [![Build And Push](https://github.com/dismay712/paray/actions/workflows/build-and-push.yml/badge.svg?branch=main&event=workflow_dispatch)](https://github.com/dismay712/paray/actions/workflows/build-and-push.yml) [![Docker Pulls](https://img.shields.io/docker/pulls/znxr/paray)](https://hub.docker.com/r/znxr/paray)

### 环境变量

| 环境变量     | 说明                                                         |
| ------------ | ------------------------------------------------------------ |
| WEBJS_UUID   | `vless` 的 `UUID` 参数                                       |
| WEBJS_DECR   | `vless` 的 `decryption` 参数，不需要可填 `none`，不能留空    |
| KOMARI_ARGS  | `Komari Agent` 的运行参数，可以从 `Komari` 后台管理的安装命令获取 |
| TUNNEL_TOKEN | `Cloudflare Tunnel` 的 `Token` 参数                          |

### 保活

#### 分流

![pZzR538.png](https://s41.ax1x.com/2026/02/27/pZzR538.png)

#### gRPC 分流设置

![pZzRIgS.png](https://s41.ax1x.com/2026/02/27/pZzRIgS.png)

### 保活

可以将 `3000` (xhttp) 端口暴露出来，直接使用定时工具定时访问 `/fetch-xhttp` 即可。

因为不带上正确的参数，虽然请求到达了 `xray`，但会直接丢弃，损失一丢丢性能。

### 配置

#### XHTTP

```url
vless://{UUID}@icook.hk:443?mode=auto&path=fetch-xhttp&security=tls&encryption={没有就写none}&type=xhttp&sni={Cloudflare Tunnel 域名}#Paray-XHTTP
```

```json
{
  "outbound": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "icook.hk",
            "port": 443,
            "users": [
              {
                "encryption": "{没有就写none}",
                "flow": "",
                "id": "{UUID}",
                "level": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false,
          "serverName": "{Cloudflare Tunnel 域名}"
        },
        "xhttpSettings": {
          "host": "",
          "mode": "auto",
          "path": "fetch-xhttp"
        }
      }
    }
  ]
}
```

#### Clash

```yaml
# ws
- name: Paray-WS
  type: vless
  server: icook.hk # 可换用其他 Cloudflare 加速域名
  port: 443
  uuid: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee # UUID
  tls: true
  udp: true
  servername: aaa.bbb.ccc # Cloudflare Tunnel 域名
  skip-cert-verify: false
  network: ws
  ws-opts:
    path: /fetch-ws?ed=2560
    headers:
      Host: aaa.bbb.ccc # Cloudflare Tunnel 域名
# gRPC
- name: Paray-gRPC
  type: vless
  server: icook.hk # 可换用其他 Cloudflare 加速域名
  port: 443
  uuid: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee # UUID
  tls: true
  udp: true
  servername: aaa.bbb.ccc # Cloudflare Tunnel 域名
  skip-cert-verify: false
  alpn: ['h2']
  network: grpc
  grpc-opts:
    grpc-service-name: fetch-grpc
```