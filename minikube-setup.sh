#!/bin/bash
# User data script for initial EC2 setup
# This runs once when the instance is first created

set -e

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y
# Restart services that need it
sudo needrestart -r a

# Install basic tools
sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    unzip \
    jq \
    conntrack

# Install Docker (idempotent - skip if already installed)
if ! command -v docker &> /dev/null; then
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  # Remove existing keyring if it exists to avoid prompts
  sudo rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker ubuntu
else
  echo "Docker is already installed, skipping..."
fi

# Install kubectl (idempotent - skip if already installed)
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
else
  echo "kubectl is already installed, skipping..."
fi

# Install Minikube (idempotent - skip if already installed)
if ! command -v minikube &> /dev/null; then
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm minikube-linux-amd64
else
  echo "Minikube is already installed, skipping..."
fi

# Verify installations
echo "Verifying installations..."
docker --version || { echo "ERROR: Docker installation failed"; exit 1; }
kubectl version --client || { echo "ERROR: kubectl installation failed"; exit 1; }
minikube version || { echo "ERROR: Minikube installation failed"; exit 1; }

# Log completion
echo "Minikube setup script completed at $(date)" >> /var/log/minikube-setup.log
