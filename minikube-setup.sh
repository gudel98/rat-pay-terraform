#!/bin/bash
# User data script for initial EC2 setup
# This runs once when the instance is first created

set -e

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

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



# Create Minikube startup script
cat > /home/ubuntu/start-minikube.sh <<'SCRIPT'
#!/bin/bash
set -e

echo "Starting Minikube..."
minikube start --driver=docker --memory=2048 --cpus=2

echo "Configuring kubectl to use Minikube context..."
minikube kubectl -- config use-context minikube

echo "Enabling Minikube addons..."
minikube addons enable ingress
minikube addons enable metrics-server

echo "Forwarding ports..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt install iptables-persistent -y
sudo netfilter-persistent save
sudo tee /etc/systemd/system/port-forward.service > /dev/null <<'PORT_SCRIPT'
[Unit]
Description=Port-forward ingress-nginx-controller
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kubectl port-forward --address=0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 8080:80 8443:443
Restart=always
RestartSec=5
User=ubuntu
Environment=KUBECONFIG=/home/ubuntu/.kube/config

[Install]
WantedBy=multi-user.target
PORT_SCRIPT
sudo systemctl daemon-reload
sudo systemctl enable port-forward

echo ""
echo "✅ Minikube started successfully!"
echo ""
echo "Useful commands:"
echo "  kubectl get nodes           - Check cluster status"
echo "  kubectl get pods -A         - List all pods"
echo "  minikube dashboard          - Open Kubernetes dashboard"
echo "  minikube service <name>     - Get service URL"
SCRIPT

chmod +x /home/ubuntu/start-minikube.sh
chown ubuntu:ubuntu /home/ubuntu/start-minikube.sh



# Create cluster startup script
cat > /home/ubuntu/start-cluster.sh <<'SCRIPT'
#!/bin/bash
set -e

echo "Disabling port-forwarding..."
sudo systemctl stop port-forward
if sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null; then
    sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
fi
if sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null; then
    sudo iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
fi

cd rat-pay/
echo "Building rat_pay_app image..."
docker build -t rat_pay_app:latest .
echo "Loading image into minikube..."
minikube image load rat_pay_app:latest
echo "Applying k8s manifests..."
kubectl apply -R -f k8s/

echo "Enabling port-forwarding..."
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
fi
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
fi
sudo iptables -t nat -L PREROUTING --line-numbers
sudo systemctl start port-forward
sudo systemctl status port-forward

echo ""
echo "✅ RatPay cluster started successfully!"
echo ""
echo "https://rat-pay.online/up"
SCRIPT

chmod +x /home/ubuntu/start-cluster.sh
chown ubuntu:ubuntu /home/ubuntu/start-cluster.sh



# Create script for application redeployment
cat > /home/ubuntu/redeploy-app.sh <<'SCRIPT'
#!/bin/bash
set -e

echo "Disabling port-forwarding..."
sudo systemctl stop port-forward
if sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null; then
    sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
fi
if sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null; then
    sudo iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
fi

echo "Removing an existing applciation pod..."
kubectl scale deployment rat-pay-app --replicas=0
echo "Deleting current rat_pay_app docker image..."
minikube ssh
docker rmi rat_pay_app
exit
docker rmi rat_pay_app:latest
rm -rf rat-pay-old
mv rat-pay rat-pay-old
echo "Downloading new application version from GitHub..."
git clone https://github.com/gudel98/rat-pay.git
echo "Synchronizing secrets..."
cp rat-pay-old/k8s/secrets.yaml rat-pay/k8s/secrets.yaml
rm rat-pay/k8s/secrets.yaml.example
cd rat-pay/
echo "Building rat_pay_app image..."
docker build -t rat_pay_app:latest .
echo "Loading image into minikube..."
minikube image load rat_pay_app:latest
echo "Restaring rat_pay_app pod..."
kubectl scale deployment rat-pay-app --replicas=1
kubectl rollout restart deployment rat-pay-app
kubectl get pods -A

echo "Enabling port-forwarding..."
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
fi
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
fi
sudo iptables -t nat -L PREROUTING --line-numbers
sudo systemctl start port-forward
sudo systemctl status port-forward

echo ""
echo "✅ RatPay application updated successfully!"
echo ""
echo "https://rat-pay.online/up"
SCRIPT

chmod +x /home/ubuntu/redeploy-app.sh
chown ubuntu:ubuntu /home/ubuntu/redeploy-app.sh



# Log completion
echo "Minikube setup script completed at $(date)" >> /var/log/minikube-setup.log
