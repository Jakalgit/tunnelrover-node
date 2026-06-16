# Middle-node architecture (branch `middle-node-hysteria`)

**One VPS = one Hysteria middle node** on port `443` (UDP+TCP).  
Unlike xray middle-node, Hysteria cannot share one port across several logical nodes.

```
Client ──Hysteria2 :443──► hysteria (middle)
                               │ ACL → SOCKS5
                               ▼
                         hysteria-exit (client)
                               │
                               ▼
                         exit Hysteria server
```

Nest API on `https://<domain>:8080`, Redis auth — same as branch `hysteria`.

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. Fill in **one** node object (`name`, `domain`, `nodeToken`, `exit`).
3. On the **exit** node, add relay UUID from `exit.auth` via `POST /user` (one-time).
4. On VPS:

```bash
chmod +x deploy.sh
sudo bash deploy.sh
```

`deploy/nodes.json` must be a **single JSON object**, not an array.  
If you pass an array, it must contain exactly one element.

Re-deploy configs only:

```bash
SKIP_BOOTSTRAP=1 SKIP_CERTBOT=1 sudo ./deploy.sh
```

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/nginx/node.conf` | nginx `:8080` API |
| `generated/hysteria-server-config.yaml` | public Hysteria server |
| `generated/hysteria-exit-client.yaml` | relay client → exit |
| `generated/.env` | Nest + traffic stats secret |

## Compose

```bash
docker compose up -d
```

All services are in `docker-compose.yaml` (no second compose file).

## Tunnel Rover DB

| Field | Value |
|-------|--------|
| `connection` | `hysteria` |
| `host` | `domain` from nodes.json |
| `tcpPort` | `443` |
| `pathServerName` | same as `domain` (SNI) |

Client link:

`hysteria2://<USER_UUID>@node-us-1.tunnelrover.com:443?sni=node-us-1.tunnelrover.com`

## vs other branches

| | `hysteria` | `middle-node` (xray) | `middle-node-hysteria` |
|--|------------|----------------------|-------------------------|
| Role | exit | xray relay → REALITY | hysteria relay → hysteria exit |
| Nodes per VPS | 1 | N (nginx SNI) | **1** |
| Public port | 443 | 443 via nginx `/ws` | 443 UDP+TCP direct |

## Scaling

Need more middle nodes? Deploy **one VPS per domain** — each runs its own `deploy.sh`.
