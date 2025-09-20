#!/bin/bash
set -e
# Update and install docker
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
usermod -aG docker ubuntu || true

# Install docker compose v2
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Create deploy folder and placeholder docker-compose
DEPLOY_DIR=/home/ubuntu/deploy
mkdir -p $DEPLOY_DIR
chown ubuntu:ubuntu $DEPLOY_DIR

cat > $DEPLOY_DIR/docker-compose.yml <<'EOF'
version: "3.8"
services:
  backend:
    image: YOUR_DOCKERHUB_USER/project-backend:latest
    restart: always
    environment:
      - PORT=3000
    ports:
      - "3000:3000"

  frontend:
    image: YOUR_DOCKERHUB_USER/project-frontend:latest
    restart: always
    ports:
      - "80:80"
EOF

chown ubuntu:ubuntu $DEPLOY_DIR/docker-compose.yml

# Start docker-compose
cd $DEPLOY_DIR
/usr/local/lib/docker/cli-plugins/docker-compose up -d
