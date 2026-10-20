#!/bin/bash
set -euo pipefail

CONFIG_FILE="deploy.config.json"
TEMPLATE_DIR=".deploy-templates"
TEMPLATE_FILES=(docker-compose.yaml nginx.conf hysteria-config.yaml)

usage() {
  cat <<EOF
Usage: sudo ./deploy.sh [--config deploy.config.json]

Copy deploy.config.example.json to deploy.config.json and fill nodeToken
(and host/nodeName if needed). Re-running this script is safe.
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
import json, os, shlex, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)

def q(value):
    return shlex.quote("" if value is None else str(value))

node_name = cfg.get("nodeName") or "node-nl-1"
host = cfg.get("host") or f"{node_name}.tunnelrover.com"
node_token = cfg.get("nodeToken") or os.environ.get("NODE_TOKEN", "")
secret = cfg.get("trafficStatsSecret") or ""
bandwidth = cfg.get("bandwidth") or {}

print(f"NODE_NAME={q(node_name)}")
print(f"ROVER_NODE_HOST={q(host)}")
print(f"NODE_TOKEN={q(node_token)}")
print(f"CERTBOT_EMAIL={q(cfg.get('certbotEmail') or 'info@tunnelrover.com')}")
print(f"SWAP_SIZE={q(cfg.get('swapSize') or '3G')}")
print(f"TEST_MODE={q(str(cfg.get('testMode', False)).lower())}")
print(f"TRAFFIC_STATS_SECRET={q(secret)}")
print(f"MASQUERADE_URL={q(cfg.get('masqueradeUrl') or 'https://www.bing.com')}")
print(f"BANDWIDTH_UP={q(bandwidth.get('up') or '1 gbps')}")
print(f"BANDWIDTH_DOWN={q(bandwidth.get('down') or '1 gbps')}")
PY
)"

if [[ -z "$NODE_TOKEN" || "$NODE_TOKEN" == "same-as-accessToken-in-DB" ]]; then
  echo "Set nodeToken in $CONFIG_FILE (same as accessToken in Tunnel Rover DB)." >&2
  exit 1
fi

if [[ -z "$TRAFFIC_STATS_SECRET" && -f .env ]]; then
  TRAFFIC_STATS_SECRET="$(awk -F= '/^HYSTERIA_TRAFFIC_SECRET=/{print substr($0, index($0,"=")+1); exit}' .env || true)"
fi

if [[ -z "$TRAFFIC_STATS_SECRET" ]]; then
  TRAFFIC_STATS_SECRET="$(openssl rand -hex 32)"
fi

python3 - "$CONFIG_FILE" "$TRAFFIC_STATS_SECRET" <<'PY'
import json, sys

path, secret = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
if cfg.get("trafficStatsSecret") != secret:
    cfg["trafficStatsSecret"] = secret
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
PY

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

patch_files() {
  restore_templates

  sed -i "s/container_name:[[:space:]]*nginx-proxy$/container_name: nginx-proxy-${NODE_NAME}/" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*nest-app$/container_name: nest-app-${NODE_NAME}/" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*hysteria$/container_name: hysteria-${NODE_NAME}/" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*redis$/container_name: redis-${NODE_NAME}/" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*promtail$/container_name: promtail-${NODE_NAME}/" docker-compose.yaml

  sed -i "s|server-node.tunnelrover.com|${ROVER_NODE_HOST}|g" nginx.conf

  sed -i "s|{{TRAFFIC_STATS_SECRET}}|${TRAFFIC_STATS_SECRET}|g" hysteria-config.yaml
  sed -i "s|{{MASQUERADE_URL}}|${MASQUERADE_URL}|g" hysteria-config.yaml
  sed -i "s|{{BANDWIDTH_UP}}|${BANDWIDTH_UP}|g" hysteria-config.yaml
  sed -i "s|{{BANDWIDTH_DOWN}}|${BANDWIDTH_DOWN}|g" hysteria-config.yaml

  cat > .env <<EOF
NODE_TOKEN=${NODE_TOKEN}
HYSTERIA_TRAFFIC_SECRET=${TRAFFIC_STATS_SECRET}
REDIS_HOST=redis
REDIS_PORT=6379
HYSTERIA_HOST=hysteria
HYSTERIA_TRAFFIC_PORT=9999
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
patch_files

docker compose up -d --build

echo
echo "Done."
echo "  Hysteria: $ROVER_NODE_HOST:443 (UDP+TCP)"
echo "  Nest API: https://$ROVER_NODE_HOST:8080/user"
echo "  Client auth: hysteria2://<USER_UUID>@$ROVER_NODE_HOST:443?sni=$ROVER_NODE_HOST"
