#!/bin/bash
# Hysteria middle-node: one VPS = one relay node on :443 (UDP+TCP).
#
# Stack: hysteria + hysteria-exit + redis + nest-app + nginx (:8080 API)
#
# 1. Copy deploy/nodes.example.json → deploy/nodes.json (single object, not an array)
# 2. Run on VPS: sudo ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NODES_FILE="${NODES_FILE:-deploy/nodes.json}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-info@tunnelrover.com}"

TEMPLATE_NGINX="templates/node-single.conf.template"
TEMPLATE_HYSTERIA_SERVER="templates/hysteria-server-config.yaml.template"
TEMPLATE_HYSTERIA_EXIT="templates/hysteria-exit-client.yaml.template"

GENERATED_DIR="generated"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install: apt install jq"
  exit 1
fi

if [[ ! -f "$NODES_FILE" ]]; then
  echo "Missing $NODES_FILE — copy deploy/nodes.example.json and edit exit fields."
  exit 1
fi

NODE_TYPE="$(jq -r 'type' "$NODES_FILE")"
if [[ "$NODE_TYPE" == "array" ]]; then
  NODE_COUNT="$(jq length "$NODES_FILE")"
  if [[ "$NODE_COUNT" -ne 1 ]]; then
    echo "Hysteria middle-node supports exactly one node per VPS."
    echo "Use a single JSON object in deploy/nodes.json (not an array of $NODE_COUNT nodes)."
    exit 1
  fi
  NODES_FILE_TMP="$(mktemp)"
  jq '.[0]' "$NODES_FILE" > "$NODES_FILE_TMP"
  NODES_FILE="$NODES_FILE_TMP"
  trap 'rm -f "$NODES_FILE_TMP"' EXIT
elif [[ "$NODE_TYPE" != "object" ]]; then
  echo "$NODES_FILE must be a JSON object with one node definition."
  exit 1
fi

NAME="$(jq -r '.name' "$NODES_FILE")"
DOMAIN="$(jq -r '.domain' "$NODES_FILE")"
EXIT_ADDRESS="$(jq -r '.exit.address' "$NODES_FILE")"
EXIT_PORT="$(jq -r '.exit.port // 443' "$NODES_FILE")"
EXIT_AUTH="$(jq -r '.exit.auth' "$NODES_FILE")"
EXIT_SNI="$(jq -r '.exit.sni // .exit.address' "$NODES_FILE")"
NODE_TOKEN_VALUE="$(jq -r '.nodeToken // empty' "$NODES_FILE")"
TRAFFIC_STATS_SECRET="$(openssl rand -hex 32)"

if [[ -z "$NAME" || "$NAME" == "null" || -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
  echo "name and domain are required in $NODES_FILE"
  exit 1
fi

if [[ -z "$EXIT_ADDRESS" || "$EXIT_ADDRESS" == "null" || -z "$EXIT_AUTH" || "$EXIT_AUTH" == "null" ]]; then
  echo "exit.address and exit.auth are required in $NODES_FILE"
  exit 1
fi

if [[ -z "$NODE_TOKEN_VALUE" || "$NODE_TOKEN_VALUE" == "null" ]]; then
  NODE_TOKEN_VALUE="${NODE_TOKEN:-}"
fi

if [[ -z "$NODE_TOKEN_VALUE" ]]; then
  echo "nodeToken is required in $NODES_FILE"
  exit 1
fi

echo "==> Generating Hysteria middle-node: $NAME ($DOMAIN) → exit $EXIT_ADDRESS:$EXIT_PORT"

rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR/nginx"

sed \
  -e "s|{{DOMAIN}}|$DOMAIN|g" \
  "$TEMPLATE_NGINX" > "$GENERATED_DIR/nginx/node.conf"

sed \
  -e "s|{{TRAFFIC_STATS_SECRET}}|$TRAFFIC_STATS_SECRET|g" \
  "$TEMPLATE_HYSTERIA_SERVER" > "$GENERATED_DIR/hysteria-server-config.yaml"

sed \
  -e "s|{{EXIT_ADDRESS}}|$EXIT_ADDRESS|g" \
  -e "s|{{EXIT_PORT}}|$EXIT_PORT|g" \
  -e "s|{{EXIT_AUTH}}|$EXIT_AUTH|g" \
  -e "s|{{EXIT_SNI}}|$EXIT_SNI|g" \
  "$TEMPLATE_HYSTERIA_EXIT" > "$GENERATED_DIR/hysteria-exit-client.yaml"

cat > "$GENERATED_DIR/.env" <<EOF
NODE_TOKEN=${NODE_TOKEN_VALUE}
HYSTERIA_TRAFFIC_SECRET=${TRAFFIC_STATS_SECRET}
REDIS_HOST=redis
REDIS_PORT=6379
HYSTERIA_HOST=hysteria
HYSTERIA_TRAFFIC_PORT=9999
TEST_MODE=false
EOF

if [[ "${SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh
    systemctl enable --now docker
  fi

  apt-get update -y
  apt-get install -y certbot jq docker-compose-plugin iptables-persistent nano

  if [[ ! -f "/swapfile" ]]; then
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
  fi
fi

if [[ "${SKIP_CERTBOT:-0}" != "1" ]]; then
  echo "==> Obtaining certificate for: $DOMAIN"
  certbot certonly \
    --standalone \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    --no-eff-email
fi

CERT_LIVE_NAME="$DOMAIN"
if [[ ! -f "/etc/letsencrypt/live/$CERT_LIVE_NAME/fullchain.pem" ]]; then
  CERT_LIVE_NAME="$(basename "$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | head -1)")"
fi

mkdir -p ./nginx-certs
cp "/etc/letsencrypt/live/$CERT_LIVE_NAME/fullchain.pem" ./nginx-certs/fullchain.pem
cp "/etc/letsencrypt/live/$CERT_LIVE_NAME/privkey.pem" ./nginx-certs/privkey.pem
chmod 644 ./nginx-certs/*.pem

assert_mount_file() {
  local path="$1"
  if [[ -d "$path" ]]; then
    echo "ERROR: '$path' is a directory, but Docker needs a file."
    exit 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "ERROR: required file missing: $path"
    exit 1
  fi
}

echo "==> Preflight mount paths..."
assert_mount_file nginx.conf
assert_mount_file index.html
assert_mount_file promtail-config.yaml
assert_mount_file "$GENERATED_DIR/hysteria-server-config.yaml"
assert_mount_file "$GENERATED_DIR/hysteria-exit-client.yaml"
assert_mount_file "$GENERATED_DIR/nginx/node.conf"
assert_mount_file "$GENERATED_DIR/.env"

echo "==> Starting stack..."
docker compose up -d --build

echo "Done. Hysteria middle-node ($NAME):"
echo "  hysteria2://<USER_UUID>@$DOMAIN:443?sni=$DOMAIN"
echo "  https://$DOMAIN:8080  → nest-app control API"
