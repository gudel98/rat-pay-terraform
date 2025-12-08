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

echo "Updating application code..."
if [ -d "rat-pay" ]; then
    echo "Existing rat-pay directory found. Backing up and updating..."
    # Remove old backup if it exists
    rm -rf rat-pay-old
    # Backup current
    mv rat-pay rat-pay-old
    
    echo "Downloading new application version from GitHub..."
    git clone https://github.com/gudel98/rat-pay.git
    
    echo "Synchronizing secrets..."
    if [ -f "rat-pay-old/k8s/secrets.yaml" ]; then
        cp rat-pay-old/k8s/secrets.yaml rat-pay/k8s/secrets.yaml
    else
        echo "WARNING: secrets.yaml not found in backup!"
    fi
else
    echo "rat-pay directory not found. Cloning fresh..."
    git clone https://github.com/gudel98/rat-pay.git
    # Note: If this is a fresh clone and no backup exists, 
    # secrets.yaml must be provided manually or via Terraform provisioning
fi

if [ -f "rat-pay/k8s/secrets.yaml.example" ]; then
    rm rat-pay/k8s/secrets.yaml.example
fi

cd rat-pay/

echo "Building rat_pay_app image..."
docker build -t rat_pay_app:latest .

echo "Cleaning up old images..."
# Remove the image from minikube's docker daemon if it exists to ensure we load the new one
minikube ssh -- docker rmi rat_pay_app:latest || true

echo "Loading image into minikube..."
minikube image load rat_pay_app:latest

echo "Applying k8s manifests..."
kubectl apply -R -f k8s/

echo "Restaring rat_pay_app pod..."
# Ensure the deployment picks up the change (useful if image tag is 'latest')
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
echo "✅ RatPay cluster deployed successfully!"
echo ""
echo "https://rat-pay.online/up"
