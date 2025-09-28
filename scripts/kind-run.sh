#!/usr/bin/env bash
set -euo pipefail

# Helper to create a kind cluster (with host ports 80/443 mapped), build and load the local image,
# apply manifests and create TLS secret
# Usage: ./scripts/kind-run.sh

# Check Docker status and restart if needed
check_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Attempting to restart..."
    if [[ "$(uname)" == "Darwin" ]]; then  # macOS
      echo "Restarting Docker Desktop..."
      open --background -a Docker
      # Wait for Docker to start
      for i in {1..30}; do
        if docker info >/dev/null 2>&1; then
          echo "Docker is now running!"
          return 0
        fi
        echo "Waiting for Docker to start... ($i/30)"
        sleep 2
      done
      echo "ERROR: Docker failed to start after 60 seconds"
      exit 1
    else  # Linux
      echo "Please start Docker manually"
      exit 1
    fi
  else
    echo "Docker is already running"
  fi
}

# Check Docker status first
check_docker

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command '$1' not found."
    return 1
  }
}

for cmd in kind kubectl docker openssl; do
  if ! require_cmd "$cmd"; then
    case "$cmd" in
      kind)
        echo "Install kind: 'brew install kind' (macOS) or see https://kind.sigs.k8s.io/"
        ;;
      kubectl)
        echo "Install kubectl: 'brew install kubectl' or https://kubernetes.io/docs/tasks/tools/"
        ;;
      docker)
        echo "Install Docker Desktop and ensure docker daemon is running"
        ;;
      openssl)
        echo "Install openssl"
        ;;
    esac
    exit 1
  fi
done

CLUSTER_NAME=wisecow

# Step 1: Create temporary cluster to discover ingress-nginx NodePorts
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Creating temporary cluster to discover ingress-nginx NodePorts..."
  cat <<'YAML' > temp-kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
YAML
  kind create cluster --config temp-kind-config.yaml --name "${CLUSTER_NAME}"
  
  # Use fixed NodePorts for consistent mapping
  HTTP_NODEPORT=30080
  HTTPS_NODEPORT=30443
  
  echo "Using fixed NodePorts: HTTP=$HTTP_NODEPORT, HTTPS=$HTTPS_NODEPORT"
  
  # Step 2: Delete temporary cluster and create final cluster with correct port mappings
  echo "Deleting temporary cluster and creating final cluster with correct port mappings..."
  kind delete cluster --name "${CLUSTER_NAME}"
  
  cat <<YAML > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: ${HTTP_NODEPORT}   # ingress-nginx HTTP NodePort (fixed)
        hostPort: 4499                    # Host port for HTTP
        listenAddress: "127.0.0.1"
        protocol: TCP
      - containerPort: ${HTTPS_NODEPORT}  # ingress-nginx HTTPS NodePort (fixed)
        hostPort: 54499                   # Host port for HTTPS
        listenAddress: "127.0.0.1"
        protocol: TCP
YAML

  echo "Creating final cluster with port mappings..."
  kind create cluster --config kind-config.yaml --name "${CLUSTER_NAME}"
else
  echo "kind cluster '${CLUSTER_NAME}' already exists — skipping creation"
fi

echo "Waiting for cluster nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "Installing ingress-nginx for kind..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "Waiting for ingress-nginx service..."
sleep 10  # Give the service time to create

# Use fixed NodePorts for consistent port mapping
FIXED_HTTP_NODEPORT=30080
FIXED_HTTPS_NODEPORT=30443

echo "Setting fixed NodePorts: HTTP=$FIXED_HTTP_NODEPORT, HTTPS=$FIXED_HTTPS_NODEPORT"

# Patch the ingress-nginx controller service to use fixed NodePorts
kubectl patch svc -n ingress-nginx ingress-nginx-controller -p '{"spec":{"ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":"http","appProtocol":"http","nodePort":'$FIXED_HTTP_NODEPORT'},{"name":"https","port":443,"protocol":"TCP","targetPort":"https","appProtocol":"https","nodePort":'$FIXED_HTTPS_NODEPORT'}]}}'

HTTP_NODEPORT=$FIXED_HTTP_NODEPORT
HTTPS_NODEPORT=$FIXED_HTTPS_NODEPORT

echo "Final ingress-nginx NodePorts: HTTP=$HTTP_NODEPORT, HTTPS=$HTTPS_NODEPORT"

echo "Waiting for ingress-nginx controller to be ready (namespace: ingress-nginx)..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=120s || {
  echo "Timed out waiting for ingress controller; check 'kubectl get pods -n ingress-nginx'"
}

echo "Building docker image..."
docker build -t wisecow:local .

echo "Loading image into kind cluster..."
kind load docker-image wisecow:local --name "${CLUSTER_NAME}"

echo "Applying k8s manifests..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

echo "Creating self-signed cert and TLS secret (wisecow-tls)..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout wisecow.key -out wisecow.crt -subj "/CN=wisecow.local/O=wisecow" -addext "subjectAltName=DNS:wisecow.local,DNS:localhost,IP:127.0.0.1"
kubectl create secret tls wisecow-tls --cert=wisecow.crt --key=wisecow.key --dry-run=client -o yaml | kubectl apply -f -

echo "Applying ingress..."
kubectl apply -f k8s/ingress.yaml

echo "
NOTE: Add this line to your /etc/hosts file if not present:
127.0.0.1 wisecow.local

You can edit /etc/hosts with:
code /etc/hosts   # VSCode
# or
nano /etc/hosts   # Terminal editor
"

echo "Done! Access the app via:

HTTP:   http://wisecow.local:4499/
HTTPS:  https://wisecow.local:54499/

Or via port-forward:
kubectl port-forward svc/wisecow 4499:4499
# Then visit http://localhost:4499

NOTE: If the above URLs don't work, the NodePorts may have changed.
Current NodePorts: HTTP=${HTTP_NODEPORT}, HTTPS=${HTTPS_NODEPORT}
You may need to run the teardown and setup script again to get correct port mappings.
"