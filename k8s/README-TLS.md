# TLS for Wisecow Ingress

This file explains how to create a self-signed certificate for the host `wisecow.local` and create a Kubernetes TLS secret named `wisecow-tls` used by `k8s/ingress.yaml`.

1. Create cert and key with Subject Alternative Names (for proper browser support):

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout wisecow.key -out wisecow.crt \
  -subj "/CN=wisecow.local/O=wisecow" \
  -addext "subjectAltName=DNS:wisecow.local,DNS:localhost,IP:127.0.0.1"
```

2. Create k8s TLS secret:

```bash
kubectl create secret tls wisecow-tls --cert=wisecow.crt --key=wisecow.key -n default
```

3. Ensure your local /etc/hosts points `wisecow.local` to `127.0.0.1`:

```bash
echo "127.0.0.1 wisecow.local" | sudo tee -a /etc/hosts
```

4. Access the application:

```bash
# HTTP (redirects to HTTPS) - port 4499
curl -v http://wisecow.local:4499/

# HTTPS (secure connection) - port 54499  
curl -vk https://wisecow.local:54499/
```

**Port Mapping Details**:
- Host port 4499 → ingress-nginx HTTP NodePort (30080)
- Host port 54499 → ingress-nginx HTTPS NodePort (30443)
- The automated `scripts/kind-run.sh` sets up these mappings automatically

Notes:
- For production, use a trusted CA (Let's Encrypt, cert-manager, etc.).
- If using `cert-manager`, you can create an Issuer and Certificate and reference the resulting secret name here.
