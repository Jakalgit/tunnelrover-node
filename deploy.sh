#!/bin/bash
set -euo pipefail

NODE_NAME="node-nl-1"
ROVER_NODE_HOST=""
XRAY_PRIVATE_KEY=""
SWAP_SIZE="3G"
CERTBOT_EMAIL="info@tunnelrover.com"

usage() {
  cat <<EOF
Usage: sudo ./deploy.sh [options]

  --name NAME       Node name (default: node-nl-1)
                    Host becomes NAME.tunnelrover.com unless --host is set
  --host FQDN       Public hostname / REALITY SNI
  --privkey KEY     Reuse an existing REALITY private key
  --email EMAIL     Let's Encrypt email (default: ${CERTBOT_EMAIL})
  -h, --help        Show this help

Prints the REALITY public key at the end — put it in the backend node record
together with shortId from xray-config.json and SNI = host.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --name)
      NODE_NAME="$2"
      shift 2
      ;;
    --host)
      ROVER_NODE_HOST="$2"
      shift 2
      ;;
    --privkey)
      XRAY_PRIVATE_KEY="$2"
      shift 2
      ;;
    --email)
      CERTBOT_EMAIL="$2"
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

if [[ -z "$ROVER_NODE_HOST" ]]; then
  ROVER_NODE_HOST="${NODE_NAME}.tunnelrover.com"
fi

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo ./deploy.sh --name ${NODE_NAME}" >&2
    exit 1
  fi
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh
  fi
  systemctl enable --now docker
  apt-get update -y
  apt-get install -y certbot iptables-persistent nano docker-compose-plugin
}

ensure_swap() {
  if [[ -f /swapfile ]]; then
    return
  fi
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
}

issue_certs() {
  certbot certonly \
    --standalone \
    -d "$ROVER_NODE_HOST" \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    --no-eff-email

  mkdir -p ./nginx-certs
  cp "/etc/letsencrypt/live/${ROVER_NODE_HOST}/fullchain.pem" ./nginx-certs/fullchain.pem
  cp "/etc/letsencrypt/live/${ROVER_NODE_HOST}/privkey.pem" ./nginx-certs/privkey.pem
  chmod 644 ./nginx-certs/*.pem
}

parse_x25519() {
  local keys="$1"
  XRAY_PRIVATE_KEY=$(echo "$keys" | awk '/[Pp]rivate/{print $NF; exit}')
  XRAY_PUBLIC_KEY=$(echo "$keys" | awk '/[Pp]ublic/{print $NF; exit}')
}

ensure_reality_keys() {
  if [[ -n "$XRAY_PRIVATE_KEY" ]]; then
    echo "Using provided REALITY private key"
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

patch_files() {
  echo "XRAY_HOST=xray-${NODE_NAME}" >> .env

  sed -i "s/container_name:[[:space:]]*nginx-proxy/container_name: nginx-proxy-${NODE_NAME}/g" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*nest-app/container_name: nest-app-${NODE_NAME}/g" docker-compose.yaml
  sed -i "s/container_name:[[:space:]]*xray/container_name: xray-${NODE_NAME}/g" docker-compose.yaml

  sed -i "s|http://nest-app:|http://nest-app-${NODE_NAME}:|g" nginx.conf
  sed -i "s|server-node.tunnelrover.com|${ROVER_NODE_HOST}|g" nginx.conf
  sed -i "s|server-node.tunnelrover.com|${ROVER_NODE_HOST}|g" xray-config.json
  sed -i "s|\"privateKey\": \"\"|\"privateKey\": \"${XRAY_PRIVATE_KEY}\"|" xray-config.json
}

require_root
install_docker
ensure_swap
issue_certs
ensure_reality_keys
patch_files

docker compose up -d

echo
echo "Node host / REALITY SNI: ${ROVER_NODE_HOST}"
echo "REALITY public key:      ${XRAY_PUBLIC_KEY:-'(reuse --privkey, public key not printed)'}"
echo "REALITY shortId:         $(grep -A1 shortIds xray-config.json | tail -n1 | tr -d ' \"')"
echo "Camouflage site:         http://${ROVER_NODE_HOST}/"
echo "Control API:             https://${ROVER_NODE_HOST}:8080/"
