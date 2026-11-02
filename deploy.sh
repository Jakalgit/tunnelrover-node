#!/bin/bash
set -euo pipefail

CONFIG_FILE="deploy.config.json"
TEMPLATE_DIR=".deploy-templates"
TEMPLATE_FILES=(docker-compose.yaml nginx.conf xray-config.json)

usage() {
  cat <<EOF
Usage: sudo ./deploy.sh [--config deploy.config.json]

Copy deploy.config.example.json to deploy.config.json and fill nodeToken
(and host/nodeName if needed). Re-running this script is safe.
REALITY privateKey is generated once and saved back into the config.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./deploy.sh" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  if [[ -f deploy.config.example.json ]]; then
    cp deploy.config.example.json "$CONFIG_FILE"
    echo "Created $CONFIG_FILE from example. Fill nodeToken and run again." >&2
    exit 1
  fi
  echo "Missing $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y python3
fi

eval "$(python3 - "$CONFIG_FILE" <<'PY'
import json, shlex, sys

with open(sys.argv[1], encoding="utf-8") as f:
    cfg = json.load(f)

def q(value):
    return shlex.quote("" if value is None else str(value))

node_name = cfg.get("nodeName") or "node-nl-1"
host = cfg.get("host") or f"{node_name}.tunnelrover.com"
test_mode = "true" if cfg.get("testMode") else "false"

print(f"NODE_NAME={q(node_name)}")
print(f"ROVER_NODE_HOST={q(host)}")
print(f"NODE_TOKEN={q(cfg.get('nodeToken') or '')}")
print(f"CERTBOT_EMAIL={q(cfg.get('certbotEmail') or 'info@tunnelrover.com')}")
print(f"SWAP_SIZE={q(cfg.get('swapSize') or '3G')}")
print(f"TEST_MODE={q(test_mode)}")
print(f"XRAY_PRIVATE_KEY={q(cfg.get('privateKey') or '')}")
print(f"XRAY_PUBLIC_KEY={q(cfg.get('publicKey') or '')}")
print(f"SHORT_ID={q(cfg.get('shortId') or '1cb91b1d48ed')}")
print(f"XRAY_PORT={q(cfg.get('xrayPort') or 10085)}")
PY
)"

if [[ -z "$NODE_TOKEN" || "$NODE_TOKEN" == "same-as-accessToken-in-DB" ]]; then
  echo "Set nodeToken in $CONFIG_FILE (same as accessToken in Tunnel Rover DB)." >&2
  exit 1
fi

ensure_templates() {
  mkdir -p "$TEMPLATE_DIR"
  local file
  for file in "${TEMPLATE_FILES[@]}"; do
    if [[ ! -f "${TEMPLATE_DIR}/${file}" ]]; then
      cp "$file" "${TEMPLATE_DIR}/${file}"
    fi
  done
}

restore_templates() {
  local file
  for file in "${TEMPLATE_FILES[@]}"; do
    cp "${TEMPLATE_DIR}/${file}" "$file"
  done
}

parse_x25519() {
  local keys="$1"
  XRAY_PRIVATE_KEY=$(echo "$keys" | awk '/[Pp]rivate/{print $NF; exit}')
  XRAY_PUBLIC_KEY=$(echo "$keys" | awk '/[Pp]ublic/{print $NF; exit}')
}

ensure_reality_keys() {
  if [[ -n "$XRAY_PRIVATE_KEY" ]]; then
    return
  fi

  local keys
  keys=$(docker run --rm teddysun/xray xray x25519)
  parse_x25519 "$keys"

  if [[ -z "$XRAY_PRIVATE_KEY" || -z "$XRAY_PUBLIC_KEY" ]]; then
    echo "Failed to parse x25519 keys:" >&2
    echo "$keys" >&2
    exit 1
  fi
}

save_keys() {
  python3 - "$CONFIG_FILE" "$XRAY_PRIVATE_KEY" "$XRAY_PUBLIC_KEY" "$SHORT_ID" <<'PY'
import json, sys

path, private_key, public_key, short_id = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
changed = False
for key, value in (
    ("privateKey", private_key),
    ("publicKey", public_key),
    ("shortId", short_id),
):
    if cfg.get(key) != value:
        cfg[key] = value
        changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
PY
}

patch_files() {
  restore_templates

  python3 - "$NODE_NAME" "$ROVER_NODE_HOST" "$XRAY_PRIVATE_KEY" "$SHORT_ID" <<'PY'
import pathlib, sys

node_name, host, private_key, short_id = sys.argv[1:]

compose = pathlib.Path("docker-compose.yaml")
text = compose.read_text()
replacements = {
    "container_name: nginx-proxy\n": f"container_name: nginx-proxy-{node_name}\n",
    "container_name: nest-app\n": f"container_name: nest-app-{node_name}\n",
    "container_name: xray\n": f"container_name: xray-{node_name}\n",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"docker-compose.yaml is missing {old!r}")
    text = text.replace(old, new, 1)
compose.write_text(text)

nginx = pathlib.Path("nginx.conf")
nginx.write_text(nginx.read_text().replace("server-node.tunnelrover.com", host))

xray = pathlib.Path("xray-config.json")
xray_text = xray.read_text()
for token, value in (
    ("{{NODE_HOST}}", host),
    ("{{PRIVATE_KEY}}", private_key),
    ("{{SHORT_ID}}", short_id),
):
    if token not in xray_text:
        raise SystemExit(f"xray-config.json is missing {token}")
    xray_text = xray_text.replace(token, value)
xray.write_text(xray_text)
PY

  cat > .env <<EOF
XRAY_HOST=xray
XRAY_PORT=${XRAY_PORT}
NODE_TOKEN=${NODE_TOKEN}
TEST_MODE=${TEST_MODE}
EOF
}

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

issue_certs() {
  local live_dir="/etc/letsencrypt/live/${ROVER_NODE_HOST}"

  if [[ ! -f "${live_dir}/fullchain.pem" ]]; then
    docker compose down || true
    certbot certonly \
      --standalone \
      -d "$ROVER_NODE_HOST" \
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

ensure_templates
install_docker
ensure_swap
issue_certs
ensure_reality_keys
save_keys
patch_files

docker compose up -d --build

echo
echo "Node host / REALITY SNI: ${ROVER_NODE_HOST}"
echo "REALITY public key:      ${XRAY_PUBLIC_KEY:-'(set publicKey in deploy.config.json)'}"
echo "REALITY shortId:         ${SHORT_ID}"
echo "Camouflage site:         http://${ROVER_NODE_HOST}/"
echo "Control API:             https://${ROVER_NODE_HOST}:8080/"
