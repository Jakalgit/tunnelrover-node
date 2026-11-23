# Middle-node architecture (branch `middle-node-hysteria-xhttp`)

**One folder is one Hysteria middle node.** To run another node on the same VPS, copy this folder under a different name and set other `listenPort` and `controlPort`. The folder name becomes the Compose project name.

TCP 80 and TCP 443 belong to one host nginx (`systemd`), shared by every folder. `deploy.sh` writes a separate site file, `/etc/nginx/conf.d/tunnelrover-<folder>.conf`, and the main `nginx.conf` loads the whole directory with `include /etc/nginx/conf.d/*.conf`. Installing the second node does not rewrite the first node's file. Port 80 answers ACME challenges for every domain, so certificates can be issued while the other nodes stay up. Hysteria publishes only `listenPort/udp` (443 is fine: it does not collide with nginx on TCP 443). `controlPort` is bound on `127.0.0.1` and must not be 80 or 443.

```
Client ──Hysteria2 listenPort──► hysteria (middle)
                               │ SOCKS5
                               ▼
                         xray-exit (VLESS XHTTP)
                               │
                               ▼
                         exit Xray XHTTP
```

Nest API on `https://<domain>` (host nginx proxies to `127.0.0.1:<controlPort>`).

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. Fill in the object. It needs `name`, `domain`, `nodeToken`, `listenPort`, `controlPort`, and `exit`. Ports have no default: a second folder must not reuse `listenPort` or `controlPort`.
3. On the **exit** XHTTP node, the VLESS client id must be this entry's `exit.id`. `exit.path` and `exit.mode` must match the exit (`packet-up` by default). `exit.sni` is the name on the exit certificate.
4. On VPS:

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

`deploy/nodes.json` is **one object**. Re-running `./deploy.sh` is safe. Files in `templates/` are only read. Each run rebuilds `generated/`, keeps `trafficStatsSecret` in `nodes.json`, and skips certbot when the live certificate already covers the domain. The folder name must be unique on the host.

The first deploy installs host nginx if it is missing, disables `sites-enabled/default` (it would also take port 80), and serves `/.well-known/acme-challenge/` from `/var/www/certbot`. Certbot uses webroot, so nginx stays up. A renew hook reloads nginx and restarts only the Hysteria container of the renewed domain.

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/host-node.conf` | site file copied to `/etc/nginx/conf.d/tunnelrover-<folder>.conf` |
| `generated/nodes/<name>/` | Hysteria server, exit client, Nest env |
| `generated/docker-compose.yaml` | this folder's promtail and node stack |
| `/etc/nginx/conf.d/00-tunnelrover-http.conf` | shared port 80 for ACME and the landing page |
| `/etc/nginx/conf.d/tunnelrover-<folder>.conf` | this domain on port 443 |

## Compose

`deploy.sh` writes `.env` with `COMPOSE_FILE` and `COMPOSE_PROJECT_NAME`. From this folder:

```bash
docker compose ps
sudo ./deploy.sh down
```

`sudo ./deploy.sh down` deletes this project's containers, the Nest image built here, and this folder's file in `/etc/nginx/conf.d/`. The shared port 80 config and every other node's site stay. Images such as `hysteria` stay on the machine while another folder is still using them.

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
| Public port | 443 | 443 via nginx `/ws` | `listenPort` UDP, API on TCP 443 by domain |

## Several nodes on one host

Copy the folder. The copy's directory name must differ, and so must `listenPort` and `controlPort`. Run `sudo ./deploy.sh` in the copy. It adds another file under `/etc/nginx/conf.d/` and asks certbot for that domain through the nginx that is already listening on port 80. TCP 80 and TCP 443 stay with the host nginx. If an older container from this folder still publishes port 80 or TCP 443, the deploy removes that container. A container from another project that still holds those ports has to be stopped first.
