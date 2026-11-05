# Middle-node xhttp architecture (branch `middle-node-xhttp`)

One VPS runs **one nginx** and **N relay stacks**. Each stack is a pair `xray-{name}` + `nest-app-{name}` for its own domain.

Client connects with **VLESS + xhttp** (TLS terminated by nginx, HTTP/2). Relay forwards to **xhttp exit** (`tunnelrover-exit-node` branch `xhttp`).

```
  Client ──xhttp──► middle (nginx + xray) ──xhttp/TLS──► exit (nginx + xray) ──► internet
```

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. For each node set:
   - `name`, `domain`, `nodeToken` (same as `accessToken` in Tunnel Rover DB)
   - `xhttpPath`, `xhttpMode` (default: `/assets/build/_app/immutable/chunks/`, `packet-up`)
   - `exit` — xhttp exit from `tunnelrover-exit-node` branch `xhttp`
3. On VPS:

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

Re-running `./deploy.sh` is safe. Files in `templates/` and the repo `docker-compose.yaml` are only read. Each run rebuilds `generated/`, and certbot runs only when the existing certificate does not cover every domain in `nodes.json`.

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/nginx/nodes/*.conf` | nginx `server` blocks with xhttp path → xray |
| `generated/nodes/*/xray-config.json` | relay xray: xhttp inbound + REALITY outbound |
| `generated/nodes/*/.env` | `XRAY_HOST`, `NODE_TOKEN` |
| `generated/docker-compose.yaml` | nginx, promtail, xray и nest на каждую ноду |

## Compose

```bash
docker compose --project-directory . -f generated/docker-compose.yaml up -d
```

## Tunnel Rover DB (per middle node)

| Field | Value |
|-------|--------|
| `connection` | `xhttp` |
| `host` | `domain` from nodes.json |
| `tcpPort` | `443` |
| `pathServerName` | `xhttpPath` from nodes.json (e.g. `/assets/build/_app/immutable/chunks/`) |

## Exit node (`tunnelrover-exit-node` branch `xhttp`)

```bash
cp deploy/nodes.example.json deploy/nodes.json
sudo ./deploy.sh
```

`relayUuid` on the exit is the same UUID as `exit.id` here.

## vs `middle-node` (WS)

| | middle-node | middle-node-xhttp |
|--|-------------|-----------------|
| Client transport | VLESS + WS | VLESS + xhttp |
| Middle → exit | REALITY tcp-node | xhttp exit-node |
| Exit repo | tunnelrover-exit-node `main` | tunnelrover-exit-node `xhttp` |
