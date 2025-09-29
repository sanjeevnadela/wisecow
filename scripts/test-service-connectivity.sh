#!/bin/bash

# Test script to verify service connectivity in Kubernetes

set -euo pipefail

echo "=== Testing Service Connectivity ==="

# Check if we're in a Kubernetes cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Not connected to a Kubernetes cluster"
    exit 1
fi

echo "1. Checking service exists..."
kubectl get svc wisecow-service || {
    echo "Service 'wisecow-service' not found!"
    exit 1
}

echo "2. Checking service endpoints..."
kubectl get endpoints wisecow-service

echo "3. Checking pods are ready..."
kubectl get pods -l app=wisecow -o wide

echo "4. Testing DNS resolution..."
kubectl run test-dns-$(date +%s) --image=busybox --rm -it --restart=Never -- nslookup wisecow-service || echo "DNS test failed"

echo "5. Testing HTTP connectivity..."
kubectl run test-http-$(date +%s) --image=busybox --rm -it --restart=Never -- wget -qO- --timeout=10 http://wisecow-service:80 || echo "HTTP test failed"

echo "6. Running health checker..."
python3 scripts/k8s-app-health-checker.py -k -n default -a wisecow http://wisecow-service:80

echo "=== Test Complete ==="
