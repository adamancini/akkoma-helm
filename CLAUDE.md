# CLAUDE.md - Akkoma Helm Chart Project

This file provides guidance to Claude Code when working with the Akkoma Helm chart in this repository.

## Project Overview

This repository contains a Helm chart for deploying Akkoma, a federated social networking server (ActivityPub/Fediverse). Akkoma is a fork of Pleroma with enhanced features and active development.

## Akkoma Architecture

### Core Components

**Application Server**
- Elixir/Phoenix application
- Built using Mix build system
- Runs on BEAM VM (Erlang runtime)
- Configuration via `config/prod.secret.exs`
- Default port: 4000

**Database**
- PostgreSQL (required)
- Database name: `akkoma`
- Default user: `akkoma`
- Schema initialized via `config/setup_db.psql`
- Migrations: `mix ecto.migrate`

**Reverse Proxy**
- Required for production deployments
- Options: Caddy (recommended), nginx
- Handles HTTPS/TLS termination
- Serves static assets
- Proxies API requests to application server

**Frontends**
- Pleroma-FE: Primary web interface
- Admin-FE: Administrative interface
- Installed separately via `mix pleroma.frontend install`
- Not bundled with application

### Configuration Requirements

**Instance Generation**
- Run `mix pleroma.instance gen` to create initial config
- Generates `config/generated_config.exs`
- Copy to `config/prod.secret.exs` for production
- Key settings:
  - Instance name and description
  - Admin email
  - Database connection (host: `db`, password: `akkoma`)
  - Listen address: `0.0.0.0` for container networking
  - Domain/hostname for federation

**Database Setup**
1. Create database and user via `config/setup_db.psql`
2. Run initial migrations: `mix ecto.migrate`
3. Database must be accessible before application starts

**User Management**
- Create admin user: `mix pleroma.user new <username> <email> --admin`
- User creation requires running application

### Docker-Specific Considerations

**Container Structure**
- Thin wrapper around dependencies
- Application code mounted as volume (not in image)
- Allows easy updates and debugging
- Requires build step: `./docker-resources/build.sh`

**Volume Mounts**
- PostgreSQL data: `./pgdata`
- Akkoma uploads: `./uploads` (persistent storage for media)
- Configuration: `./config` directory

**Environment Variables**
- `DOCKER_USER`: Set to `$(id -u):$(id -g)` for permission management
- Defined in `.env` file from `docker-resources/env.example`

**Management Script**
- `./docker-resources/manage.sh`: Wrapper for Mix commands
- Ensures commands run in correct container context
- Used for migrations, user creation, frontend installation

## Helm Chart Development Guidelines

### Required Kubernetes Resources

**Deployment/StatefulSet**
- Application server (akkoma)
- PostgreSQL database (or use external/operator)

**Services**
- ClusterIP for database
- ClusterIP for application (internal)
- LoadBalancer/Ingress for external access

**PersistentVolumeClaims**
- PostgreSQL data (if not using operator)
- Akkoma uploads directory
- Configuration directory (optional, could use ConfigMap)

**ConfigMaps**
- Initial database setup SQL (`setup_db.psql`)
- Application configuration template
- Environment variables

**Secrets**
- Database passwords
- Secret key base (for Phoenix sessions)
- Instance secrets (generated during setup)

### Init Containers Pattern

**Database Initialization**
1. Wait for PostgreSQL readiness
2. Run `setup_db.psql` if database doesn't exist
3. Run `mix ecto.migrate` for schema setup

**Configuration Generation**
1. Run `mix pleroma.instance gen` on first install
2. Store generated config in Secret or ConfigMap
3. Mount into application pod

**Frontend Installation**
1. Install pleroma-fe and admin-fe
2. Could be init container or separate Job
3. Frontends stored in application volume

### Values Structure Recommendations

```yaml
image:
  repository: akkoma
  tag: latest
  pullPolicy: IfNotPresent

akkoma:
  domain: example.com
  instanceName: "My Akkoma Instance"
  adminEmail: admin@example.com

postgresql:
  enabled: true  # Use bundled PostgreSQL subchart
  auth:
    username: akkoma
    password: akkoma
    database: akkoma
  # Or external:
  external:
    enabled: false
    host: postgres.example.com
    port: 5432

ingress:
  enabled: true
  className: nginx
  tls:
    enabled: true
    secretName: akkoma-tls

persistence:
  uploads:
    enabled: true
    size: 10Gi
    storageClass: ""

proxy:
  type: caddy  # or nginx
  enabled: true
```

### Testing Approach

**Template Validation**
- `helm lint charts/akkoma`
- `helm template akkoma charts/akkoma --debug`
- Validate against Kubernetes API schemas

**Installation Testing**
- Local Kind/k3d cluster
- Verify database initialization
- Check application startup logs
- Test frontend accessibility
- Verify federation connectivity

**Upgrade Testing**
- Test migration path from previous versions
- Verify database migrations run correctly
- Check configuration persistence

## Development Workflow

### Building the Container

If building custom image:
```bash
./docker-resources/build.sh
docker tag akkoma <registry>/akkoma:<version>
docker push <registry>/akkoma:<version>
```

### Local Testing

```bash
# Create test cluster
kind create cluster --name akkoma-test

# Install chart
helm install akkoma ./charts/akkoma -f values.test.yaml

# Watch pods
kubectl get pods -w

# Check logs
kubectl logs -f deployment/akkoma

# Port forward for testing
kubectl port-forward svc/akkoma 4000:4000
```

### Common Commands

```bash
# Update dependencies
helm dependency update charts/akkoma

# Lint chart
helm lint charts/akkoma

# Package chart
helm package charts/akkoma

# Template with values
helm template akkoma charts/akkoma -f values.yaml

# Dry run install
helm install akkoma charts/akkoma --dry-run --debug
```

## Akkoma-Specific Operations

### Database Migrations

Handled by init container or Job:
```bash
mix ecto.migrate
```

### User Management

Via kubectl exec:
```bash
kubectl exec -it deployment/akkoma -- mix pleroma.user new myuser email@example.com --admin
```

### Frontend Installation

Should be automated in init container:
```bash
mix pleroma.frontend install pleroma-fe --ref stable
mix pleroma.frontend install admin-fe --ref stable
```

### Configuration Updates

Configuration changes require pod restart:
```bash
kubectl rollout restart deployment/akkoma
```

## Security Considerations

### Secrets Management

- Never commit `prod.secret.exs` with real values
- Use Kubernetes Secrets for:
  - Database credentials
  - Secret key base
  - Instance signing keys
  - Admin passwords

### Network Policies

- Restrict database access to application pods only
- Ingress should only allow HTTPS
- Consider egress policies for federation

### RBAC

- Minimal ServiceAccount permissions
- No cluster-wide access needed
- Namespace-scoped resources only

## References

- [Akkoma Documentation](https://docs.akkoma.dev/)
- [Docker Installation Guide](https://docs.akkoma.dev/stable/installation/docker_en/)
- [Configuration Reference](https://docs.akkoma.dev/stable/configuration/cheatsheet/)
- [Federation Guide](https://blog.soykaf.com/post/how-federation-works/)
- [Backup and Restore](https://docs.akkoma.dev/stable/administration/backup/)
- [Updating Instances](https://docs.akkoma.dev/stable/administration/updating/)

## Chart Maintenance

### Version Tagging

- Chart version follows SemVer
- appVersion tracks Akkoma release version
- Update CHANGELOG.md for each release

### Testing Requirements

- All PRs must pass `helm lint`
- Template rendering must succeed
- Consider chart-testing (ct) for automation

### CI/CD

- GitHub Actions for chart linting
- Automated releases to chart repository
- Integration testing in ephemeral clusters
