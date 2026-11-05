#!/bin/bash
# TCP REALITY middle-node. One VPS = one relay. Xray owns :443.
#
#   cp deploy/nodes.example.json deploy/nodes.json
#   sudo ./deploy.sh
#
# Safe to run again: templates are only read, generated files are rebuilt,
# REALITY keys stay in nodes.json, certbot runs only when the cert is missing.

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

load_config() {
  local parsed
  parsed="$(python3 - "$NODES_FILE" <<'PY'
import json, shlex, sys

with open(sys.argv[1], encoding="utf-8") as f:
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
name = cfg.get("name") or ""
domain = cfg.get("domain") or ""
token = cfg.get("nodeToken") or ""
address = exit_cfg.get("address") or ""
relay = exit_cfg.get("id") or ""
public_key = exit_cfg.get("publicKey") or ""
short_id = exit_cfg.get("shortId") or ""

missing = [
    label
    for label, value in (
        ("name", name),
        ("domain", domain),
        ("nodeToken", token),
        ("exit.address", address),
        ("exit.id", relay),
        ("exit.publicKey", public_key),
        ("exit.shortId", short_id),
    )
    if not value or str(value).startswith("REPLACE_")
]
if missing:
    raise SystemExit("Fill in deploy/nodes.json: " + ", ".join(missing))

print(f"NODE_NAME={q(name)}")
print(f"DOMAIN={q(domain)}")
print(f"NODE_TOKEN_VALUE={q(token)}")
print(f"CERTBOT_EMAIL={q(cfg.get('certbotEmail') or 'info@tunnelrover.com')}")
print(f"SWAP_SIZE={q(cfg.get('swapSize') or '2G')}")
print(f"TEST_MODE={q('true' if cfg.get('testMode') else 'false')}")
print(f"PRIVATE_KEY={q(cfg.get('privateKey') or '')}")
print(f"PUBLIC_KEY={q(cfg.get('publicKey') or '')}")
print(f"SHORT_ID={q(cfg.get('shortId') or '')}")
print(f"EXIT_ADDRESS={q(address)}")
print(f"EXIT_PORT={q(exit_cfg.get('port') or 443)}")
print(f"EXIT_ID={q(relay)}")
print(f"EXIT_SNI={q(exit_cfg.get('sni') or address)}")
print(f"EXIT_PUBLIC_KEY={q(public_key)}")
print(f"EXIT_SHORT_ID={q(short_id)}")
PY
)" || exit 1
  eval "$parsed"
}

load_config

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh
  fi
  systemctl enable --now docker

  if ! command -v certbot >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y certbot openssl iptables-persistent nano
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

ensure_reality_keys() {
  if [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" && -n "$SHORT_ID" ]]; then
    return
  fi

  if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    local output
    output="$(docker run --rm teddysun/xray xray x25519)" || exit 1
    local parsed
    parsed="$(python3 - "$output" <<'PY'
import shlex, sys
text = sys.argv[1]
private = public = None
for line in text.splitlines():
    if ":" not in line:
        continue
    key, value = line.split(":", 1)
    key = "".join(ch for ch in key.split("(", 1)[0].lower() if ch.isalpha())
    value = value.strip()
    if key in ("privatekey", "private"):
        private = value
    elif key in ("publickey", "password", "public") and value:
        public = value
if not private or not public:
    raise SystemExit("Could not parse xray x25519 output:\n" + text)
print(f"declare -g PRIVATE_KEY={shlex.quote(private)}")
print(f"declare -g PUBLIC_KEY={shlex.quote(public)}")
PY
)" || exit 1
    eval "$parsed"
  fi

  if [[ -z "$SHORT_ID" ]]; then
    SHORT_ID="$(openssl rand -hex 8)"
  fi

  python3 - "$NODES_FILE" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID" <<'PY'
import json, sys
path, private_key, public_key, short_id = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    raw = json.load(f)
cfg = raw[0] if isinstance(raw, list) else raw
cfg["privateKey"] = private_key
cfg["publicKey"] = public_key
cfg["shortId"] = short_id
with open(path, "w", encoding="utf-8") as f:
    json.dump(raw, f, indent=2)
    f.write("\n")
PY
}

render() {
  python3 - "$1" "$2" <<'PY'
import json, os, pathlib, sys
src, dst = sys.argv[1], sys.argv[2]
text = pathlib.Path(src).read_text()
mapping = {
    "NODE_NAME": os.environ["NODE_NAME"],
    "DOMAIN": os.environ["DOMAIN"],
    "PRIVATE_KEY": os.environ["PRIVATE_KEY"],
    "PUBLIC_KEY": os.environ["PUBLIC_KEY"],
    "SHORT_ID": os.environ["SHORT_ID"],
    "EXIT_ADDRESS": os.environ["EXIT_ADDRESS"],
    "EXIT_PORT": os.environ["EXIT_PORT"],
    "EXIT_ID": os.environ["EXIT_ID"],
    "EXIT_SNI": os.environ["EXIT_SNI"],
    "EXIT_PUBLIC_KEY": os.environ["EXIT_PUBLIC_KEY"],
    "EXIT_SHORT_ID": os.environ["EXIT_SHORT_ID"],
    "ROOT": os.environ["ROOT"],
}
for key, value in mapping.items():
    text = text.replace("{{" + key + "}}", value)
if "{{" in text and "}}" in text:
    raise SystemExit(f"Unresolved placeholder left in {dst}")
path = pathlib.Path(dst)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
if dst.endswith(".json"):
    json.loads(text)
PY
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
ensure_reality_keys

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" ]]; then
  echo "REALITY key was not written. deploy/nodes.json privateKey, publicKey, or shortId is empty." >&2
  exit 1
fi

export NODE_NAME DOMAIN PRIVATE_KEY PUBLIC_KEY SHORT_ID
export EXIT_ADDRESS EXIT_PORT EXIT_ID EXIT_SNI EXIT_PUBLIC_KEY EXIT_SHORT_ID
export ROOT="$SCRIPT_DIR"

rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR"

render templates/xray-config.json.template "$GENERATED_DIR/xray-config.json"
render templates/nginx.conf.template "$GENERATED_DIR/nginx.conf"
render templates/docker-compose.yaml.template "$GENERATED_DIR/docker-compose.yaml"

cat > "$GENERATED_DIR/.env" <<EOF
NODE_TOKEN=${NODE_TOKEN_VALUE}
XRAY_HOST=xray
XRAY_PORT=10085
XRAY_INBOUND_TAG=vless-tcp
TEST_MODE=${TEST_MODE}
EOF

issue_certs

if [[ ! -f index.html ]]; then
  echo "Missing index.html" >&2
  exit 1
fi

compose up -d --build

echo
echo "Done. TCP REALITY middle-node ($NODE_NAME):"
echo "  client public key: $PUBLIC_KEY"
echo "  client short id:   $SHORT_ID"
echo "  client sni:        $DOMAIN"
echo "  https://$DOMAIN:8080  → nest-app control API"
