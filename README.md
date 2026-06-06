# Middle-node architecture (branch `middle-node`)

One VPS runs **one nginx** and **N relay stacks**. Each stack is a pair `xray-{name}` + `nest-app-{name}` for its own domain.

```
                    ┌──────────────── nginx-proxy ────────────────┐
  Client ──443/8080 │  server_name node-us-1.tunnelrover.com      │
                    │    /ws      → xray-node-us-1:443            │
                    │    :8080    → nest-app-node-us-1:5000       │
                    │  server_name node-hk-1.tunnelrover.com      │
                    │    /ws      → xray-node-hk-1:443            │
                    │    :8080    → nest-app-node-hk-1:5000       │
                    └─────────────────────────────────────────────┘
```

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. For each node set `name`, `domain`, `nodeToken` (API secret for nest-app; same value as `accessToken` in Tunnel Rover DB), and `exit` (REALITY exit from `tcp-node`).
3. On VPS (from repo root, where `deploy.sh` lives):

```bash
cd ~/node   # or your clone path
ls -la deploy.sh deploy/nodes.json   # must exist

chmod +x deploy.sh
sudo bash deploy.sh
```

`nodeToken` is read from `deploy/nodes.json` per node. Optional fallback for all nodes: `sudo env NODE_TOKEN='shared-secret' bash deploy.sh` (only if `nodeToken` is omitted in JSON).

If you see `./deploy.sh: command not found`, usually CRLF line endings from Windows:

```bash
sed -i 's/\r$//' deploy.sh
# or: apt install dos2unix && dos2unix deploy.sh
sudo bash deploy.sh
```

### `nginx.conf: not a directory` / mount error

If `nginx.conf` (or `index.html`) was missing on first `docker compose up`, Docker may have created a **directory** with that name. Remove it and restore the **file** from the repo:

```bash
cd ~/node
docker compose -f docker-compose.yaml -f generated/docker-compose.nodes.yaml down 2>/dev/null || true
rm -rf nginx.conf index.html   # only if: file nginx.conf shows "directory"
git checkout -- nginx.conf index.html   # or re-upload from your machine
file nginx.conf   # must say "ASCII text", not "directory"
sudo bash deploy.sh
```

Re-deploy configs only (Docker already installed):

```bash
SKIP_BOOTSTRAP=1 SKIP_CERTBOT=1 sudo ./deploy.sh
```

## Generated files (gitignored)

| Path | Purpose |
|------|---------|
| `generated/nginx/nodes/*.conf` | nginx `server` blocks from `templates/node-single.conf.template` |
| `generated/nodes/*/xray-config.json` | relay xray with exit placeholders filled |
| `generated/nodes/*/.env` | `XRAY_HOST`, `NODE_TOKEN` (from `nodeToken` in nodes.json) |
| `generated/docker-compose.nodes.yaml` | xray + nest services per node |

## Compose

```bash
docker compose -f docker-compose.yaml -f generated/docker-compose.nodes.yaml up -d
```

Always use **both** compose files. Do not run `docker network create` manually.

## Tunnel Rover DB (per middle node)

| Field | Value |
|-------|--------|
| `connection` | `ws` |
| `host` | `domain` from nodes.json |
| `tcpPort` | `443` |
| `pathServerName` | `/ws` |

## vs single-node / tcp-node

| | single-node (main) | middle-node | tcp-node |
|--|-------------------|-------------|----------|
| nginx | 1 domain | 1 nginx, N domains | optional / minimal |
| xray role | exit (freedom) | relay → REALITY exit | exit REALITY TCP |
| nest-app | 1 | N | 1 |

Reference bridge: `tunnelrover-be/nginx/ru-bridge-deploy/`.
