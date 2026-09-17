#!/bin/bash

set -e

echo "======================================"
echo "     Docker Engine Installation"
echo "======================================"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "sudo ./idocker.sh"
    exit 1
fi

# Get actual login user
REAL_USER="${SUDO_USER:-$USER}"

echo ""
echo "[1/8] Updating APT..."

apt-get update

echo ""
echo "[2/8] Installing prerequisites..."

apt-get install -y \
    ca-certificates \
    curl

echo ""
echo "[3/8] Removing old Docker repository configuration..."

rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/sources.list.d/docker.sources

echo ""
echo "[4/8] Adding Docker GPG key..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

echo ""
echo "[5/8] Adding Docker official repository..."

. /etc/os-release

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list

echo ""
echo "[6/8] Installing Docker Engine..."

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo ""
echo "[7/8] Starting Docker..."

systemctl enable docker
systemctl enable containerd

systemctl start containerd
systemctl start docker

echo ""
echo "[8/8] Creating app-net network..."

# apps/*/compose.yml and kafka/compose.yml create app-net implicitly on
# first "up", but docker-compose.monitoring-agent.yml and
# docker-compose.nginx.yml declare it external:true and fail if it
# doesn't exist yet — create it here so startup order never matters.
if ! docker network inspect app-net >/dev/null 2>&1; then
    docker network create app-net
else
    echo "app-net already exists, skipping."
fi

echo ""
echo "======================================"
echo " Adding user to docker group"
echo "======================================"

if id "$REAL_USER" >/dev/null 2>&1; then
    usermod -aG docker "$REAL_USER"
fi

echo ""
echo "======================================"
echo " Docker Installation Completed"
echo "======================================"

echo ""
echo "Docker:"
docker --version

echo ""
echo "Docker Compose:"
docker compose version

echo ""
echo "Docker Service:"
systemctl is-active docker

echo ""
echo "Containerd:"
systemctl is-active containerd

echo ""
echo "app-net network:"
docker network inspect app-net --format '{{.Name}} ({{.Id}})'

echo ""
echo "======================================"
echo " IMPORTANT"
echo "======================================"
echo ""
echo "Run:"
echo ""
echo "    newgrp docker"
echo ""
echo "Then:"
echo ""
echo "    docker ps"
echo ""