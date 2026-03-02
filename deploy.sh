#!/bin/bash

set -e

NODE_NAME="node-nl-1"
ROVER_NODE_HOST="$NODE_NAME.tunnelrover.com"

sed -i "s/container_name:[[:space:]]*nginx-proxy/container_name: nginx-proxy-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*nest-app/container_name: nest-app-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*ss-rust/container_name: ss-rust-$NODE_NAME/g" docker-compose.yaml

sed -i "s|http://nest-app:|http://nest-app-$NODE_NAME:|g" nginx.conf
sed -i "s|server-node.tunnelrover.com;|$ROVER_NODE_HOST;|g" nginx.conf

sudo apt update -y && sudo apt install certbot iptables-persistent -y

sudo certbot certonly \
  --standalone \
  -d "$ROVER_NODE_HOST" \
  --non-interactive \
  --agree-tos \
  --email info@tunnelrover.com \
  --no-eff-email

mkdir -p ./nginx-certs
cp /etc/letsencrypt/live/$ROVER_NODE_HOST/fullchain.pem ./nginx-certs/fullchain.pem
cp /etc/letsencrypt/live/$ROVER_NODE_HOST/privkey.pem   ./nginx-certs/privkey.pem
chmod 644 ./nginx-certs/*.pem

sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

sudo iptables -A INPUT -i lo -j ACCEPT

sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

sudo iptables -A FORWARD -p tcp --dport 8388:8488 -j ACCEPT
sudo iptables -A FORWARD -p udp --dport 8388:8488 -j ACCEPT

sudo netfilter-persistent save

docker compose up -d

