# Cow wisdom web server

## Prerequisites

```
sudo apt install fortune-mod cowsay -y
```

## How to use?

1. Run `./wisecow.sh`
2. Point the browser to server port (default 4499)

## What to expect?
![wisecow](https://github.com/nyrahul/wisecow/assets/9133227/8d6bfde3-4a5a-480e-8d55-3fef60300d98)

# Problem Statement
Deploy the wisecow application as a k8s app

## Requirement
1. Create Dockerfile for the image and corresponding k8s manifest to deploy in k8s env. The wisecow service should be exposed as k8s service.
2. Github action for creating new image when changes are made to this repo
3. [Challenge goal]: Enable secure TLS communication for the wisecow app.

## Expected Artifacts
1. Github repo containing the app with corresponding dockerfile, k8s manifest, any other artifacts needed.
2. Github repo with corresponding github action.
3. Github repo should be kept private and the access should be enabled for following github IDs: nyrahul

## Added artifacts in this repository

- `Dockerfile` - builds the wisecow container (based on Ubuntu, installs `fortune-mod`, `cowsay`, `netcat`).
- `k8s/deployment.yaml` - Kubernetes Deployment manifest.
- `k8s/service.yaml` - Kubernetes Service manifest exposing port 4499.
- `k8s/ingress.yaml` - Example Ingress manifest referencing TLS secret `wisecow-tls` for host `wisecow.local`.
- `.github/workflows/ci-cd.yml` - GitHub Actions workflow to build and push the image to GHCR and optionally deploy to k8s if `KUBE_CONFIG` secret is present.
- `k8s/README-TLS.md` - Short guide to create a self-signed cert and TLS secret for local testing.

## How to build the container locally

Build with Docker (or any OCI compatible builder):

```bash
docker build -t wisecow:local .
```

Run locally and test (requires `fortune` and `cowsay` are present in the image - they are installed by the Dockerfile):

```bash
docker run --rm -p 4499:4499 wisecow:local
```

Open `http://localhost:4499` in your browser.

## Deploy to Kubernetes (kind - local development)

### Quick Setup (Automated)

We provide automated scripts for easy setup and teardown:

**Prerequisites**: Install `kind`, `kubectl`, `docker`, and `openssl`:
```bash
# macOS
brew install kind kubectl docker
# openssl is usually pre-installed

# Ensure Docker Desktop is running
```

**One-command setup**:
```bash
./scripts/kind-run.sh
```

This script will:
- Create a kind cluster with proper port mappings
- Install ingress-nginx controller with fixed NodePorts
- Build and load the wisecow Docker image
- Deploy all Kubernetes manifests
- Create TLS certificates with proper Subject Alternative Names
- Set up ingress for both HTTP and HTTPS

**Clean up everything**:
```bash
./scripts/teardown.sh
```

### Access the Application

After running the setup script:

1. **Add to /etc/hosts** (if not already present):
```bash
echo "127.0.0.1 wisecow.local" | sudo tee -a /etc/hosts
```

2. **Test the endpoints**:
```bash
# HTTP (redirects to HTTPS)
curl -v http://wisecow.local:4499/

# HTTPS (secure connection)
curl -vk https://wisecow.local:54499/

# Or via port-forward
kubectl port-forward svc/wisecow 4499:4499
curl http://localhost:4499
```

### Manual Setup (Advanced)

If you prefer manual steps, see the automated script `scripts/kind-run.sh` for the exact commands. Key details:
- **Fixed NodePorts**: HTTP=30080, HTTPS=30443
- **Host Port Mapping**: 4499→HTTP, 54499→HTTPS
- **TLS Certificate**: Includes Subject Alternative Names for proper browser support

**Notes**:
- The automated script uses fixed NodePorts (30080/30443) to ensure consistent port mapping across cluster recreations
- TLS certificates include Subject Alternative Names (SANs) for proper browser compatibility
- `kind load docker-image` loads local images into the kind cluster without needing a registry
- For production: push images to a registry, use `cert-manager` with Let's Encrypt, and configure proper ingress classes

## GitHub Actions CI/CD

The workflow `.github/workflows/ci-cd.yml` will build and push an image to GitHub Container Registry at `ghcr.io/<owner>/wisecow:latest` whenever commits are pushed to `main` (or `master`).

To enable automatic deployment from the workflow, add a repository secret named `KUBE_CONFIG` containing your base64-encoded kubeconfig. The deploy job will decode it and run `kubectl apply` on the manifests.

## Notes and next steps

- For production TLS automate cert issuance with `cert-manager` and a real CA (Let's Encrypt).
- Consider switching the app to run as a small HTTP server in a language runtime (Go/Python) if you want better concurrency and TLS termination inside the pod. Currently TLS is handled at the Ingress level.
- The `ingress.yaml` provided assumes an nginx ingress controller; adapt annotations for other controllers.

