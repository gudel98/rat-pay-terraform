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
    rm -rf rat-pay-old
    mv rat-pay rat-pay-old
    
    git clone ${repository_url}
    
    echo "Synchronizing secrets..."
    if [ -f "rat-pay-old/k8s/secrets.yaml" ]; then
        cp rat-pay-old/k8s/secrets.yaml rat-pay/k8s/secrets.yaml
    else
        echo "WARNING: secrets.yaml not found!"
    fi
else
    echo "rat-pay directory not found. Cloning fresh..."
    git clone ${repository_url}
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
minikube ssh -- docker rmi -f rat_pay_app:latest || true

echo "Loading new image into minikube..."
minikube image load rat_pay_app:latest

echo "Applying k8s manifests..."
kubectl apply -R -f k8s/

echo "Restaring rat_pay_app pod..."
kubectl rollout restart deployment rat-pay-app
kubectl wait --for=condition=available --timeout=300s deployment/kafka || echo "Kafka deployment not found or timed out"
kubectl wait --for=condition=available --timeout=300s deployment/postgres || echo "Postgres deployment not found or timed out"
kubectl wait --for=condition=available --timeout=300s deployment/rat-pay-app || echo "App deployment not found or timed out"
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
