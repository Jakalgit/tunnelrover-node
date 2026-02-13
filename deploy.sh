#!/bin/bash

set -e

ROVER_NODE_HOST="web-node-1.tunnelrover.com"

sudo iptables -F
sudo iptables -X

sudo apt update -y && sudo apt install certbot iptables-persistent -y

sudo certbot certonly \
  --standalone \
  -d "$ROVER_NODE_HOST" \
  --non-interactive \
  --agree-tos \
  --email info@tunnelrover.com \
  --no-eff-email

mkdir -p ./nginx-certs
cp /etc/letsencrypt/live/$ROVER_NODE_HOST/fullchain.pem ./nginx-certs/
cp /etc/letsencrypt/live/$ROVER_NODE_HOST/privkey.pem   ./nginx-certs/
chmod 644 ./nginx-certs/*.pem

sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

sudo iptables -A FORWARD -p tcp --dport 8388:8488 -j ACCEPT
sudo iptables -A FORWARD -p udp --dport 8388:8488 -j ACCEPT

sudo netfilter-persistent save

docker compose up -d

