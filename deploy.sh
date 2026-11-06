#!/bin/bash
# Hysteria middle-node. One VPS = one relay on :443.
#
#   cp deploy/nodes.example.json deploy/nodes.json
#   sudo ./deploy.sh
#
# Safe to run again: templates are only read, generated files are rebuilt,
# the traffic secret is reused, certbot runs only when the cert is missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NODES_FILE="${NODES_FILE:-deploy/nodes.json}"
GENERATED_DIR="generated"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./deploy.sh" >&2
  exit 1
fi

if [[ ! -f "$NODES_FILE" ]]; then
  if [[ -f deploy/nodes.example.json ]]; then
    cp deploy/nodes.example.json "$NODES_FILE"
    echo "Created $NODES_FILE from example. Fill it and run again." >&2
    exit 1
  fi
  echo "Missing $NODES_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y python3
fi

eval "$(python3 - "$NODES_FILE" <<'PY'
import json, shlex, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    raw = json.load(f)

if isinstance(raw, list):
    if len(raw) != 1:
        raise SystemExit("deploy/nodes.json must describe exactly one node")
    cfg = raw[0]
else:
    cfg = raw

def q(value):
    return shlex.quote("" if value is None else str(value))

exit_cfg = cfg.get("exit") or {}
bandwidth = cfg.get("bandwidth") or {}
def port_num(value, default, label):
    if value is None or value == "":
        value = default
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"{label} must be a TCP port")
    if not 1 <= number <= 65535:
        raise SystemExit(f"{label} must be between 1 and 65535")
    return number

name = cfg.get("name") or ""
domain = cfg.get("domain") or ""
token = cfg.get("nodeToken") or ""
listen_port = port_num(cfg.get("listenPort"), 443, "listenPort")
control_port = port_num(cfg.get("controlPort"), 8080, "controlPort")
address = exit_cfg.get("address") or ""
auth = exit_cfg.get("auth") or ""
if listen_port == control_port or listen_port == 80 or control_port == 80:
    raise SystemExit("listenPort and controlPort must be different, and neither can be 80")

missing = [
    label
    for label, value in (
        ("name", name),
        ("domain", domain),
        ("nodeToken", token),
        ("exit.address", address),
        ("exit.auth", auth),
    )
    if not value or value.startswith("REPLACE_")
]
if missing:
    raise SystemExit("Fill in deploy/nodes.json: " + ", ".join(missing))

print(f"NODE_NAME={q(name)}")
print(f"DOMAIN={q(domain)}")
print(f"LISTEN_PORT={listen_port}")
print(f"CONTROL_PORT={control_port}")
print(f"NODE_TOKEN_VALUE={q(token)}")
print(f"EXIT_ADDRESS={q(address)}")
print(f"EXIT_PORT={q(exit_cfg.get('port') or 443)}")
print(f"EXIT_AUTH={q(auth)}")
print(f"EXIT_SNI={q(exit_cfg.get('sni') or address)}")
print(f"CERTBOT_EMAIL={q(cfg.get('certbotEmail') or 'info@tunnelrover.com')}")
print(f"SWAP_SIZE={q(cfg.get('swapSize') or '2G')}")
print(f"TEST_MODE={q('true' if cfg.get('testMode') else 'false')}")
print(f"TRAFFIC_STATS_SECRET={q(cfg.get('trafficStatsSecret') or '')}")
print(f"MASQUERADE_URL={q(cfg.get('masqueradeUrl') or 'https://www.cloudflare.com')}")
print(f"BANDWIDTH_UP={q(bandwidth.get('up') or '1 gbps')}")
print(f"BANDWIDTH_DOWN={q(bandwidth.get('down') or '1 gbps')}")
PY
)"

if [[ -z "$TRAFFIC_STATS_SECRET" && -f "$GENERATED_DIR/.env" ]]; then
  TRAFFIC_STATS_SECRET="$(awk -F= '/^HYSTERIA_TRAFFIC_SECRET=/{print substr($0, index($0,"=")+1); exit}' "$GENERATED_DIR/.env" || true)"
fi

if [[ -z "$TRAFFIC_STATS_SECRET" ]]; then
  TRAFFIC_STATS_SECRET="$(openssl rand -hex 32)"
fi

python3 - "$NODES_FILE" "$TRAFFIC_STATS_SECRET" <<'PY'
import json, sys

path, secret = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    raw = json.load(f)

if isinstance(raw, list):
    cfg = raw[0]
else:
    cfg = raw

if cfg.get("trafficStatsSecret") == secret:
    raise SystemExit(0)

cfg["trafficStatsSecret"] = secret
with open(path, "w", encoding="utf-8") as f:
    json.dump(raw, f, indent=2)
    f.write("\n")
PY

render() {
  python3 - "$1" "$2" <<'PY'
import os, pathlib, sys

src, dst = sys.argv[1], sys.argv[2]
text = pathlib.Path(src).read_text()
mapping = {
    "NODE_NAME": os.environ["NODE_NAME"],
    "DOMAIN": os.environ["DOMAIN"],
    "LISTEN_PORT": os.environ["LISTEN_PORT"],
    "CONTROL_PORT": os.environ["CONTROL_PORT"],
    "TRAFFIC_STATS_SECRET": os.environ["TRAFFIC_STATS_SECRET"],
    "MASQUERADE_URL": os.environ["MASQUERADE_URL"],
    "BANDWIDTH_UP": os.environ["BANDWIDTH_UP"],
    "BANDWIDTH_DOWN": os.environ["BANDWIDTH_DOWN"],
    "EXIT_ADDRESS": os.environ["EXIT_ADDRESS"],
    "EXIT_PORT": os.environ["EXIT_PORT"],
    "EXIT_AUTH": os.environ["EXIT_AUTH"],
    "EXIT_SNI": os.environ["EXIT_SNI"],
    "ROOT": os.environ["ROOT"],
}
for key, value in mapping.items():
    text = text.replace("{{" + key + "}}", value)
if "{{" in text and "}}" in text:
    raise SystemExit(f"Unresolved placeholder left in {dst}")
path = pathlib.Path(dst)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
PY
}

export NODE_NAME DOMAIN LISTEN_PORT CONTROL_PORT TRAFFIC_STATS_SECRET MASQUERADE_URL BANDWIDTH_UP BANDWIDTH_DOWN
export EXIT_ADDRESS EXIT_PORT EXIT_AUTH EXIT_SNI
export ROOT="$SCRIPT_DIR"

rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR/nginx"

render templates/node-single.conf.template "$GENERATED_DIR/nginx/node.conf"
render templates/hysteria-server-config.yaml.template "$GENERATED_DIR/hysteria-server-config.yaml"
render templates/hysteria-exit-client.yaml.template "$GENERATED_DIR/hysteria-exit-client.yaml"
render templates/docker-compose.yaml.template "$GENERATED_DIR/docker-compose.yaml"

cat > "$GENERATED_DIR/.env" <<EOF
NODE_TOKEN=${NODE_TOKEN_VALUE}
HYSTERIA_TRAFFIC_SECRET=${TRAFFIC_STATS_SECRET}
REDIS_HOST=redis
REDIS_PORT=6379
HYSTERIA_HOST=hysteria
HYSTERIA_TRAFFIC_PORT=9999
TEST_MODE=${TEST_MODE}
EOF

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh
  fi
  systemctl enable --now docker

  if ! command -v certbot >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y certbot iptables-persistent nano
  fi

  if ! docker compose version >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y docker-compose-plugin
  fi
}

ensure_swap() {
  if [[ -f /swapfile ]]; then
    return
  fi
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
}

compose() {
  docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/$GENERATED_DIR/docker-compose.yaml" "$@"
}

issue_certs() {
  local live_dir="/etc/letsencrypt/live/${DOMAIN}"

  if [[ ! -f "${live_dir}/fullchain.pem" ]]; then
    compose down || true
    certbot certonly \
      --standalone \
      -d "$DOMAIN" \
      --non-interactive \
      --agree-tos \
      --email "$CERTBOT_EMAIL" \
      --no-eff-email
  fi

  mkdir -p ./nginx-certs
  cp "${live_dir}/fullchain.pem" ./nginx-certs/fullchain.pem
  cp "${live_dir}/privkey.pem" ./nginx-certs/privkey.pem
  chmod 644 ./nginx-certs/*.pem
}

install_docker
ensure_swap
issue_certs

compose up -d --build

echo
echo "Done. Hysteria middle-node ($NODE_NAME):"
echo "  hysteria2://<USER_UUID>@$DOMAIN:$LISTEN_PORT?sni=$DOMAIN"
echo "  https://$DOMAIN:$CONTROL_PORT  → nest-app control API"
