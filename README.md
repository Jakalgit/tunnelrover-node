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
2. For each node set `name`, `domain`, and `exit` (REALITY exit from `tcp-node`).
3. On VPS (from repo root, where `deploy.sh` lives):

```bash
cd ~/node   # or your clone path
ls -la deploy.sh deploy/nodes.json   # must exist

chmod +x deploy.sh
export NODE_TOKEN='your-secret-token'
sudo -E bash deploy.sh
```

Alternative (one line):

```bash
sudo env NODE_TOKEN='your-secret-token' bash deploy.sh
```

**Do not** run `sudo bash NODE_TOKEN=... ./deploy.sh` — that is invalid syntax.

If you see `./deploy.sh: command not found`, usually CRLF line endings from Windows:

```bash
sed -i 's/\r$//' deploy.sh
# or: apt install dos2unix && dos2unix deploy.sh
sudo env NODE_TOKEN='...' bash deploy.sh
```

### `nginx.conf: not a directory` / mount error

If `nginx.conf` (or `index.html`) was missing on first `docker compose up`, Docker may have created a **directory** with that name. Remove it and restore the **file** from the repo:

```bash
cd ~/node
docker compose -f docker-compose.yaml -f generated/docker-compose.nodes.yaml down 2>/dev/null || true
rm -rf nginx.conf index.html   # only if: file nginx.conf shows "directory"
git checkout -- nginx.conf index.html   # or re-upload from your machine
file nginx.conf   # must say "ASCII text", not "directory"
sudo env NODE_TOKEN='...' bash deploy.sh
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
| `generated/nodes/*/.env` | `XRAY_HOST=xray-{name}` for nest-app |
| `generated/docker-compose.nodes.yaml` | xray + nest services per node |

## Compose

```bash
docker compose -f docker-compose.yaml -f generated/docker-compose.nodes.yaml up -d
```

- `docker-compose.yaml` — shared **nginx** + **promtail**
- `generated/docker-compose.nodes.yaml` — per-node **xray** + **nest-app**

## vs single-node / tcp-node

| | single-node (main) | middle-node | tcp-node |
|--|-------------------|-------------|----------|
| nginx | 1 domain | 1 nginx, N domains | optional / minimal |
| xray role | exit (freedom) | relay → REALITY exit | exit REALITY TCP |
| nest-app | 1 | N | 1 |

Reference bridge: `tunnelrover-be/nginx/ru-bridge-deploy/`.
