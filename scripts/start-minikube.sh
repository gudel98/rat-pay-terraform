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
