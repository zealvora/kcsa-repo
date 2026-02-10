#!/bin/bash

# ==========================================
# Kubeadm Cluster Bootstrap (Single Node)
# Kubernetes v1.35
# CNI: Calico
# ==========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${BLUE}Please run as root (use sudo)${NC}"
  exit 1
fi

echo -e "${BLUE}[INFO] Bootstrapping Kubeadm Cluster...${NC}"

# 1. Pull required images first (Optional but good for stability)
# ------------------------------------------
echo -e "${GREEN}[1/5] Pulling Control Plane Images...${NC}"
kubeadm config images pull --kubernetes-version v1.35.0

# 2. Initialize Control Plane
# ------------------------------------------
# We use 192.168.0.0/16 specifically for Calico CNI compatibility
echo -e "${GREEN}[2/5] Initializing Kubeadm...${NC}"
kubeadm init \
  --kubernetes-version v1.35.0 \
  --pod-network-cidr=192.168.0.0/16 \
  --cri-socket unix:///var/run/containerd/containerd.sock

# 3. Configure Kubeconfig for the Regular User
# ------------------------------------------
# This allows you to run kubectl without sudo
echo -e "${GREEN}[3/5] Configuring kubectl for non-root user...${NC}"

# Get the actual user who invoked sudo (not root)
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

mkdir -p "$USER_HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/.kube/config"

# Also setup for root (current session)
export KUBECONFIG=/etc/kubernetes/admin.conf

# 4. Install CNI (Calico)
# ------------------------------------------
echo -e "${GREEN}[4/5] Installing Calico Network Operator...${NC}"

# Install the Tigera operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Install Calico custom resources
# Note: This file creates the installation with the default CIDR 192.168.0.0/16
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

echo -e "${BLUE}[INFO] Waiting 30s for CNI pods to initialize...${NC}"
sleep 30

# 5. Untaint Master (Allow workloads on single node)
# ------------------------------------------
echo -e "${GREEN}[5/5] Removing Control Plane Taint (Single Node Mode)...${NC}"
# In v1.35, the taint key is usually 'node-role.kubernetes.io/control-plane'
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Cluster is Ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "To verify, run: ${BLUE}kubectl get nodes${NC} (Wait for status to become Ready)"
echo -e "To see pods:    ${BLUE}kubectl get pods -A${NC}"
