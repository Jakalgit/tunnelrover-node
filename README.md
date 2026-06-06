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
3. Set `NODE_TOKEN` env before deploy (used in generated `.env` per node).
4. On VPS: `sudo NODE_TOKEN=secret ./deploy.sh`

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
