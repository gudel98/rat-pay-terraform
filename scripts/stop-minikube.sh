#!/bin/bash
set -e

echo "Stopping port-forwarding service..."
if systemctl is-active --quiet port-forward; then
    sudo systemctl stop port-forward
fi
if systemctl is-enabled --quiet port-forward; then
    sudo systemctl disable port-forward
fi

if [ -f "/etc/systemd/system/port-forward.service" ]; then
    echo "Removing port-forward service file..."
    sudo rm /etc/systemd/system/port-forward.service
    sudo systemctl daemon-reload
fi

echo "Cleaning up iptables rules..."
if sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null; then
    sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
fi
if sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null; then
    sudo iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
fi

# Save the clean state to persist changes across reboots
if command -v netfilter-persistent &> /dev/null; then
    sudo netfilter-persistent save
fi

echo "Stopping Minikube cluster..."
minikube stop

echo ""
echo "✅ Minikube cluster stopped and system configuration cleaned up!"
echo "To completely delete the cluster data, run: minikube delete"
