# Akkoma Helm Chart

A Helm chart for deploying [Akkoma](https://akkoma.dev/) on Kubernetes. Akkoma is a federated social networking server for the Fediverse (ActivityPub protocol), forked from Pleroma with enhanced features and active development.

## Features

- Akkoma application server (Elixir/OTP release)
- Multi-architecture support (amd64 + arm64)
- Bundled PostgreSQL with automatic initialization and migrations
- CloudNativePG operator support as alternative to bundled PostgreSQL
- Automated frontend installation (Pleroma-FE and Admin-FE)
- Frontend version pinning and custom build URL support
- Persistent storage for uploads and frontend assets
- External S3 storage support (AWS, Backblaze B2, Wasabi, Cloudflare R2)
- Optional Garage S3-compatible object storage subchart
- Media pruning CronJob for automated remote media cleanup
- Ingress with TLS and cert-manager support
- Zero-trust NetworkPolicies
- Prometheus metrics, ServiceMonitor, and Grafana dashboard
- Auto-generated secrets with upgrade persistence
- External secrets integration (Sealed Secrets, ESO, Vault)
- Security-hardened containers (non-root, seccomp, dropped capabilities, read-only root filesystem)

## Prerequisites

- Kubernetes 1.28+
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

### Frontends

| Parameter | Description | Default |
|-----------|-------------|---------|
| `frontends.pleromaFe.ref` | Pleroma-FE version/branch to install | `stable` |
| `frontends.pleromaFe.url` | Custom build URL for Pleroma-FE (overrides CDN) | `""` |
| `frontends.adminFe.ref` | Admin-FE version/branch to install | `stable` |
| `frontends.adminFe.url` | Custom build URL for Admin-FE (overrides CDN) | `""` |

### Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storage.type` | Upload backend: `local` or `s3` | `local` |
| `storage.uploads.size` | Media uploads volume size | `50Gi` |
| `storage.uploads.storageClass` | Storage class (empty = cluster default) | `""` |
| `storage.frontends.size` | Frontend assets volume size | `5Gi` |
| `storage.s3.endpoint` | S3 endpoint | `""` |
| `storage.s3.region` | S3 region | `us-east-1` |
| `storage.s3.bucket` | S3 bucket name | `akkoma-uploads` |
| `storage.s3.baseUrl` | Public media URL | `""` |
| `storage.s3.existingSecret` | Existing Secret for S3 credentials | `""` |
| `storage.s3.accessKeyId` | S3 access key (if no existingSecret) | `""` |
| `storage.s3.secretAccessKey` | S3 secret key (if no existingSecret) | `""` |

### Garage (Bundled S3 Storage)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `garage.enabled` | Deploy Garage alongside Akkoma | `false` |
| `garage.persistence.meta.size` | Garage metadata volume | `1Gi` |
| `garage.persistence.data.size` | Garage data volume | `50Gi` |

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
| `postgresql.cnpg.enabled` | Use CloudNativePG operator instead of bundled StatefulSet | `false` |
| `postgresql.cnpg.instances` | Number of CNPG instances | `1` |
| `postgresql.cnpg.storage.size` | CNPG storage size | `10Gi` |
| `postgresql.cnpg.storage.storageClass` | CNPG storage class | `""` |
| `postgresql.cnpg.imageName` | CNPG PostgreSQL image | `ghcr.io/cloudnative-pg/postgresql:16` |
| `postgresql.cnpg.parameters` | Additional PostgreSQL parameters | `{}` |
| `postgresql.cnpg.backup.enabled` | Enable CNPG backups | `false` |

### Metrics

| Parameter | Description | Default |
|-----------|-------------|---------|
| `metrics.enabled` | Enable Prometheus metrics | `false` |
| `metrics.serviceMonitor.enabled` | Create ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `30s` |
| `metrics.serviceMonitor.labels` | Additional ServiceMonitor labels | `{}` |
| `metrics.grafana.enabled` | Create Grafana dashboard ConfigMap | `false` |
| `metrics.grafana.labels` | Labels for Grafana sidecar discovery | `{grafana_dashboard: "1"}` |
| `metrics.grafana.annotations` | Annotations for dashboard ConfigMap | `{}` |

### Media Pruning

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mediaPruning.enabled` | Enable media pruning CronJob | `false` |
| `mediaPruning.schedule` | Cron schedule expression | `0 3 * * 0` |
| `mediaPruning.options.keepFollowed` | Keep media from followed accounts: `none`, `posts`, `full` | `posts` |
| `mediaPruning.options.keepThreads` | Keep media from threads | `true` |
| `mediaPruning.options.keepNonPublic` | Keep media from non-public posts | `true` |
| `mediaPruning.options.limit` | Maximum objects to prune (0 = unlimited) | `0` |
| `mediaPruning.options.pruneOrphanedActivities` | Also prune orphaned activities | `true` |
| `mediaPruning.options.vacuum` | Run VACUUM after pruning | `false` |
| `mediaPruning.successfulJobsHistoryLimit` | Successful job history to retain | `3` |
| `mediaPruning.failedJobsHistoryLimit` | Failed job history to retain | `1` |

### Security

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Enable NetworkPolicies | `false` |
| `securityContext.readOnlyRootFilesystem` | Read-only root filesystem | `true` |
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

### With External S3 Storage

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set storage.type=s3 \
  --set storage.s3.endpoint=s3.amazonaws.com \
  --set storage.s3.region=us-east-1 \
  --set storage.s3.bucket=my-akkoma-uploads \
  --set storage.s3.baseUrl=https://media.example.com \
  --set storage.s3.accessKeyId=AKIAIOSFODNN7EXAMPLE \
  --set storage.s3.secretAccessKey=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### With Bundled Garage Storage

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set garage.enabled=true
```

The Garage setup Job runs automatically after install, creating the storage layout, access key, bucket, and storing credentials in a Kubernetes Secret.

### With Prometheus Metrics

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.serviceMonitor.labels.release=prometheus
```

### With Frontend Version Override

Pin frontend versions or use custom build URLs:

```yaml
# values.yaml
frontends:
  pleromaFe:
    ref: "develop"  # Use development branch
  adminFe:
    ref: "v2.6.0"   # Pin to specific version

# Or use a custom build URL
frontends:
  pleromaFe:
    url: "https://my-cdn.example.com/custom-akkoma-fe.zip"
```

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set frontends.pleromaFe.ref=develop
```

### With Grafana Dashboard

Enable the Grafana dashboard ConfigMap for sidecar-based auto-discovery:

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set metrics.enabled=true \
  --set metrics.grafana.enabled=true
```

The dashboard ConfigMap is labeled with `grafana_dashboard: "1"` by default, which the standard Grafana sidecar uses for auto-discovery. Customize labels if your Grafana uses a different selector:

```yaml
# values.yaml
metrics:
  enabled: true
  grafana:
    enabled: true
    labels:
      grafana_dashboard: "1"
    annotations:
      description: "Akkoma instance dashboard"
```

### With Media Pruning

Schedule automatic cleanup of remote media to reclaim database and storage space:

```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set mediaPruning.enabled=true \
  --set mediaPruning.schedule="0 3 * * 0"
```

Full configuration example:

```yaml
# values.yaml
mediaPruning:
  enabled: true
  schedule: "0 3 * * 0"  # 3 AM every Sunday
  options:
    keepFollowed: "posts"  # Keep posts from followed accounts
    keepThreads: true       # Keep media in threads you participated in
    keepNonPublic: true     # Keep non-public post media
    limit: 0                # 0 = no limit
    pruneOrphanedActivities: true
    vacuum: false           # Run VACUUM after (locks DB, use with caution)
```

### With CloudNativePG

Use the CloudNativePG operator for production-grade PostgreSQL instead of the bundled StatefulSet. The CNPG operator must be installed in the cluster first.

```bash
# Install the CNPG operator (if not already installed)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.22.0.yaml

# Install Akkoma with CNPG
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set postgresql.cnpg.enabled=true \
  --set postgresql.cnpg.instances=2 \
  --set postgresql.cnpg.storage.size=20Gi
```

Full configuration example:

```yaml
# values.yaml
postgresql:
  cnpg:
    enabled: true
    instances: 2
    storage:
      size: 20Gi
      storageClass: "fast-ssd"
    imageName: "ghcr.io/cloudnative-pg/postgresql:16"
    parameters:
      shared_buffers: "256MB"
      max_connections: "100"
    backup:
      enabled: true
      barmanObjectStore:
        destinationPath: "s3://my-backup-bucket/akkoma"
        s3Credentials:
          accessKeyId:
            name: backup-creds
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: backup-creds
            key: SECRET_ACCESS_KEY
```

When CNPG is enabled, the bundled PostgreSQL StatefulSet is automatically disabled. The CNPG operator manages the database lifecycle, including initialization with required extensions (citext, pg_trgm, uuid-ossp).

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

## Backup and Restore

### PostgreSQL Backup

```bash
# Create a backup using pg_dump
kubectl exec akkoma-postgresql-0 -- \
  pg_dump -U akkoma -Fc akkoma > akkoma-db-$(date +%Y%m%d).dump

# Or use a CronJob with Velero/Restic for automated backups
```

### Uploads Backup

```bash
# If using local storage (PVC)
# Option 1: Use Velero to snapshot the PVC
velero backup create akkoma-uploads --include-resources pvc \
  --selector app.kubernetes.io/name=akkoma

# Option 2: Copy files from the PVC
kubectl cp akkoma-<pod-name>:/opt/akkoma/uploads ./uploads-backup/
```

### Full Restore

```bash
# 1. Install the chart (creates empty resources)
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com

# 2. Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod akkoma-postgresql-0

# 3. Restore the database
kubectl exec -i akkoma-postgresql-0 -- \
  pg_restore -U akkoma -d akkoma --clean --if-exists < akkoma-db.dump

# 4. Restore uploads (if using local storage)
kubectl cp ./uploads-backup/ akkoma-<pod-name>:/opt/akkoma/uploads/

# 5. Restart Akkoma to pick up restored data
kubectl rollout restart deployment/akkoma
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
- Metrics: `https://social.example.com/api/v1/akkoma/metrics` (when enabled)

## Upgrading

```bash
helm upgrade akkoma ./charts/akkoma
```

Secrets are automatically preserved across upgrades using Helm's `lookup` function. Database migrations run automatically via init container on every pod start.

**Warning:** If you delete the `akkoma-secrets` Secret between upgrades, new secrets will be generated and all user sessions will be invalidated.

### Upgrading to v0.3.1

v0.3.1 fixes a critical bug where Helm rendered `upload_limit` (16000000) as scientific notation (`1.6e+07`), which Elixir parsed as a float. This crashed the Plug multipart parser on login (`POST /oauth/token`) and file uploads. All users on v0.3.0 or earlier should upgrade.

### Upgrading from v0.2.x to v0.3.0

v0.3.0 adds four new opt-in features. All are disabled by default and require no action for existing deployments:

- **Frontend version override** (`frontends.pleromaFe.ref`, `frontends.adminFe.ref`) -- defaults remain `stable`
- **Grafana dashboard** (`metrics.grafana.enabled`) -- opt-in ConfigMap
- **Media pruning CronJob** (`mediaPruning.enabled`) -- opt-in scheduled cleanup
- **CloudNativePG** (`postgresql.cnpg.enabled`) -- alternative PostgreSQL backend; enabling this disables the bundled StatefulSet

If migrating to CNPG, you must migrate your existing PostgreSQL data before enabling `postgresql.cnpg.enabled`. Refer to the CloudNativePG documentation for import procedures.

### Upgrading from v0.1.0 to v0.2.0

v0.2.0 enables `readOnlyRootFilesystem: true` by default. This is a non-breaking change -- tmpfs volumes are automatically mounted for BEAM VM scratch space. No action required.

New features (metrics, S3, Garage) are all disabled by default and opt-in.

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
                                 |-- init: wait-for-db (postgres:15-alpine)
                                 |-- init: db-migrate (akkoma image)
                                 |-- init: install-frontends (alpine:3.23)
                                 +-- main: akkoma (port 4000)
                                       |-- /etc/akkoma (ConfigMap, read-only)
                                       |-- /opt/akkoma/uploads (PVC)
                                       |-- /opt/akkoma/instance/static/frontends (PVC)
                                       +-- /tmp (tmpfs, 64Mi)

PostgreSQL StatefulSet (default)
  |-- /var/lib/postgresql/data (PVC)
  +-- /docker-entrypoint-initdb.d (ConfigMap: extensions)

[OR] CloudNativePG Cluster (when postgresql.cnpg.enabled)
  +-- Managed by CNPG operator (automatic failover, backups)

[Optional] Garage StatefulSet
  |-- /var/lib/garage/meta (PVC)
  |-- /var/lib/garage/data (PVC)
  +-- /etc/garage (ConfigMap + Secret)

[Optional] Media Pruning CronJob (when mediaPruning.enabled)
  +-- Runs pleroma_ctl database prune_objects on schedule
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
| Secret | `akkoma-s3` | S3 credentials (when S3/Garage enabled) |
| PVC | `akkoma-uploads` | Media storage |
| PVC | `akkoma-frontends` | Frontend assets |
| Ingress | `akkoma` | External access (optional) |
| NetworkPolicy | `akkoma` | App network rules (optional) |
| NetworkPolicy | `akkoma-postgresql` | DB isolation (optional) |
| ServiceMonitor | `akkoma` | Prometheus scraping (optional) |
| StatefulSet | `akkoma-garage` | Garage S3 storage (optional) |
| Job | `akkoma-garage-setup` | Garage initialization (optional) |
| Cluster (CNPG) | `akkoma-cnpg` | Operator-managed PostgreSQL (optional) |
| CronJob | `akkoma-media-prune` | Media pruning (optional) |
| ConfigMap | `akkoma-grafana-dashboard` | Grafana dashboard (optional) |

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

### Garage setup Job stuck

Check the Job logs:

```bash
kubectl logs job/akkoma-garage-setup
```

Common issues:
- Garage pod not ready (check `kubectl get pods -l app.kubernetes.io/name=garage`)
- Admin API unreachable (check Garage service and port 3903)

## Development

```bash
# Lint
helm lint charts/akkoma --strict

# Render templates
helm template akkoma charts/akkoma --debug

# Test all CI value combinations
for f in charts/akkoma/ci/*.yaml; do
  helm template akkoma charts/akkoma -f "$f" > /dev/null && echo "OK: $f"
done

# Render with specific values
helm template akkoma charts/akkoma \
  --set ingress.enabled=true \
  --set networkPolicy.enabled=true \
  --set metrics.enabled=true

# Dry-run install
helm install akkoma charts/akkoma --dry-run --debug
```

## Resources

- [Akkoma Documentation](https://docs.akkoma.dev/)
- [Akkoma Repository](https://akkoma.dev/AkkomaGang/akkoma)
- [Configuration Reference](https://docs.akkoma.dev/stable/configuration/cheatsheet/)
- [Garage Documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [Federation Guide](https://blog.soykaf.com/post/how-federation-works/)
- [Design Document](DESIGN.md)
- [Changelog](CHANGELOG.md)

## License

This chart is licensed under the MIT License. Akkoma itself is licensed under the GNU AGPLv3.
