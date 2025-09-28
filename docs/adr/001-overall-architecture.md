# ADR-001: Overall Architecture for Wisecow Application Containerization and Deployment

**Date**: 2025-09-29  
**Status**: Accepted  
**Deciders**: Sanjeev Nadela  

## Context

The Wisecow application is a simple web server that displays random fortune messages with ASCII cow art. The requirement is to containerize this application and deploy it to a Kubernetes environment with:

1. Containerized deployment using Docker
2. Kubernetes manifests for orchestration
3. TLS-secured communication (challenge goal)
4. CI/CD pipeline for automated deployment (challenge goal)

## Decision

We have decided on a comprehensive containerization and deployment architecture with the following components:

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     CI/CD Pipeline                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │    Test     │→ │ Build/Push  │→ │   Deploy    │            │
│  │ Application │  │   Image     │  │ to K8s      │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                Container Registry (GHCR)                       │
│            ghcr.io/sanjeevnadela/wisecow                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Kubernetes Cluster                             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Ingress Layer                         │   │
│  │  ┌─────────────┐    ┌─────────────┐                   │   │
│  │  │    HTTP     │    │    HTTPS    │                   │   │
│  │  │ :4499       │    │ :54499      │                   │   │
│  │  └─────────────┘    └─────────────┘                   │   │
│  │           │                │                           │   │
│  │           └────────────────┴──────────┐                │   │
│  └─────────────────────────────────────────│────────────────┘   │
│                                          │                    │
│  ┌─────────────────────────────────────────│────────────────┐   │
│  │              Service Layer              │                │   │
│  │                                         ▼                │   │
│  │          wisecow-service (NodePort 31499)               │   │
│  └─────────────────────────────────────────┬────────────────┘   │
│                                          │                    │
│  ┌─────────────────────────────────────────│────────────────┐   │
│  │             Application Layer           │                │   │
│  │                                         ▼                │   │
│  │     ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │   │
│  │     │ wisecow-pod │  │ wisecow-pod │  │ wisecow-pod │   │   │
│  │     │    :4499    │  │    :4499    │  │    :4499    │   │   │
│  │     └─────────────┘  └─────────────┘  └─────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Component Architecture

#### 1. **Containerization Layer**
- **Base Image**: Ubuntu 22.04 (stable, well-supported)
- **Runtime Dependencies**: fortune-mod, cowsay, netcat-openbsd
- **Application Port**: 4499 (non-privileged port)
- **Security**: Non-root execution context

#### 2. **Kubernetes Orchestration**
- **Deployment**: ReplicaSet management with rolling updates
- **Service**: NodePort type for external access (port 31499)
- **Ingress**: nginx-ingress with TLS termination
- **Namespace**: Default (suitable for single-application deployment)

#### 3. **Network Architecture**
- **External Access Ports**:
  - HTTP: `localhost:4499` → `ingress-nginx:30080`
  - HTTPS: `localhost:54499` → `ingress-nginx:30443`
- **Internal Communication**: 
  - Service discovery via DNS (`wisecow.default.svc.cluster.local`)
  - Pod-to-pod communication on port 4499

#### 4. **TLS Security Architecture**
- **Certificate Type**: Self-signed with Subject Alternative Names (SANs)
- **TLS Termination**: At ingress level (edge termination)
- **Certificate Storage**: Kubernetes TLS secret (`wisecow-tls`)
- **Cipher Support**: TLS 1.3 with modern cipher suites

#### 5. **CI/CD Pipeline Architecture**
- **Trigger Strategy**: 
  - Push to `sj-k8s-implementation` → Build + Deploy
  - Pull Request → Test + Build only
- **Testing**: Container functionality verification
- **Registry**: GitHub Container Registry (GHCR)
- **Deployment**: Direct kubectl apply with image updates

## Rationale

### Technology Choices

#### **1. Container Runtime: Docker**
- **Pros**: Industry standard, excellent tooling, multi-platform support
- **Cons**: Requires Docker daemon
- **Alternative Considered**: Podman (rejected due to broader Docker ecosystem)

#### **2. Kubernetes Distribution: kind**
- **Pros**: Local development, reproducible environments, official k8s
- **Cons**: Not suitable for production
- **Alternative Considered**: minikube (rejected due to kind's better port mapping)

#### **3. Ingress Controller: nginx-ingress**
- **Pros**: Mature, feature-rich, excellent TLS support
- **Cons**: Resource overhead for simple use cases  
- **Alternative Considered**: Traefik (rejected due to nginx's stability)

#### **4. Base Image: Ubuntu 22.04**
- **Pros**: Stable LTS, fortune-mod availability, familiar tooling
- **Cons**: Larger image size than Alpine
- **Alternative Considered**: Alpine Linux (rejected due to glibc compatibility)

#### **5. CI/CD Platform: GitHub Actions**
- **Pros**: Integrated with repository, free for public repos, good ecosystem
- **Cons**: Vendor lock-in
- **Alternative Considered**: GitLab CI (rejected due to existing GitHub workflow)

### Architectural Patterns

#### **1. Port Strategy**
- **Fixed NodePorts**: Ensures consistent access across cluster recreations
- **Non-privileged Ports**: Avoids requiring root permissions
- **Port Mapping**: Clear separation between host, service, and container ports

#### **2. Security Model**
- **Defense in Depth**: TLS at ingress, network policies capability
- **Least Privilege**: Non-root containers, minimal base image
- **Certificate Management**: Automated with proper SANs for browser compatibility

#### **3. Deployment Strategy**
- **Rolling Updates**: Zero-downtime deployments
- **Health Checks**: Readiness and liveness probes
- **Resource Management**: CPU and memory limits defined

## Implementation Details

### **Container Specification**
```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y fortune-mod cowsay netcat-openbsd
WORKDIR /app
COPY wisecow.sh /app/wisecow.sh
RUN chmod +x /app/wisecow.sh
EXPOSE 4499
ENTRYPOINT ["/app/wisecow.sh"]
```

### **Service Discovery**
- **Internal DNS**: `wisecow.default.svc.cluster.local:4499`
- **Service Type**: NodePort for external access
- **Load Balancing**: Round-robin across healthy pods

### **TLS Configuration**
- **Certificate Subjects**: CN=wisecow.local, SANs=[wisecow.local, localhost, 127.0.0.1]
- **Key Size**: RSA 2048-bit (balance of security and performance)
- **Validity**: 365 days (suitable for development)

## Consequences

### **Positive Consequences**
- **Reproducible Deployments**: Containerization ensures consistency across environments
- **Scalable Architecture**: Kubernetes provides horizontal scaling capabilities  
- **Secure Communication**: TLS encryption protects data in transit
- **Automated Operations**: CI/CD reduces manual deployment effort
- **Local Development**: kind enables realistic local testing

### **Negative Consequences**
- **Complexity Overhead**: More complex than simple binary deployment
- **Resource Usage**: Container and Kubernetes overhead
- **Learning Curve**: Requires Kubernetes knowledge for maintenance
- **Network Complexity**: Multiple port mappings can be confusing

### **Neutral Consequences**
- **Vendor Dependencies**: Relies on GitHub, Docker, and Kubernetes ecosystems
- **Maintenance Overhead**: Requires regular updates for security patches
- **Documentation Requirements**: More documentation needed for operations

## Compliance and Standards

### **Security Compliance**
- Container runs as non-root user
- TLS 1.3 support for modern encryption
- Regular vulnerability scanning via CI/CD
- Secrets management through Kubernetes secrets

### **Operational Standards**  
- Health checks for application monitoring
- Resource limits prevent resource exhaustion
- Logging to stdout for container log collection
- Graceful shutdown handling

### **Development Standards**
- Infrastructure as Code (Kubernetes YAML)
- Version controlled configuration
- Automated testing in CI/CD pipeline
- Documentation-driven development

## Future Considerations

### **Potential Improvements**
1. **Production Readiness**:
   - Real TLS certificates (Let's Encrypt, cert-manager)
   - Resource quotas and network policies
   - Multi-environment support (staging, production)

2. **Observability**:
   - Prometheus metrics collection
   - Distributed tracing with Jaeger
   - Centralized logging with ELK stack

3. **Performance Optimization**:
   - Multi-stage Docker builds for smaller images
   - CDN integration for static assets
   - Horizontal Pod Autoscaler (HPA) configuration

4. **Security Enhancements**:
   - Pod Security Standards enforcement
   - Network policies for micro-segmentation
   - Image vulnerability scanning integration

## Related Decisions

- **ADR-002**: TLS Certificate Management Strategy (Future)
- **ADR-003**: Health Monitoring and Observability Implementation (Future)  
- **ADR-004**: Production Environment Architecture (Future)

---