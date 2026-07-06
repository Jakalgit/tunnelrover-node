#!/bin/bash

set -e

NODE_NAME="${NODE_NAME:-node-nl-1}"
ROVER_NODE_HOST="${ROVER_NODE_HOST:-$NODE_NAME.tunnelrover.com}"
SWAP_SIZE="${SWAP_SIZE:-3G}"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --node-name)
      NODE_NAME="$2"
      ROVER_NODE_HOST="$NODE_NAME.tunnelrover.com"
      shift 2
      ;;
    --host)
      ROVER_NODE_HOST="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${NODE_TOKEN:-}" ]]; then
  echo "Set NODE_TOKEN before deploy (same as accessToken in Tunnel Rover DB)."
  exit 1
fi

TRAFFIC_STATS_SECRET="${TRAFFIC_STATS_SECRET:-$(openssl rand -hex 32)}"

curl -sSL https://get.docker.com/ | CHANNEL=stable sh
systemctl enable --now docker
apt-get update -y && apt-get install -y certbot iptables-persistent nano docker-compose-plugin

if [[ ! -f "/swapfile" ]]; then
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

sed -i "s/container_name:[[:space:]]*nginx-proxy/container_name: nginx-proxy-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*nest-app/container_name: nest-app-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*hysteria/container_name: hysteria-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*redis/container_name: redis-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*promtail/container_name: promtail-$NODE_NAME/g" docker-compose.yaml

sed -i "s|server_name server-node.tunnelrover.com;|server_name $ROVER_NODE_HOST;|g" nginx.conf

sed -i "s|{{TRAFFIC_STATS_SECRET}}|$TRAFFIC_STATS_SECRET|g" hysteria-config.yaml

cat > .env <<EOF
NODE_TOKEN=$NODE_TOKEN
HYSTERIA_TRAFFIC_SECRET=$TRAFFIC_STATS_SECRET
REDIS_HOST=redis
REDIS_PORT=6379
HYSTERIA_HOST=hysteria
HYSTERIA_TRAFFIC_PORT=9999
TEST_MODE=false
EOF

certbot certonly \
  --standalone \
  -d "$ROVER_NODE_HOST" \
  --non-interactive \
  --agree-tos \
  --email info@tunnelrover.com \
  --no-eff-email

mkdir -p ./nginx-certs
cp "/etc/letsencrypt/live/$ROVER_NODE_HOST/fullchain.pem" ./nginx-certs/fullchain.pem
cp "/etc/letsencrypt/live/$ROVER_NODE_HOST/privkey.pem" ./nginx-certs/privkey.pem
chmod 644 ./nginx-certs/*.pem

docker compose up -d --build

echo "Done."
echo "  Hysteria: $ROVER_NODE_HOST:443 (UDP+TCP)"
echo "  Nest API: https://$ROVER_NODE_HOST:8080/user"
echo "  Client auth: hysteria2://<USER_UUID>@$ROVER_NODE_HOST:443?sni=$ROVER_NODE_HOST"
