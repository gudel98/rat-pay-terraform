#!/bin/bash
# User data script for initial EC2 setup
# This runs once when the instance is first created

set -e
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -y
sudo apt-get upgrade -y

# Configure needrestart to be non-interactive and auto-restart services
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
sudo sed -i 's/#$nrconf{kernelhints} = -1;/$nrconf{kernelhints} = -1;/g' /etc/needrestart/needrestart.conf

# Check if a reboot is required due to kernel updates
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required by system updates. Scheduling reboot..."
    # We can't reboot immediately in this script as it might break the terraform run if it expects ssh to stay up
    # However, if this is user-data (cloud-init), it runs on boot.
    # If run via SSH from terraform, a reboot will kill the connection.
    # Best practice for terraform remote-exec: avoid rebooting inside the script if possible, or handle it carefully.
    
    # For now, let's just log it. The user sees the message.
    echo "WARNING: Kernel update pending. You may need to reboot the instance manually for changes to take effect."
else
    echo "No immediate reboot required."
fi

sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    unzip \
    jq \
    conntrack

if ! command -v docker &> /dev/null; then
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
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

if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
else
  echo "kubectl is already installed, skipping..."
fi

if ! command -v minikube &> /dev/null; then
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm minikube-linux-amd64
else
  echo "Minikube is already installed, skipping..."
fi

echo "Verifying installations..."
docker --version || { echo "ERROR: Docker installation failed"; exit 1; }
kubectl version --client || { echo "ERROR: kubectl installation failed"; exit 1; }
minikube version || { echo "ERROR: Minikube installation failed"; exit 1; }

echo "Minikube setup script completed at $(date)" >> /var/log/minikube-setup.log
