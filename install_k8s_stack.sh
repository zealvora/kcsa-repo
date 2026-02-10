#!/bin/bash

# ==========================================
# Automated Installer: Kubeadm 1.35 + Kind + Docker
# OS: Ubuntu 24.04 LTS
# ==========================================

set -e # Exit immediately if a command exits with a non-zero status

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}[INFO] Starting installation...${NC}"

# 1. System Update & Dependencies
# ------------------------------------------
echo -e "${GREEN}[1/6] Updating system and installing dependencies...${NC}"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg lsb-release software-properties-common

# 2. Configure System Prerequisites (Swap & Sysctl)
# ------------------------------------------
echo -e "${GREEN}[2/6] Configuring Kernel modules and Sysctl for Kubernetes...${NC}"

# Disable Swap (Critical for Kubeadm)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 3. Install Docker Engine
# ------------------------------------------
echo -e "${GREEN}[3/6] Installing Docker Engine...${NC}"

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Containerd (Important for Kubeadm compatibility)
echo -e "${BLUE}[INFO] Configuring containerd for systemd cgroups...${NC}"
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# Set SystemdCgroup = true
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# Add current user to docker group (avoids sudo for docker commands)
sudo usermod -aG docker $USER

# 4. Install Kubeadm, Kubelet, Kubectl (v1.35)
# ------------------------------------------
echo -e "${GREEN}[4/6] Installing Kubernetes 1.35 components...${NC}"

# Add Kubernetes GPG key (pkgs.k8s.io)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

# Add Kubernetes v1.35 Repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install packages
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Enable Kubelet service (it will crash loop until configured, this is normal)
sudo systemctl enable --now kubelet

# 5. Install Kind (Kubernetes IN Docker)
# ------------------------------------------
echo -e "${GREEN}[5/6] Installing Kind...${NC}"

# Download latest stable binary
# Note: Kind binary version handles multiple K8s versions. 
# You specify the node image version when creating a cluster if strictly needed.
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.26.0/kind-linux-amd64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.26.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# 6. Verification
# ------------------------------------------
echo -e "${GREEN}[6/6] Verifying installations...${NC}"

echo "------------------------------------------------"
echo "Docker Version: $(docker --version)"
echo "Kind Version:   $(kind --version)"
echo "Kubeadm Version: $(kubeadm version -o short)"
echo "Kubectl Version: $(kubectl version --client -o yaml | grep gitVersion)"
echo "------------------------------------------------"

echo -e "${BLUE}[INFO] Installation Complete!${NC}"
echo -e "${BLUE}[INFO] NOTE: You may need to log out and log back in for Docker group permissions to take effect.${NC}"
echo -e "${BLUE}[INFO] To create a 1.35 cluster with Kind, run:${NC}"
echo -e "       kind create cluster --image kindest/node:v1.35.0"
