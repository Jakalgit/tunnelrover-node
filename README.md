# Middle-node architecture (branch `middle-node-hysteria`)

**One VPS = one Hysteria middle node.** Clients connect to `listenPort` (default `443`, UDP+TCP). The control API is published on `controlPort` (default `8080`).  
Unlike xray middle-node, Hysteria cannot share one port across several logical nodes.

```
Client ──Hysteria2 listenPort──► hysteria (middle)
                               │ ACL → SOCKS5
                               ▼
                         hysteria-exit (client)
                               │
                               ▼
                         exit Hysteria server
```

Nest API on `https://<domain>:<controlPort>`. Default `controlPort` is `8080`.

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. Fill in **one** node object (`name`, `domain`, `nodeToken`, `exit`). `listenPort` is the client port, `controlPort` is the nest API port. Both can be omitted: `443` and `8080`.
3. On the **exit** node, add relay UUID from `exit.auth` via `POST /user` (one-time).
4. On VPS:

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

`deploy/nodes.json` must be a **single JSON object**, not an array.
Re-running `./deploy.sh` is safe. Files in `templates/` and the repo `docker-compose.yaml` are only read. Each run rebuilds `generated/` (including `generated/docker-compose.yaml`), keeps `trafficStatsSecret` in `nodes.json`, and skips certbot when `/etc/letsencrypt/live/<domain>` already exists.

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/nginx/node.conf` | nginx control API on `controlPort` |
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
| `tcpPort` | `listenPort` from nodes.json |
| `pathServerName` | same as `domain` (SNI) |

Client link:

`hysteria2://<USER_UUID>@node-us-1.tunnelrover.com:<listenPort>?sni=node-us-1.tunnelrover.com`

## vs other branches

| | `hysteria` | `middle-node` (xray) | `middle-node-hysteria` |
|--|------------|----------------------|-------------------------|
| Role | exit | xray relay → REALITY | hysteria relay → hysteria exit |
| Nodes per VPS | 1 | N (nginx SNI) | **1** |
| Public port | 443 | 443 via nginx `/ws` | 443 UDP+TCP direct |

## Scaling

Need more middle nodes? Deploy **one VPS per domain** — each runs its own `deploy.sh`.
