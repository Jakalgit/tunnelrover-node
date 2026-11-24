# Middle node, XDNS (branch `xdns`)

One folder is one XDNS entry node. The phone does not connect to this server's IP. It sends DNS queries to a resolver that is already reachable, and the resolver delivers them to this host on UDP 53.

```
Phone ──DNS query──► resolver ──UDP 53──► xray (VLESS + XDNS)
                                              │ XHTTP
                                              ▼
                                            exit
```

The exit is a normal XHTTP exit (`tunnelrover-exit-node` branch `xhttp`). `exit.id` here is that exit's relay UUID.

## DNS records

`tunnelDomain` is the name clients put in the XDNS mask. It is an NS name, not an address record.

| Record | Example | Target |
|--------|---------|--------|
| A | `ns.example.com` | this server's IP |
| NS | `t.example.com` | `ns.example.com` |

`tunnelDomain` is `t.example.com`. The A name must not be a subdomain of the NS name. The zone does not have to be `.ru`.

`domain` is only the control API. Certbot issues a certificate for it.

## Deploy

1. Copy `deploy/nodes.example.json` → `deploy/nodes.json`.
2. Fill in `name`, `domain`, `tunnelDomain`, `controlPort`, `nodeToken`, and `exit`.
3. On the VPS, UDP 53 must be free. `systemd-resolved` often holds it.

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

Re-running `./deploy.sh` is safe. Templates are only read. Each run rebuilds `generated/` and skips certbot when the live certificate already covers `domain`.

Only one XDNS folder can run on a host, because recursive resolvers always query port 53.

```bash
sudo ./deploy.sh down
```

`down` removes this folder's containers and the Nest image built here.

## Client

Same UUID as a user added through the control API. Resolver is one the phone can reach. For a whitelist network that is Yandex DNS, not `1.1.1.1` or `8.8.8.8`.

```json
"streamSettings": {
  "network": "kcp",
  "kcpSettings": { "mtu": 130, "tti": 200 },
  "finalmask": {
    "udp": [
      {
        "type": "xdns",
        "settings": {
          "domains": [{ "names": ["t.example.com"], "types": [16], "edns0": 1232 }],
          "resolvers": [{ "addrs": ["udp://77.88.8.8:53"] }]
        }
      }
    ]
  }
}
```

Server MTU is 900. Client MTU stays 130 so a DNS answer is not truncated.

## Tunnel Rover DB

| Field | Value |
|-------|--------|
| `connection` | `xhttp` is the exit hop, not this client profile |
| control API | `https://<domain>:<controlPort>` |
| bearer | `nodeToken` |
