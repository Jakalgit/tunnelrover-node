# tunnelrover-node (Hysteria2)

Exit node: **Hysteria2** + **Redis** (allowed users) + **Nest** (control API).

Backend calls the same `/xray` API as tcp-node; users are stored in Redis instead of Xray.

## Architecture

```
Client ──Hysteria2:443──► hysteria ──POST /internal/hysteria/auth──► nest ──► Redis
Backend ──Bearer──► https://node:8080/xray ──► nest ──► Redis (+ kick hysteria on DELETE)
```

## Deploy

```bash
cp deploy.config.example.json deploy.config.json
# fill nodeToken, nodeName, host
sudo ./deploy.sh
```

Re-running `./deploy.sh` is safe: templates are restored, Docker/certbot/swap are skipped if already present, the Hysteria traffic secret is reused.

## API (unchanged for tunnelrover-be)

| Method | Path | Body |
|--------|------|------|
| POST | `/xray` | `{ uuids: string[] }` |
| DELETE | `/xray` | `{ uuids: string[] }` |
| GET | `/xray/list` | — |
| GET | `/xray/count` | — |

Auth: `Authorization: Bearer {NODE_TOKEN}`

## Client

```text
hysteria2://<USER_UUID>@node-nl-1.tunnelrover.com:443?sni=node-nl-1.tunnelrover.com
```

`auth` = user UUID from backend (same as VLESS user id).

## Env (.env)

| Var | Purpose |
|-----|---------|
| `NODE_TOKEN` | Bearer for `/xray` API |
| `HYSTERIA_TRAFFIC_SECRET` | Hysteria Traffic Stats API (kick) |
| `REDIS_HOST` | `redis` (docker service) |
| `HYSTERIA_HOST` | `hysteria` (docker service) |

## Redis key

`SADD hysteria:users <uuid>` on add, `SREM` on remove.
