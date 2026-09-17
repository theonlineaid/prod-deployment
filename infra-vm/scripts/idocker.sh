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
echo "[1/7] Updating APT..."

apt-get update

echo ""
echo "[2/7] Installing prerequisites..."

apt-get install -y \
    ca-certificates \
    curl

echo ""
echo "[3/7] Removing old Docker repository configuration..."

rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/sources.list.d/docker.sources

echo ""
echo "[4/7] Adding Docker GPG key..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

echo ""
echo "[5/7] Adding Docker official repository..."

. /etc/os-release

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list

echo ""
echo "[6/7] Installing Docker Engine..."

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo ""
echo "[7/7] Starting Docker..."

systemctl enable docker
systemctl enable containerd

systemctl start containerd
systemctl start docker

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