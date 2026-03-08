#!/bin/bash

set -e

NODE_NAME="node-nl-1"
ROVER_NODE_HOST="$NODE_NAME.tunnelrover.com"

EXT_IFACE="eth0"
DOCKER_SUBNET="172.17.0.0/16"

echo "XRAY_HOST=xray-$NODE_NAME" >> .env

sed -i "s/container_name:[[:space:]]*nginx-proxy/container_name: nginx-proxy-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*nest-app/container_name: nest-app-$NODE_NAME/g" docker-compose.yaml
sed -i "s/container_name:[[:space:]]*xray/container_name: xray-$NODE_NAME/g" docker-compose.yaml

sed -i "s|http://nest-app:|http://nest-app-$NODE_NAME:|g" nginx.conf
sed -i "s|http://xray:|http://xray-$NODE_NAME:|g" nginx.conf
sed -i "s|server-node.tunnelrover.com;|$ROVER_NODE_HOST;|g" nginx.conf

sudo apt update -y && sudo apt install certbot iptables-persistent git -y

sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab

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

# sudo iptables -A INPUT -i lo -j ACCEPT
# sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
#
# sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
# sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
#
# sudo iptables -A INPUT -p tcp --dport $SS_PORT_FROM:$SS_PORT_TO -j ACCEPT
# sudo iptables -A INPUT -p udp --dport $SS_PORT_FROM:$SS_PORT_TO -j ACCEPT
#
# sudo iptables -A FORWARD -i docker0 -o $EXT_IFACE -j ACCEPT
# sudo iptables -A FORWARD -i $EXT_IFACE -o docker0 -m state --state ESTABLISHED,RELATED -j ACCEPT
# sudo iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT
#
# sudo iptables -t nat -A POSTROUTING -s $DOCKER_SUBNET -o $EXT_IFACE -j MASQUERADE
#
# sudo iptables -P INPUT DROP
# sudo iptables -P FORWARD DROP
# sudo iptables -P OUTPUT ACCEPT
#
# sudo netfilter-persistent save

docker compose up -d

