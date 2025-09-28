#!/usr/bin/env bash
set -euo pipefail

# Helper script to tear down the kind cluster and clean up resources
# Usage: ./scripts/teardown.sh

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

# Check Docker status
check_docker

CLUSTER_NAME=wisecow

echo "Checking for existing kind cluster '${CLUSTER_NAME}'..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "No kind cluster '${CLUSTER_NAME}' found."
fi

echo "Cleaning up generated files..."
rm -f kind-config.yaml wisecow.key wisecow.crt

echo "Done! All resources have been cleaned up."