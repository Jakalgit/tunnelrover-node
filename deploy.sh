#!/bin/bash
# Middle-node deploy: one shared nginx + N relay stacks (xray + nest-app per domain).
#
# 1. Copy deploy/nodes.example.json → deploy/nodes.json and fill exit credentials.
# 2. Run on VPS: sudo ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NODES_FILE="${NODES_FILE:-deploy/nodes.json}"
SWAP_SIZE="${SWAP_SIZE:-3G}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-info@tunnelrover.com}"

TEMPLATE_NGINX="templates/node-single.conf.template"
TEMPLATE_XRAY="templates/xray-config.json.template"

GENERATED_NGINX_DIR="generated/nginx/nodes"
GENERATED_NODES_DIR="generated/nodes"
COMPOSE_NODES_FILE="generated/docker-compose.nodes.yaml"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install: apt install jq"
  exit 1
fi

if [[ ! -f "$NODES_FILE" ]]; then
  echo "Missing $NODES_FILE — copy deploy/nodes.example.json and edit exit fields."
  exit 1
fi

NODE_COUNT="$(jq length "$NODES_FILE")"
if [[ "$NODE_COUNT" -lt 1 ]]; then
  echo "No nodes defined in $NODES_FILE"
  exit 1
fi

echo "==> Generating configs for $NODE_COUNT node(s)..."

rm -rf generated
mkdir -p "$GENERATED_NGINX_DIR" "$GENERATED_NODES_DIR"

CERT_DOMAINS=()

# --- per-node: nginx snippet, xray config, nest .env ---
for i in $(seq 0 $((NODE_COUNT - 1))); do
  NAME="$(jq -r ".[$i].name" "$NODES_FILE")"
  DOMAIN="$(jq -r ".[$i].domain" "$NODES_FILE")"
  EXIT_ADDRESS="$(jq -r ".[$i].exit.address" "$NODES_FILE")"
  EXIT_ID="$(jq -r ".[$i].exit.id" "$NODES_FILE")"
  EXIT_SNI="$(jq -r ".[$i].exit.sni" "$NODES_FILE")"
  EXIT_PUBLIC_KEY="$(jq -r ".[$i].exit.publicKey" "$NODES_FILE")"
  EXIT_SHORT_ID="$(jq -r ".[$i].exit.shortId" "$NODES_FILE")"

  if [[ -z "$NAME" || "$NAME" == "null" || -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
    echo "Node #$i: name and domain are required"
    exit 1
  fi

  CERT_DOMAINS+=("$DOMAIN")
  NODE_DIR="$GENERATED_NODES_DIR/$NAME"
  mkdir -p "$NODE_DIR"

  sed \
    -e "s|{{NODE_NAME}}|$NAME|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$TEMPLATE_NGINX" > "$GENERATED_NGINX_DIR/$NAME.conf"

  sed \
    -e "s|{{EXIT_ADDRESS}}|$EXIT_ADDRESS|g" \
    -e "s|{{EXIT_ID}}|$EXIT_ID|g" \
    -e "s|{{EXIT_SNI}}|$EXIT_SNI|g" \
    -e "s|{{EXIT_PUBLIC_KEY}}|$EXIT_PUBLIC_KEY|g" \
    -e "s|{{EXIT_SHORT_ID}}|$EXIT_SHORT_ID|g" \
    "$TEMPLATE_XRAY" > "$NODE_DIR/xray-config.json"

  cat > "$NODE_DIR/.env" <<EOF
XRAY_HOST=xray-$NAME
XRAY_PORT=10085
NODE_TOKEN=${NODE_TOKEN:-change-me}
TEST_MODE=false
EOF

  echo "  - $NAME ($DOMAIN)"
done

# --- docker-compose fragment: xray + nest-app per node ---
{
  echo 'version: "3.9"'
  echo ''
  echo 'services:'

  for i in $(seq 0 $((NODE_COUNT - 1))); do
    NAME="$(jq -r ".[$i].name" "$NODES_FILE")"
    NODE_DIR="$GENERATED_NODES_DIR/$NAME"

    cat <<EOF
  xray-$NAME:
    image: teddysun/xray
    container_name: xray-$NAME
    volumes:
      - ./$NODE_DIR/xray-config.json:/etc/xray/config.json:ro
    command: xray run -config /etc/xray/config.json
    networks:
      - instance-network
    restart: unless-stopped

  nest-app-$NAME:
    container_name: nest-app-$NAME
    restart: always
    build:
      context: .
      dockerfile: Dockerfile.nestjs
    env_file:
      - ./$NODE_DIR/.env
    networks:
      - instance-network
    depends_on:
      - xray-$NAME

EOF
  done
} > "$COMPOSE_NODES_FILE"

echo "==> Generated $COMPOSE_NODES_FILE and nginx snippets in $GENERATED_NGINX_DIR"

# --- bootstrap (skip if SKIP_BOOTSTRAP=1 for re-deploy) ---
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

# --- TLS: one certificate with all node domains (SAN) ---
DOMAIN_ARGS=()
for d in "${CERT_DOMAINS[@]}"; do
  DOMAIN_ARGS+=(-d "$d")
done

PRIMARY_DOMAIN="${CERT_DOMAINS[0]}"

if [[ "${SKIP_CERTBOT:-0}" != "1" ]]; then
  echo "==> Obtaining certificate for: ${CERT_DOMAINS[*]}"
  certbot certonly \
    --standalone \
    "${DOMAIN_ARGS[@]}" \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    --no-eff-email
fi

mkdir -p ./nginx-certs
cp "/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem" ./nginx-certs/fullchain.pem
cp "/etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem" ./nginx-certs/privkey.pem
chmod 644 ./nginx-certs/*.pem

assert_mount_file() {
  local path="$1"
  if [[ -d "$path" ]]; then
    echo ""
    echo "ERROR: '$path' is a directory, but Docker needs a file."
    echo "  This usually happens after a failed start when the file was missing."
    echo "  Fix:  rm -rf '$path'"
    echo "  Then copy the file from the repo (git checkout -- '$path' or re-upload)."
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

if [[ ! -d "$GENERATED_NGINX_DIR" ]] || ! compgen -G "$GENERATED_NGINX_DIR/*.conf" >/dev/null; then
  echo "ERROR: no nginx node configs in $GENERATED_NGINX_DIR"
  exit 1
fi

if [[ ! -f "$COMPOSE_NODES_FILE" ]]; then
  echo "ERROR: missing $COMPOSE_NODES_FILE"
  exit 1
fi

echo "==> Starting stack..."
docker compose -f docker-compose.yaml -f "$COMPOSE_NODES_FILE" up -d --build

echo "Done. Shared nginx routes by server_name:"
for d in "${CERT_DOMAINS[@]}"; do
  echo "  https://$d/ws  → xray relay"
  echo "  https://$d:8080  → nest-app control API"
done
