#!/bin/bash
set -euo pipefail

NODE_NAME="node-nl-1"
ROVER_NODE_HOST="${NODE_NAME}.tunnelrover.com"
SWAP_SIZE="3G"
CERTBOT_EMAIL="info@tunnelrover.com"
TEMPLATE_DIR=".deploy-templates"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --name)
      NODE_NAME="$2"
      ROVER_NODE_HOST="${NODE_NAME}.tunnelrover.com"
      shift 2
      ;;
    --host)
      ROVER_NODE_HOST="$2"
      shift 2
      ;;
    --email)
      CERTBOT_EMAIL="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: sudo ./deploy.sh [--name node-nl-1] [--host fqdn] [--email email]" >&2
      exit 1
      ;;
  esac
done

TEMPLATE_FILES=(docker-compose.yaml nginx.conf xray-config.json)

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

upsert_env() {
  local key="$1"
  local value="$2"
  touch .env
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

patch_files() {
  restore_templates

  sed -i "s/container_name:[[:space:]]*nginx-proxy$/container_name: nginx-proxy-${NODE_NAME}/" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*nest-app$/container_name: nest-app-${NODE_NAME}/" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*xray$/container_name: xray-${NODE_NAME}/" docker-compose.yaml

  sed -i "s|http://nest-app:|http://nest-app-${NODE_NAME}:|g" nginx.conf
  sed -i "s|http://xray:|http://xray-${NODE_NAME}:|g" nginx.conf
  sed -i "s|server-node.tunnelrover.com|${ROVER_NODE_HOST}|g" nginx.conf
  sed -i "s|server-node.tunnelrover.com|${ROVER_NODE_HOST}|g" xray-config.json

  upsert_env XRAY_HOST "xray-${NODE_NAME}"
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
    if command -v docker >/dev/null 2>&1; then
      docker compose down || true
    fi
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

docker compose up -d

echo
echo "Host: ${ROVER_NODE_HOST}"
echo "xhttp host: $(grep -A2 xhttpSettings xray-config.json | grep host | awk -F '"' '{print $4}')"
