# Middle-node TCP + REALITY (branch `middle-node-tcp`)

One VPS is one relay. Clients connect with VLESS TCP + REALITY on `:443`. Xray owns that port and forwards non-VPN TLS to nginx on `8443`. The relay outbound is VLESS TCP + REALITY to `tunnelrover-exit-node` branch `main`.

```
Client ──REALITY/TCP──► middle xray :443 ──REALITY/TCP──► exit xray :443 ──► internet
                         dest nginx:8443
```

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. Set `name`, `domain`, `nodeToken`, and `exit` (`id`, `sni`, `publicKey`, `shortId` from the exit node).
3. Leave `privateKey` empty. The first run generates a REALITY keypair and writes `privateKey`, `publicKey`, and `shortId` back into `nodes.json`.

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

Re-running is safe. Files in `templates/` are only read. `generated/` is rebuilt every time. The keypair is reused. Certbot runs only when `/etc/letsencrypt/live/<domain>` is missing.

## Tunnel Rover DB

| Field | Value |
|-------|--------|
| `connection` | `tcp` |
| `host` | `domain` |
| `tcpPort` | `443` |
| `sni` | `domain` |
| `publicKey` | `publicKey` printed by deploy |
| `shortId` | `shortId` printed by deploy |
| `accessToken` | `nodeToken` |

`pathServerName` is not used.
