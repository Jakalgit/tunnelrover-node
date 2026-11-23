# Middle-node architecture (branch `middle-node-hysteria-xhttp`)

**One folder is one Hysteria middle node.** To run another node on the same VPS, copy this folder under a different name and set other `listenPort` and `controlPort`. The folder name becomes the Compose project name, so `docker compose down` removes only that folder's containers. `listenPort`, `controlPort` and port `80` must all be different. Only one folder on the host can publish port `80` (`"bindHttp": false` on the others, once their certificate already exists).

```
Client ──Hysteria2 listenPort──► hysteria (middle)
                               │ SOCKS5
                               ▼
                         xray-exit (VLESS XHTTP)
                               │
                               ▼
                         exit Xray XHTTP
```

Nest API on `https://<domain>:<controlPort>`.

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. Fill in the object. It needs `name`, `domain`, `nodeToken`, `listenPort`, `controlPort`, and `exit`. Ports have no default: a second folder must not reuse them.
3. On the **exit** XHTTP node, the VLESS client id must be this entry's `exit.id`. `exit.path` and `exit.mode` must match the exit (`packet-up` by default). `exit.sni` is the name on the exit certificate.
4. On VPS:

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

`deploy/nodes.json` is **one object**. Re-running `./deploy.sh` is safe. Files in `templates/` are only read. Each run rebuilds `generated/`, keeps `trafficStatsSecret` in `nodes.json`, and skips certbot when the live certificate already covers the domain. The folder name must be unique on the host.

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/nginx/<name>.conf` | nginx control API on that node's `controlPort` |
| `generated/nodes/<name>/` | Hysteria server, exit client, Nest env |
| `generated/docker-compose.yaml` | this folder's nginx, promtail, and node stack |

## Compose

`deploy.sh` writes `.env` with `COMPOSE_FILE` and `COMPOSE_PROJECT_NAME`. From this folder:

```bash
docker compose ps
docker compose down --rmi local --volumes --remove-orphans
```

`down` stops and deletes containers of this project only, plus the Nest image built here. Images such as `nginx` and `hysteria` stay on the machine while another folder is still using them. A second copy of the folder is a different project, so this command does not touch it.

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
| Role | exit | xray relay → REALITY | hysteria to the client, XHTTP to the exit |
| Nodes per VPS | 1 | N (nginx SNI) | **one folder each, own ports** |
| Public port | 443 | 443 via nginx `/ws` | `listenPort` UDP+TCP |

## Several nodes on one host

Copy the folder. The copy's directory name must differ, and so must `listenPort` and `controlPort`. Set `"bindHttp": false` on every folder except the one that should own port `80`. Issue that folder's certificate before the other nginx is holding port `80`, or stop the other stack for the certbot run.
