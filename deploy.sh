ROVER_NODE_HOST="web-node-1.tunnelrover.com"

sudo apt update -y && sudo apt install certbot -y

sudo certbot certonly --standalone -d $ROVER_NODE_HOST

mkdir -p ./nginx-certs
cp /etc/letsencrypt/live/$ROVER_NODE_HOST/fullchain.pem ./nginx-certs/
cp /etc/letsencrypt/live/$ROVER_NODE_HOST/privkey.pem   ./nginx-certs/
chmod 644 ./nginx-certs/*.pem

docker compose up -d

