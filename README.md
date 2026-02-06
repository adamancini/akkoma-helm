# Akkoma Helm Chart

A Helm chart for deploying [Akkoma](https://akkoma.dev/) on Kubernetes. Akkoma is a federated social networking server for the Fediverse (ActivityPub protocol), forked from Pleroma with enhanced features and active development.

## Features

- Akkoma application server (Elixir/OTP release)
- Bundled PostgreSQL with automatic initialization and migrations
- Automated frontend installation (Pleroma-FE and Admin-FE)
- Persistent storage for uploads and frontend assets
- Ingress with TLS and cert-manager support
- Zero-trust NetworkPolicies
- Auto-generated secrets with upgrade persistence
- External secrets integration (Sealed Secrets, ESO, Vault)
- Security-hardened containers (non-root, seccomp, dropped capabilities)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume provisioner (for uploads, frontends, and database)
- Ingress controller (nginx, Traefik, or similar) for external access

## Quick Start

```bash
# Clone the repository
git clone https://github.com/adamancini/akkoma-helm.git
cd akkoma-helm

# Install with minimal configuration
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com

# Watch pods start (3 init containers + main)
kubectl get pods -w

# Create your first admin user
kubectl exec -it deployment/akkoma -- \
  /opt/akkoma/bin/pleroma_ctl user new admin admin@example.com --admin

# Port forward to access locally
kubectl port-forward svc/akkoma 4000:4000
# Visit http://localhost:4000
```

## Configuration

### Required Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `akkoma.domain` | Instance domain name (must match Ingress) | `akkoma.example.com` |
| `akkoma.adminEmail` | Admin contact email | `admin@example.com` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Create Ingress resource | `false` |
| `ingress.className` | Ingress class | `nginx` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.tls.enabled` | Enable TLS | `false` |
| `ingress.tls.secretName` | TLS certificate Secret name | `akkoma-tls` |

### Instance Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `akkoma.instanceName` | Display name (defaults to domain) | `""` |
| `instance.characterLimit` | Post character limit | `5000` |
| `instance.registrationsOpen` | Allow new registrations | `false` |
| `instance.uploadLimit` | Max upload size (bytes) | `16000000` |
| `instance.description` | Instance description | `""` |

### Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storage.uploads.size` | Media uploads volume size | `50Gi` |
| `storage.uploads.storageClass` | Storage class (empty = cluster default) | `""` |
| `storage.frontends.size` | Frontend assets volume size | `5Gi` |
| `storage.frontends.storageClass` | Storage class | `""` |

### PostgreSQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.storageSize` | Database volume size | `10Gi` |
| `postgresql.storageClass` | Storage class | `""` |
| `postgresql.database` | Database name | `akkoma` |
| `postgresql.username` | Database user | `akkoma` |
| `postgresql.external.enabled` | Use external PostgreSQL | `false` |
| `postgresql.external.host` | External PostgreSQL host | `""` |
| `postgresql.external.passwordSecret` | Secret name for password | `""` |
| `postgresql.external.passwordKey` | Key in Secret | `password` |

### Security

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Enable NetworkPolicies | `false` |
| `networkPolicy.ingressControllerLabels` | Namespace labels for ingress controller | `{kubernetes.io/metadata.name: ingress-nginx}` |
| `externalSecret.enabled` | Use pre-existing Secret | `false` |
| `externalSecret.name` | Name of existing Secret | `""` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.requests.memory` | Memory request | `1Gi` |
| `resources.limits.memory` | Memory limit (no CPU limit for BEAM) | `2Gi` |

See [values.yaml](charts/akkoma/values.yaml) for the complete list.

## Production Deployment

### With Ingress and TLS

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.tls.enabled=true \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod
```

### With NetworkPolicies

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set ingress.enabled=true \
  --set networkPolicy.enabled=true \
  --set networkPolicy.ingressControllerLabels."kubernetes\.io/metadata\.name"=ingress-nginx
```

### With External Secrets

For production, manage secrets outside of Helm using Sealed Secrets, External Secrets Operator, or Vault:

```bash
# Create your secret first
kubectl create secret generic my-akkoma-secrets \
  --from-literal=secret-key-base=$(openssl rand -hex 64) \
  --from-literal=signing-salt=$(openssl rand -hex 8) \
  --from-literal=release-cookie=$(openssl rand -hex 64)

# Install with external secret
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set externalSecret.enabled=true \
  --set externalSecret.name=my-akkoma-secrets
```

### With External PostgreSQL

```bash
# Create password secret
kubectl create secret generic pg-password --from-literal=password=YOUR_PASSWORD

helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set postgresql.external.enabled=true \
  --set postgresql.external.host=postgres.example.com \
  --set postgresql.external.passwordSecret=pg-password
```

## Ingress Controller Examples

### nginx-ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "16m"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    enabled: true
```

### Traefik

```yaml
ingress:
  enabled: true
  className: traefik
  annotations:
    traefik.ingress.kubernetes.io/router.tls: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    enabled: true
```

## Post-Installation

### Create Admin User

```bash
kubectl exec -it deployment/akkoma -- \
  /opt/akkoma/bin/pleroma_ctl user new admin admin@example.com --admin
```

### Access the Web Interface

- Web UI: `https://social.example.com` (Pleroma-FE)
- Admin Panel: `https://social.example.com/pleroma/admin/`
- API: `https://social.example.com/api/v1/instance`

## Upgrading

```bash
helm upgrade akkoma ./charts/akkoma
```

Secrets are automatically preserved across upgrades using Helm's `lookup` function. Database migrations run automatically via init container on every pod start.

**Warning:** If you delete the `akkoma-secrets` Secret between upgrades, new secrets will be generated and all user sessions will be invalidated.

## Uninstalling

```bash
helm uninstall akkoma
```

PersistentVolumeClaims are not deleted automatically. To remove all data:

```bash
kubectl delete pvc -l app.kubernetes.io/name=akkoma
kubectl delete pvc data-akkoma-postgresql-0
```

## Architecture

```
Ingress (HTTPS) -> Service -> Deployment
                                 ├── init: wait-for-db (postgres:15-alpine)
                                 ├── init: db-migrate (akkoma image)
                                 ├── init: install-frontends (alpine:3.19)
                                 └── main: akkoma (port 4000)
                                       ├── /etc/akkoma (ConfigMap)
                                       ├── /opt/akkoma/uploads (PVC)
                                       └── /opt/akkoma/instance/static/frontends (PVC)

PostgreSQL StatefulSet
  ├── /var/lib/postgresql/data (PVC)
  └── /docker-entrypoint-initdb.d (ConfigMap: extensions)
```

### Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| Deployment | `akkoma` | Application server |
| StatefulSet | `akkoma-postgresql` | Database |
| Service | `akkoma` | Application ClusterIP (4000) |
| Service | `akkoma-postgresql` | Database ClusterIP (5432) |
| ConfigMap | `akkoma-config` | Elixir configuration |
| ConfigMap | `akkoma-postgresql-init` | Database extensions |
| Secret | `akkoma-secrets` | App secrets (auto-generated) |
| Secret | `akkoma-postgresql` | DB password (auto-generated) |
| PVC | `akkoma-uploads` | Media storage |
| PVC | `akkoma-frontends` | Frontend assets |
| Ingress | `akkoma` | External access (optional) |
| NetworkPolicy | `akkoma` | App network rules (optional) |
| NetworkPolicy | `akkoma-postgresql` | DB isolation (optional) |

## Troubleshooting

### Pod stuck in Init:0/3

PostgreSQL is not ready. Check the PostgreSQL pod:

```bash
kubectl logs akkoma-postgresql-0
kubectl describe pod akkoma-postgresql-0
```

### Pod in CrashLoopBackOff after uninstall/reinstall

The PostgreSQL PVC retained the old password but a new password was generated. Delete the PostgreSQL PVC and reinstall:

```bash
kubectl delete pvc data-akkoma-postgresql-0
helm install akkoma ./charts/akkoma ...
```

### Frontends not loading (blank page)

Check the install-frontends init container logs:

```bash
kubectl logs deployment/akkoma -c install-frontends
```

To force frontend reinstallation, delete the frontends PVC and restart:

```bash
kubectl delete pvc akkoma-frontends
kubectl rollout restart deployment/akkoma
```

### Database connection errors

Verify the PostgreSQL service is reachable:

```bash
kubectl exec deployment/akkoma -- pg_isready -h akkoma-postgresql -U akkoma
```

### Secrets regenerated unexpectedly

If user sessions are invalidated after an upgrade, the secrets Secret may have been deleted. For production, use `externalSecret` to manage secrets outside of Helm.

## Development

```bash
# Lint
helm lint charts/akkoma

# Render templates
helm template akkoma charts/akkoma --debug

# Render with specific values
helm template akkoma charts/akkoma \
  --set ingress.enabled=true \
  --set networkPolicy.enabled=true

# Dry-run install
helm install akkoma charts/akkoma --dry-run --debug
```

## Resources

- [Akkoma Documentation](https://docs.akkoma.dev/)
- [Akkoma Repository](https://akkoma.dev/AkkomaGang/akkoma)
- [Configuration Reference](https://docs.akkoma.dev/stable/configuration/cheatsheet/)
- [Federation Guide](https://blog.soykaf.com/post/how-federation-works/)
- [Design Document](DESIGN.md)

## License

This chart is licensed under the MIT License. Akkoma itself is licensed under the GNU AGPLv3.
