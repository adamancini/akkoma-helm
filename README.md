# Akkoma Helm Chart

A Helm chart for deploying [Akkoma](https://akkoma.dev/), a federated social networking server for the Fediverse (ActivityPub protocol).

## Overview

Akkoma is a fork of Pleroma with enhanced features and active development. This Helm chart provides a production-ready deployment of Akkoma on Kubernetes, including:

- Akkoma application server (Elixir/Phoenix)
- PostgreSQL database
- Reverse proxy configuration (Caddy or nginx)
- Persistent storage for uploads and media
- Automated database initialization and migrations
- Frontend installation (Pleroma-FE and Admin-FE)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume provisioner support (for uploads and database storage)
- Ingress controller (nginx, Caddy, or Traefik)

## Installation

### Quick Start

```bash
# Add the repository (once published)
helm repo add akkoma https://adamancini.github.io/akkoma-helm
helm repo update

# Install Akkoma
helm install akkoma akkoma/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=social.example.com
```

### Development Installation

```bash
# Clone the repository
git clone https://github.com/adamancini/akkoma-helm.git
cd akkoma-helm

# Install from local chart
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=social.example.com \
  --set akkoma.adminEmail=admin@example.com
```

## Configuration

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `akkoma.domain` | Domain name for the instance | `example.com` |
| `akkoma.instanceName` | Name of your Akkoma instance | `My Akkoma Instance` |
| `akkoma.adminEmail` | Admin email address | `admin@example.com` |
| `postgresql.enabled` | Enable bundled PostgreSQL | `true` |
| `postgresql.auth.password` | PostgreSQL password | `akkoma` |
| `ingress.enabled` | Enable ingress resource | `true` |
| `ingress.className` | Ingress class to use | `nginx` |
| `persistence.uploads.enabled` | Enable persistent storage for uploads | `true` |
| `persistence.uploads.size` | Size of uploads volume | `10Gi` |

### Full Values

See [values.yaml](charts/akkoma/values.yaml) for all configurable options.

## Post-Installation

### Create Admin User

After installation, create your first admin user:

```bash
kubectl exec -it deployment/akkoma -- \
  mix pleroma.user new myusername admin@example.com --admin
```

### Access the Web Interface

Visit your configured domain (e.g., https://social.example.com) to access the Pleroma-FE web interface.

### Admin Panel

Access the admin panel at https://social.example.com/pleroma/admin/

## Upgrading

```bash
# Update repository
helm repo update

# Upgrade release
helm upgrade akkoma akkoma/akkoma
```

## Uninstalling

```bash
helm uninstall akkoma
```

**Note:** This will not delete PersistentVolumeClaims. To remove data volumes:

```bash
kubectl delete pvc -l app.kubernetes.io/name=akkoma
```

## Architecture

- **Application Server**: Elixir/Phoenix application running on BEAM VM
- **Database**: PostgreSQL for data persistence
- **Storage**: PersistentVolumes for uploads and media files
- **Proxy**: Reverse proxy (Caddy or nginx) for HTTPS termination
- **Frontends**: Pleroma-FE (user interface) and Admin-FE (admin panel)

## Development

### Local Testing

```bash
# Create test cluster
kind create cluster --name akkoma-test

# Install chart
helm install akkoma ./charts/akkoma -f values.test.yaml

# Check status
kubectl get pods -w

# Port forward for testing
kubectl port-forward svc/akkoma 4000:4000
```

### Linting

```bash
helm lint charts/akkoma
```

### Template Rendering

```bash
helm template akkoma charts/akkoma --debug
```

## Resources

- [Akkoma Documentation](https://docs.akkoma.dev/)
- [Akkoma Repository](https://akkoma.dev/AkkomaGang/akkoma)
- [Federation Guide](https://blog.soykaf.com/post/how-federation-works/)
- [Configuration Reference](https://docs.akkoma.dev/stable/configuration/cheatsheet/)

## Contributing

Contributions welcome! Please open an issue or pull request on GitHub.

## License

This chart is licensed under the MIT License. Akkoma itself is licensed under the GNU AGPLv3.

## Support

- GitHub Issues: https://github.com/adamancini/akkoma-helm/issues
- Akkoma Community: https://meta.akkoma.dev/
- IRC: #akkoma on irc.akkoma.dev (port 6697, SSL)
