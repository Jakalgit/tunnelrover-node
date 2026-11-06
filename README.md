# Middle-node architecture (branch `middle-node-hysteria`)

**One VPS can run several Hysteria middle nodes.** Each node has its own `listenPort` (client UDP+TCP) and `controlPort` (nest API). Those ports must all be different, and none of them can be `80` (certbot). Hysteria cannot put two nodes on the same listen port.

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
2. Fill in the array. Each object needs `name`, `domain`, `nodeToken`, `listenPort`, `controlPort`, and `exit`. A single object is still accepted. If a port is omitted, the defaults are `443` and `8080`, which only works for one node.
3. On each **exit** node, add the relay UUID from that entry's `exit.auth` via `POST /user` (one-time).
4. On VPS:

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

`deploy/nodes.json` is a **JSON array** of nodes. Re-running `./deploy.sh` is safe. Files in `templates/` are only read. Each run rebuilds `generated/`, keeps each `trafficStatsSecret` in `nodes.json`, and skips certbot when the live certificate already covers every domain.

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/nginx/<name>.conf` | nginx control API on that node's `controlPort` |
| `generated/nodes/<name>/` | Hysteria server, exit client, Nest env |
| `generated/docker-compose.yaml` | nginx, promtail, and one stack per node |

## Compose

```bash
docker compose -f generated/docker-compose.yaml up -d
```

`deploy.sh` writes that file. The repo `docker-compose.yaml` is only a leftover reference.

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
| Nodes per VPS | 1 | N (nginx SNI) | **N, each with its own ports** |
| Public port | 443 | 443 via nginx `/ws` | `listenPort` UDP+TCP per node |

## Several nodes

Put every middle node in the same `deploy/nodes.json` array. `listenPort` and `controlPort` are taken together: the same number cannot be used twice, including across nodes. Port `80` stays reserved for certificate issuance.
