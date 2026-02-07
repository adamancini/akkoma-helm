# Akkoma Helm Chart - Design Document

**Date:** 2026-02-04
**Status:** Draft - Refined after technical review
**Author:** Design Session
**Version:** 0.1.0

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Installation Methods Analysis](#installation-methods-analysis)
3. [Recommended Architecture](#recommended-architecture)
4. [Container Strategy](#container-strategy)
5. [Kubernetes Resources](#kubernetes-resources)
6. [Initialization Pattern](#initialization-pattern)
7. [Values Structure](#values-structure)
8. [Configuration Management](#configuration-management)
9. [Design Decisions](#design-decisions)
10. [Implementation Approach](#implementation-approach)
11. [Future Roadmap](#future-roadmap)

---

## Executive Summary

This document outlines the design for a production-ready Helm chart to deploy Akkoma, a federated social networking server (ActivityPub/Fediverse), on Kubernetes. The design prioritizes:

- **Simplicity over complexity** - Single-instance deployment pattern
- **OTP releases built from source** - Flexibility without S3 dependency
- **Immutable infrastructure** - Proper init containers, no post-install mutations
- **Security best practices** - External secrets support, minimal privileges
- **Progressive disclosure** - Simple defaults, advanced options when needed
- **Operational pragmatism** - Proven patterns over premature optimization

### Key Design Choices (v0.1.0)

- **Single-instance only** - No clustering or horizontal scaling
- **Deployment with Recreate strategy** - Not StatefulSet (simpler for single-instance)
- **OTP release built from source** - Multi-stage Dockerfile, build from any git ref
- **Simple PostgreSQL StatefulSet** - No subchart dependencies, no operator requirement
- **Helm-templated configuration** - Runtime env vars for secrets
- **Helm lookup for secret generation** - No Jobs or RBAC complexity, secrets separated by scope
- **Three init containers** - Database readiness, migrations, and frontend installation
- **Startup probe** - Allows 150s for initial startup and migrations
- **NetworkPolicies** - Zero-trust networking enabled by default (v0.1.0)
- **No CPU limits** - Allow bursting for BEAM scheduler efficiency
- **seccompProfile RuntimeDefault** - Baseline security without read-only root filesystem
- **PVC storage for v0.1.0** - External S3 support, object storage bundling deferred to v0.2.0
- **Progressive disclosure** - Basic/advanced values structure
- **amd64-only** - Multi-arch support deferred

### Included in v0.1.0 (Added After Design Review)

- ✅ **NetworkPolicies** - Zero-trust networking for application and database
- ✅ **seccompProfile RuntimeDefault** - Baseline security hardening
- ✅ **Separated secrets** - Application vs database least privilege
- ✅ **Startup probe** - Allow 150s for slow first boot and migrations
- ✅ **No CPU limits** - Allow BEAM bursting for better performance
- ✅ **NOTES.txt** - Post-install instructions and warnings
- ✅ **Helm tests** - Automated connection validation

### Shipped in v0.2.0

- **Read-only root filesystem** with tmpfs mounts for BEAM VM
- **Multi-architecture support** (amd64 + arm64)
- **Object storage** via Garage subchart and external S3 support
- **Prometheus metrics** with ServiceMonitor
- **Backup/restore documentation**
- **CI improvements** with multi-version K8s validation

### Deferred to Future Releases

- **v0.3.0**: Grafana dashboard, HA PostgreSQL, media pruning CronJob
- **Future**: Horizontal scaling (if Akkoma adds support)

---

## Installation Methods Analysis

### Source Review

Analyzed five official Akkoma installation methods:
1. **Alpine Linux** (from source)
2. **Debian-based** (from source)
3. **Docker** (thin wrapper approach)
4. **OTP Releases** (pre-built binaries)
5. **Optional media packages** (ImageMagick, ffmpeg, ExifTool)

### OTP Releases vs From-Source

#### Decision: Build OTP Releases from Source

**Why OTP releases:**
- Self-contained pre-built binaries
- Smallest footprint (~200MB vs 800MB)
- Fastest startup time (10-20s vs 30-60s)
- No runtime compilation required

**Why build from source (not download):**
- ✅ Build from any git ref (tags, branches, commits, PRs)
- ✅ Apply custom patches if needed
- ✅ No dependency on Akkoma S3 release schedule
- ✅ Docker buildx handles builds cleanly
- ❌ Build time: 10-15 minutes (vs 2-3 for download)

**Build process:**
```dockerfile
# Stage 1: Build OTP release
FROM elixir:1.14-alpine AS builder
RUN mix release

# Stage 2: Runtime (same benefits as pre-built)
FROM alpine:3.19
COPY --from=builder /build/_build/prod/rel/pleroma /opt/akkoma
```

**Result:** OTP release benefits (small, fast) with source flexibility.

### Optional Dependencies

Three packages enhance media handling, included in base image but disabled by default:

1. **ImageMagick** - Thumbnail generation, image manipulation
2. **ffmpeg** - Video transcoding, animated previews
3. **ExifTool** - Metadata stripping, privacy features

Users enable via configuration in values.yaml.

---

## Recommended Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────┐
│                      Ingress (HTTPS)                    │
│              akkoma.example.com → akkoma-svc            │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  Service: akkoma-svc                    │
│                     (ClusterIP:4000)                    │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│              Deployment: akkoma (replicas: 1)           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Init Containers:                               │   │
│  │  1. wait-for-db                                 │   │
│  │  2. db-migrate                                  │   │
│  │  3. install-frontends                           │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Main Container: akkoma                         │   │
│  │  - OTP Release binary                           │   │
│  │  - Port 4000                                    │   │
│  │  - /opt/akkoma/uploads → PVC                    │   │
│  │  - /opt/akkoma/instance/static/frontends → PVC  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│              Service: postgresql                        │
│                  (ClusterIP:5432)                       │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│      StatefulSet: postgresql (replicas: 1)              │
│      - PostgreSQL 15                                    │
│      - Persistent volume for data                       │
│      - initdb script for database setup                 │
└─────────────────────────────────────────────────────────┘
```

### Resource List

1. **Deployment**: `akkoma`
   - Main application server (single replica)
   - OTP release-based container
   - Recreate update strategy
   - Mounts: uploads PVC, frontends PVC, config/secrets

2. **Service**: `akkoma` (ClusterIP)
   - Internal service for application
   - Port 4000

3. **Ingress**: External HTTPS access
   - TLS termination
   - Generic annotations (controller-agnostic)

4. **ConfigMap**: `akkoma-config`
   - Helm-templated `prod.secret.exs` with env var placeholders
   - Non-sensitive configuration

5. **Secret**: `akkoma-secrets`
   - Generated via Helm lookup (preserved on upgrade)
   - Secret key base, signing salt, release cookie
   - Database credentials

6. **Secret**: `akkoma-external-secrets` (optional)
   - User-managed via Sealed Secrets / External Secrets Operator
   - Alternative to generated secrets for production

7. **PersistentVolumeClaim**: `akkoma-uploads`
   - Media storage (user uploads, cached remote media)
   - Size: 50Gi default

8. **PersistentVolumeClaim**: `akkoma-frontends`
   - Frontend assets (pleroma-fe, admin-fe)
   - Size: 5Gi default
   - Separate lifecycle from uploads

9. **StatefulSet**: `postgresql`
   - PostgreSQL 15 (official image)
   - Simple single-instance deployment
   - PVC for data persistence
   - initdb script for database/extension creation

10. **Service**: `postgresql` (ClusterIP)
    - Database service
    - Port 5432

11. **ConfigMap**: `postgresql-init`
    - Database initialization SQL
    - Creates database, user, extensions

12. **NetworkPolicy**: `akkoma` (v0.1.0)
    - Restricts ingress to ingress controller only
    - Allows egress to PostgreSQL, DNS, and federation (HTTPS)
    - Follows zero-trust networking principles

13. **NetworkPolicy**: `akkoma-postgresql` (v0.1.0)
    - Restricts ingress to Akkoma pods only
    - Allows egress for DNS resolution
    - Isolates database from unauthorized access

---

## Container Strategy

### Multi-Stage Dockerfile (OTP Release from Source)

**Target: Build OTP release, minimal runtime image**

```dockerfile
# Stage 1: Build OTP release from source
FROM elixir:1.14-alpine AS builder

RUN apk add --no-cache \
    git \
    build-base \
    cmake \
    postgresql-client

ARG AKKOMA_VERSION=v3.13.2
WORKDIR /build

RUN git clone --branch ${AKKOMA_VERSION} \
    https://akkoma.dev/AkkomaGang/akkoma.git . && \
    mix local.hex --force && \
    mix local.rebar --force

# Get dependencies and compile
ENV MIX_ENV=prod
RUN mix deps.get --only prod && \
    mix do compile, release

# Stage 2: Runtime image
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ncurses-libs \
    postgresql-client \
    imagemagick \
    ffmpeg \
    exiftool \
    libmagic \
    file \
    ca-certificates \
    openssl

# Create akkoma user and group
RUN addgroup -g 1000 akkoma && \
    adduser -D -u 1000 -G akkoma akkoma

# Copy OTP release from builder
COPY --from=builder --chown=akkoma:akkoma \
    /build/_build/prod/rel/pleroma /opt/akkoma

WORKDIR /opt/akkoma
USER akkoma

# Expose application port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
  CMD wget -q -O /dev/null http://localhost:4000/api/v1/instance || exit 1

# Start application
CMD ["./bin/pleroma", "start"]
```

### Image Characteristics

| Metric | Value |
|--------|-------|
| Build time | 10-15 minutes |
| Image size | ~200MB |
| Startup time | 10-20s |
| Architecture | amd64 (v0.1.0) |

### Build Arguments

- `AKKOMA_VERSION`: Git ref to build (tag, branch, commit)
- Defaults to latest stable release tag

### Container Runtime Commands

**Management via pleroma_ctl:**
```bash
# Database migrations
./bin/pleroma_ctl migrate

# User management
./bin/pleroma_ctl user new username email@example.com --admin

# Frontend installation
./bin/pleroma_ctl frontend install pleroma-fe --ref stable

# Remote console
./bin/pleroma_ctl remote_console
```

---

## Kubernetes Resources

### 1. Deployment: Akkoma Application

**Pattern: Deployment with Recreate strategy**

**Why Deployment (not StatefulSet):**
- ✅ Single instance always (no ordering needed)
- ✅ Simpler template (no volumeClaimTemplates)
- ✅ Faster rollouts
- ✅ Standard pattern for single-instance apps
- ✅ PVC reattaches automatically on pod restart

**Why Recreate strategy:**
- Akkoma is single-instance (no rolling update benefit)
- Clean shutdown/startup on upgrade
- Avoids two pods trying to write to same PVC

**Template excerpt:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "akkoma.fullname" . }}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      {{- include "akkoma.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "akkoma.selectorLabels" . | nindent 8 }}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      initContainers:
        # See "Initialization Pattern" section
      containers:
        - name: akkoma
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - name: http
              containerPort: 4000
          startupProbe:
            httpGet:
              path: /api/v1/instance
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 30  # 150s max startup time
          livenessProbe:
            httpGet:
              path: /api/v1/instance
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /api/v1/instance
              port: http
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 2
          volumeMounts:
            - name: config
              mountPath: /opt/akkoma/config
            - name: uploads
              mountPath: /opt/akkoma/uploads
            - name: frontends
              mountPath: /opt/akkoma/instance/static/frontends
          env:
            - name: RELEASE_COOKIE
              valueFrom:
                secretKeyRef:
                  name: {{ include "akkoma.fullname" . }}-secrets
                  key: release-cookie
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef:
                  name: {{ include "akkoma.secretName" . }}
                  key: secret-key-base
            - name: SIGNING_SALT
              valueFrom:
                secretKeyRef:
                  name: {{ include "akkoma.secretName" . }}
                  key: signing-salt
            - name: DB_HOST
              value: {{ include "akkoma.postgresql.host" . }}
            - name: DB_NAME
              value: {{ .Values.postgresql.database }}
            - name: DB_USER
              value: {{ .Values.postgresql.username }}
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "akkoma.postgresql.secretName" . }}
                  key: password
      volumes:
        - name: config
          configMap:
            name: {{ include "akkoma.fullname" . }}-config
        - name: uploads
          persistentVolumeClaim:
            claimName: {{ include "akkoma.fullname" . }}-uploads
        - name: frontends
          persistentVolumeClaim:
            claimName: {{ include "akkoma.fullname" . }}-frontends
```

### 2. StatefulSet: PostgreSQL

**Simple PostgreSQL deployment without subchart dependencies**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "akkoma.fullname" . }}-postgresql
spec:
  serviceName: {{ include "akkoma.fullname" . }}-postgresql
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
      release: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: postgresql
        release: {{ .Release.Name }}
    spec:
      containers:
        - name: postgresql
          image: postgres:15-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: {{ .Values.postgresql.username }}
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "akkoma.fullname" . }}-secrets
                  key: postgres-password
            - name: POSTGRES_DB
              value: {{ .Values.postgresql.database }}
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
            - name: init-scripts
              mountPath: /docker-entrypoint-initdb.d
      volumes:
        - name: init-scripts
          configMap:
            name: {{ include "akkoma.fullname" . }}-postgresql-init
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        {{- if .Values.postgresql.storageClass }}
        storageClassName: {{ .Values.postgresql.storageClass }}
        {{- end }}
        resources:
          requests:
            storage: {{ .Values.postgresql.storageSize }}
```

### 3. ConfigMap: PostgreSQL Initialization

**Database setup via PostgreSQL's initdb mechanism**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "akkoma.fullname" . }}-postgresql-init
data:
  01-init.sql: |
    -- Create akkoma user (if not exists via POSTGRES_USER)
    -- Create database (if not exists via POSTGRES_DB)

    -- Connect to akkoma database
    \c {{ .Values.postgresql.database }};

    -- Create required extensions
    CREATE EXTENSION IF NOT EXISTS citext;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    -- Grant privileges
    GRANT ALL PRIVILEGES ON DATABASE {{ .Values.postgresql.database }} TO {{ .Values.postgresql.username }};
```

**Note:** This runs only when PostgreSQL data directory is empty (standard initdb behavior).

---

### 4. NetworkPolicy: Akkoma Application

**Zero-trust networking for the application:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "akkoma.fullname" . }}
spec:
  podSelector:
    matchLabels:
      {{- include "akkoma.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow ingress from ingress controller
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx  # Adjust based on ingress controller
      ports:
        - protocol: TCP
          port: 4000
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Allow PostgreSQL connection
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
              release: {{ .Release.Name }}
      ports:
        - protocol: TCP
          port: 5432
    # Allow HTTPS for ActivityPub federation
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
```

**Rationale:**
- Restricts ingress to only the ingress controller
- Allows only necessary egress (DNS, PostgreSQL, federation)
- Prevents lateral movement in case of compromise
- Can be disabled with `networkPolicy.enabled: false`

---

### 5. NetworkPolicy: PostgreSQL

**Database isolation policy:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "akkoma.fullname" . }}-postgresql
spec:
  podSelector:
    matchLabels:
      app: postgresql
      release: {{ .Release.Name }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Only allow connections from Akkoma pods
    - from:
        - podSelector:
            matchLabels:
              {{- include "akkoma.selectorLabels" . | nindent 14 }}
      ports:
        - protocol: TCP
          port: 5432
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
```

**Rationale:**
- PostgreSQL only accepts connections from Akkoma pods
- Prevents unauthorized database access from other namespaces
- Simple policy with minimal maintenance

---

## Initialization Pattern

### Init Container Sequence

**Goal:** Ensure database is ready and migrations are applied before starting the application.

```yaml
initContainers:
  # 1. Wait for PostgreSQL to be ready
  - name: wait-for-db
    image: postgres:15-alpine
    command:
      - sh
      - -c
      - |
        echo "Waiting for PostgreSQL at ${DB_HOST}:5432..."
        until pg_isready -h ${DB_HOST} -p 5432 -U ${DB_USER}; do
          echo "Database not ready, waiting..."
          sleep 2
        done
        echo "Database is ready!"
    env:
      - name: DB_HOST
        value: {{ include "akkoma.postgresql.host" . }}
      - name: DB_USER
        value: {{ .Values.postgresql.username }}

  # 2. Run database migrations
  - name: db-migrate
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    command: ['./bin/pleroma_ctl', 'migrate']
    env:
      - name: RELEASE_COOKIE
        valueFrom:
          secretKeyRef:
            name: {{ include "akkoma.fullname" . }}-secrets
            key: release-cookie
      - name: DB_HOST
        value: {{ include "akkoma.postgresql.host" . }}
      - name: DB_NAME
        value: {{ .Values.postgresql.database }}
      - name: DB_USER
        value: {{ .Values.postgresql.username }}
      - name: DB_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "akkoma.postgresql.secretName" . }}
            key: password
    volumeMounts:
      - name: config
        mountPath: /opt/akkoma/config

  # 3. Install frontends (to persistent volume)
  - name: install-frontends
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    command:
      - sh
      - -c
      - |
        # Check if frontends already installed
        if [ -d "/frontends/pleroma-fe" ] && [ -d "/frontends/admin-fe" ]; then
          echo "Frontends already installed, skipping"
          exit 0
        fi

        echo "Installing frontends..."
        ./bin/pleroma_ctl frontend install pleroma-fe --ref stable
        ./bin/pleroma_ctl frontend install admin-fe --ref stable
        echo "Frontends installed successfully"
    volumeMounts:
      - name: frontends
        mountPath: /opt/akkoma/instance/static/frontends
      - name: config
        mountPath: /opt/akkoma/config
    env:
      - name: RELEASE_COOKIE
        valueFrom:
          secretKeyRef:
            name: {{ include "akkoma.fullname" . }}-secrets
            key: release-cookie
```

### Init Container Behavior

| Container | First Install | Upgrade | Restart |
|-----------|---------------|---------|---------|
| wait-for-db | ✅ Runs | ✅ Runs | ✅ Runs |
| db-migrate | ✅ Runs | ✅ Runs | ✅ Runs (idempotent) |
| install-frontends | ✅ Installs | ⏭️ Skips (check exists) | ⏭️ Skips |

**Key Points:**
- `wait-for-db`: Always ensures connectivity
- `db-migrate`: Idempotent, safe to run repeatedly
- `install-frontends`: Checks for existing installation, writes to PVC

**Removed complexity:**
- No `db-setup` init container (PostgreSQL initdb handles it)
- No `config-init` init container (Helm templates the config)
- No post-install Jobs (init containers handle everything)

---

## Values Structure

### Progressive Disclosure Pattern

**Philosophy:** Simple defaults that work, advanced options clearly separated.

```yaml
#
# BASIC CONFIGURATION
# These are the only required values to get started
#

# Instance configuration
akkoma:
  # REQUIRED: Your instance domain (must match Ingress)
  domain: "akkoma.example.com"

  # REQUIRED: Admin email for notifications
  adminEmail: "admin@example.com"

# TLS configuration
ingress:
  enabled: true
  className: "nginx"
  tls:
    enabled: true
    secretName: "akkoma-tls"  # Create with cert-manager or manually

#
# ADVANCED CONFIGURATION
# Optional overrides for specific needs
#

# External secrets (production)
externalSecret:
  enabled: false
  # When enabled, chart expects these Secrets to exist:
  # - name: Name of Secret containing keys below
  # - keys:
  #     secretKeyBase: "secret-key-base"
  #     signingSalt: "signing-salt"
  #     releaseCookie: "release-cookie"

# PostgreSQL configuration
postgresql:
  storageSize: 10Gi
  # storageClass: ""  # Use cluster default
  # external:  # Use external PostgreSQL instead of bundled
  #   enabled: false
  #   host: "postgres.example.com"
  #   port: 5432
  #   database: "akkoma"
  #   username: "akkoma"
  #   passwordSecret: "postgres-credentials"
  #   passwordKey: "password"

# Storage configuration
storage:
  uploads:
    size: 50Gi
    # storageClass: ""
  frontends:
    size: 5Gi
    # storageClass: ""
  # s3:  # External S3 support (v0.1.0)
  #   enabled: false
  #   endpoint: "s3.amazonaws.com"
  #   region: "us-east-1"
  #   bucket: "akkoma-uploads"
  #   accessKeySecret: "s3-credentials"
  #   accessKeyKey: "access-key"
  #   secretKeyKey: "secret-key"

# Instance behavior
instance:
  # Character limit for posts
  characterLimit: 5000

  # Allow new user registrations
  registrationsOpen: false

  # Upload size limit (bytes)
  uploadLimit: 16000000

# Resource limits (no CPU limits for Elixir/BEAM workloads)
resources:
  requests:
    cpu: 500m      # Guaranteed CPU for scheduling
    memory: 1Gi    # Guaranteed memory
  limits:
    # No CPU limit - allow bursting for BEAM scheduler efficiency
    memory: 2Gi    # OOM protection only

# PostgreSQL resource limits
postgresql:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      memory: 1Gi

# Network security (enabled by default)
networkPolicy:
  enabled: true
  # Restricts traffic to:
  # - Ingress from ingress controller
  # - Egress to PostgreSQL, DNS, and federation (HTTPS)

# Observability (disabled by default)
metrics:
  enabled: false
  # When enabled, adds ServiceMonitor for Prometheus
  # Requires telemetry_metrics_prometheus in container

# Security context (hardened in v0.1.0, read-only filesystem in v0.2.0)
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault  # Added in v0.1.0 for baseline security

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  # readOnlyRootFilesystem: false  # TODO: Enable in v0.2.0 after writable path testing

# Image configuration
image:
  repository: ghcr.io/adamancini/akkoma
  tag: ""  # Defaults to Chart.appVersion
  pullPolicy: IfNotPresent
```

### Values Categories

**Essential (Must Configure):**
- `akkoma.domain`
- `akkoma.adminEmail`
- `ingress.tls.secretName`

**Important (Recommended to Review):**
- `postgresql.storageSize`
- `storage.uploads.size`
- `resources`

**Optional (Use Defaults):**
- Everything else

---

## Configuration Management

### Strategy Overview

**Three-layer configuration system:**

1. **Helm-templated Elixir config** (ConfigMap)
   - `prod.secret.exs` with `System.get_env()` placeholders
   - All runtime configuration
   - Non-sensitive values from values.yaml

2. **Generated Secrets** (Helm lookup)
   - Auto-generated on first install
   - Preserved across upgrades
   - Secret key base, signing salt, release cookie

3. **External Secrets** (optional, production)
   - User-managed via Sealed Secrets / ESO / Vault
   - Overrides generated secrets when enabled
   - Database passwords, S3 credentials

### ConfigMap: Akkoma Configuration

**Helm-templated prod.secret.exs with runtime env vars:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "akkoma.fullname" . }}-config
data:
  prod.secret.exs: |
    import Config

    # Web endpoint configuration
    config :pleroma, Pleroma.Web.Endpoint,
      url: [host: "{{ .Values.akkoma.domain }}", scheme: "https", port: 443],
      http: [ip: {0, 0, 0, 0}, port: 4000],
      secret_key_base: System.get_env("SECRET_KEY_BASE"),
      signing_salt: System.get_env("SIGNING_SALT")

    # Instance configuration
    config :pleroma, :instance,
      name: "{{ .Values.akkoma.domain }}",
      email: "{{ .Values.akkoma.adminEmail }}",
      notify_email: "{{ .Values.akkoma.adminEmail }}",
      limit: {{ .Values.instance.characterLimit }},
      registrations_open: {{ .Values.instance.registrationsOpen }},
      upload_limit: {{ .Values.instance.uploadLimit }}

    # Database configuration
    config :pleroma, Pleroma.Repo,
      adapter: Ecto.Adapters.Postgres,
      username: System.get_env("DB_USER"),
      password: System.get_env("DB_PASSWORD"),
      database: System.get_env("DB_NAME"),
      hostname: System.get_env("DB_HOST"),
      pool_size: 10

    # Upload configuration
    {{- if .Values.storage.s3.enabled }}
    config :pleroma, Pleroma.Upload,
      uploader: Pleroma.Uploaders.S3,
      base_url: System.get_env("S3_ENDPOINT"),
      bucket: System.get_env("S3_BUCKET")
    {{- else }}
    config :pleroma, Pleroma.Upload,
      uploader: Pleroma.Uploaders.Local,
      base_path: "/opt/akkoma/uploads"
    {{- end }}

    # Media proxy configuration
    config :pleroma, :media_proxy,
      enabled: true,
      proxy_opts: [
        redirect_on_failure: true,
        max_body_length: {{ .Values.instance.uploadLimit }}
      ]

    # Logging configuration
    config :logger, :console,
      format: "$time $metadata[$level] $message\n",
      metadata: [:request_id]
```

### Secrets: Separated by Scope (Least Privilege)

**Application secrets (used by Akkoma pods):**

```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace (printf "%s-secrets" (include "akkoma.fullname" .)) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "akkoma.fullname" . }}-secrets
type: Opaque
data:
  {{- if $existing }}
  # Preserve existing secrets on upgrade
  secret-key-base: {{ $existing.data.secret-key-base }}
  signing-salt: {{ $existing.data.signing-salt }}
  release-cookie: {{ $existing.data.release-cookie }}
  {{- else }}
  # Generate on first install
  secret-key-base: {{ randAlphaNum 64 | b64enc | quote }}
  signing-salt: {{ randAlphaNum 8 | b64enc | quote }}
  release-cookie: {{ randAlphaNum 64 | b64enc | quote }}
  {{- end }}
```

**PostgreSQL secrets (used by PostgreSQL pods):**

```yaml
{{- $existingPg := lookup "v1" "Secret" .Release.Namespace (printf "%s-postgresql" (include "akkoma.fullname" .)) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "akkoma.fullname" . }}-postgresql
type: Opaque
data:
  {{- if $existingPg }}
  postgres-password: {{ $existingPg.data.postgres-password }}
  {{- else }}
  postgres-password: {{ randAlphaNum 32 | b64enc | quote }}
  {{- end }}
```

**Security rationale:** Separating secrets follows least privilege principle. Akkoma pods only mount application secrets, PostgreSQL pods only mount database secrets. This reduces blast radius if a Secret is compromised.

**Benefits:**
- ✅ No Job or RBAC required
- ✅ Secrets persist across upgrades
- ✅ Standard Helm pattern (used by Bitnami)
- ✅ Least privilege with separated secrets

**Caveats:**
- ⚠️ `helm template` shows different values (not using lookup)
- ⚠️ **NEVER commit generated secrets to version control**
- ⚠️ Production should use external secrets management
- ⚠️ If Secret is deleted but release remains, next upgrade regenerates secrets

### External Secrets Support

**When `externalSecret.enabled: true`:**

```yaml
# Helper template
{{- define "akkoma.secretName" -}}
{{- if .Values.externalSecret.enabled -}}
{{ .Values.externalSecret.name }}
{{- else -}}
{{ include "akkoma.fullname" . }}-secrets
{{- end -}}
{{- end -}}

# Usage in Deployment
env:
  - name: SECRET_KEY_BASE
    valueFrom:
      secretKeyRef:
        name: {{ include "akkoma.secretName" . }}
        key: {{ .Values.externalSecret.keys.secretKeyBase | default "secret-key-base" }}
```

**⚠️ CRITICAL: Secret Management Security**

**NEVER commit generated secrets to version control:**
- Generated secrets are stored in Kubernetes, not Helm chart
- `helm get values` will show generated secrets - do not commit output
- Add `secrets*.yaml` and `*-secrets.yaml` to `.gitignore`
- Production deployments MUST use external secrets management

**User workflow with Sealed Secrets:**

```bash
# 1. Create plain Secret
kubectl create secret generic akkoma-external-secrets \
  --from-literal=secret-key-base=$(openssl rand -hex 64) \
  --from-literal=signing-salt=$(openssl rand -hex 8) \
  --from-literal=release-cookie=$(openssl rand -hex 64) \
  --dry-run=client -o yaml > secret.yaml

# 2. Seal it
kubeseal -f secret.yaml -w sealed-secret.yaml

# 3. Apply sealed secret
kubectl apply -f sealed-secret.yaml

# 4. Install chart with external secrets
helm install akkoma ./charts/akkoma \
  --set externalSecret.enabled=true \
  --set externalSecret.name=akkoma-external-secrets
```

**Secret rotation procedures:**
- Rotating `secret-key-base` or `signing-salt` invalidates all user sessions
- Database password rotation requires coordinated update of PostgreSQL and Akkoma
- Document rotation procedures in operations guide

---

## Design Decisions

### 1. Single-Instance Only

**Decision:** Akkoma is always deployed as a single instance.

**Rationale:**
- Akkoma doesn't support horizontal scaling (shared state, no clustering)
- Distributed Erlang clustering not configured in Akkoma by default
- Simpler deployment, operations, and troubleshooting
- Matches actual usage pattern (most Akkoma instances are single-node)

**Trade-offs:**
- ❌ No horizontal scaling for read traffic
- ❌ Downtime during upgrades (but minimal with Recreate strategy)
- ✅ Simpler architecture
- ✅ No split-brain concerns
- ✅ Easier to reason about state

**Future:** If Akkoma adds clustering support, revisit in v2.x

### 2. Deployment (Not StatefulSet)

**Decision:** Use Deployment with Recreate strategy, not StatefulSet.

**Rationale:**
- Single instance means no ordering/identity benefits from StatefulSet
- Deployment with Recreate provides same guarantees (one pod at a time)
- Simpler template (no volumeClaimTemplates)
- PVC reattaches automatically on pod restart
- More familiar to operators

**Trade-offs:**
- ❌ Pod name changes on restart (not stable identity)
- ✅ Simpler templates
- ✅ Faster rollouts
- ✅ Standard pattern for single-instance apps

**Implementation:**
```yaml
strategy:
  type: Recreate  # Terminate old pod before starting new
```

### 3. OTP Releases Built from Source

**Decision:** Build OTP releases using multi-stage Dockerfile, not download from S3.

**Rationale:**
- Same benefits as pre-built OTP releases (small, fast)
- Freedom to build from any git ref (tags, branches, commits)
- Can apply custom patches if needed
- No dependency on Akkoma S3 release schedule
- Docker buildx handles builds cleanly

**Trade-offs:**
- ❌ Build time: 10-15 minutes (vs 2-3 for download)
- ✅ Full flexibility
- ✅ Same runtime characteristics
- ✅ No external dependency

**Future:** Multi-arch support (arm64) in v0.2.0

### 4. Simple PostgreSQL StatefulSet

**Decision:** Include simple PostgreSQL StatefulSet, no subchart dependencies.

**Rationale:**
- "Batteries included" for easy getting started
- No dependency on Bitnami charts (large, complex)
- No operator requirement (CloudNativePG, Zalando, Crunchy)
- Direct control over configuration
- ~150 lines of templates vs 1000+ with subchart

**Trade-offs:**
- ❌ Not HA (single instance)
- ❌ No advanced features (backups, monitoring, replication)
- ✅ Simple to understand and maintain
- ✅ Works out of the box
- ✅ Users can bring their own PostgreSQL (RDS, Cloud SQL)

**Production:** Use external managed PostgreSQL or install operator separately.

### 5. Helm-Templated Configuration

**Decision:** Template `prod.secret.exs` with Helm, use runtime env vars for secrets.

**Rationale:**
- Full control over configuration structure
- No dependency on `pleroma_ctl instance gen` command
- Secrets stay in Kubernetes Secrets (not baked into config file)
- Support for external secrets via env var injection
- Clear separation: config (ConfigMap) vs secrets (Secret)

**Trade-offs:**
- ❌ Must maintain Elixir config template
- ❌ Updates needed if Akkoma config format changes
- ✅ Full control and flexibility
- ✅ GitOps-friendly
- ✅ External secrets support

**Maintenance:** Monitor Akkoma releases for config changes, update template accordingly.

### 6. Helm Lookup for Secret Generation

**Decision:** Use Helm's `lookup` function to generate and preserve secrets.

**Rationale:**
- No Job or RBAC required
- Standard Helm pattern (used by Bitnami, many others)
- Secrets persist across upgrades automatically
- Simple implementation

**Trade-offs:**
- ⚠️ `helm template --dry-run` shows different values (not using lookup)
- ✅ No additional resources
- ✅ Simple and well-understood
- ✅ Works with external secrets (dual-mode)

**Alternative considered:** Job with RBAC to create Secret → Rejected (unnecessary complexity)

### 7. Init Containers (Not Jobs)

**Decision:** Use init containers for database readiness, migrations, and frontend installation.

**Rationale:**
- Init containers run before main container (guaranteed ordering)
- Idempotent: safe to run on every pod start
- No race conditions (StatefulSet starts only after init completes)
- Simpler than Helm hooks (no lifecycle management)

**Removed patterns:**
- ❌ `db-setup` init container → PostgreSQL initdb handles it
- ❌ `config-init` init container → Helm templates handle it
- ❌ Post-install Jobs → Init containers sufficient

**Trade-offs:**
- ✅ Simpler deployment (fewer resources)
- ✅ Idempotent operations
- ✅ Clear dependency chain
- ❌ Frontend installation on every restart (but skips if exists)

### 8. Separate Frontends PVC

**Decision:** Separate PVC for frontends, distinct from uploads PVC.

**Rationale:**
- Different lifecycle (frontends rarely change, uploads grow continuously)
- Smaller PVC for frontends (5Gi vs 50Gi for uploads)
- Easier to manage separately (backup, expansion)
- Init container writes frontends to persistent storage

**Trade-offs:**
- ❌ Additional PVC to manage
- ✅ Clear separation of concerns
- ✅ Cheaper (don't need to back up 50Gi for 5Gi of frontends)

**Alternative considered:** Bake frontends into image → Rejected (bloats image, harder to update)

### 9. Progressive Disclosure Values

**Decision:** Two-tier values structure (basic/advanced).

**Rationale:**
- New users see only 5-10 required values
- Advanced users can override 50+ values
- Sensible defaults for everything
- Reduces decision paralysis

**Implementation:**
- Clear comments delineate BASIC vs ADVANCED sections
- Required values fail with helpful error messages
- Optional values have documented defaults

**Trade-offs:**
- ✅ Easier onboarding
- ✅ Still flexible for advanced use cases
- ❌ More documentation needed

### 10. Storage Strategy (v0.1.0)

**Decision:** PVC for uploads, external S3 support, defer object storage bundling.

**Rationale:**
- PVC works out of the box (no additional dependencies)
- External S3 support for production users (AWS, Backblaze, Wasabi)
- Object storage bundling (SeaweedFS) deferred to v0.2.0
- Progressive path: PVC → external S3 → bundled object storage

**Trade-offs:**
- ❌ PVC can fill up (need monitoring)
- ❌ No automatic cleanup of old media
- ✅ Simple to start
- ✅ Clear upgrade path documented

**Future (v0.2.0):** Evaluate SeaweedFS bundling with proper HA setup.

### 11. Security Posture (v0.1.0)

**Decision:** Hardened security context with RuntimeDefault seccomp, defer read-only filesystem.

**Rationale:**
- v0.1.0 includes baseline hardening (seccomp, no privilege escalation, separated secrets)
- NetworkPolicies included for zero-trust networking (low-risk, high-value)
- `readOnlyRootFilesystem: true` requires testing to identify all writable paths
- BEAM/Elixir may need unexpected temp directories
- Progressive hardening: establish strong baseline, then add read-only filesystem

**Current (v0.1.0):**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault  # Restricts dangerous syscalls

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: false  # TODO: v0.2.0 after writable path testing
```

**Security measures in v0.1.0:**
- ✅ seccompProfile RuntimeDefault (baseline security)
- ✅ NetworkPolicies for Akkoma and PostgreSQL
- ✅ Separated secrets (application vs database)
- ✅ No privilege escalation
- ✅ All capabilities dropped
- ✅ Non-root user (UID 1000)

**Future (v0.2.0):** Enable read-only root filesystem with explicit tmpfs mounts after testing identifies required writable paths.

### 12. Observability (v0.1.0)

**Decision:** Metrics optional and disabled by default.

**Rationale:**
- Prometheus metrics require additional Elixir dependency (`telemetry_metrics_prometheus`)
- Not essential for initial deployment
- Progressive disclosure: add when needed

**Implementation:**
```yaml
metrics:
  enabled: false
  # When enabled:
  # - Adds telemetry dependency to image
  # - Creates ServiceMonitor
  # - Exposes /metrics endpoint
```

**Trade-offs:**
- ✅ Simpler initial setup
- ✅ Smaller image by default
- ❌ No built-in monitoring

### 13. Multi-Architecture Support

**Decision:** amd64-only for v0.1.0, multi-arch in v0.2.0.

**Rationale:**
- Most production Kubernetes clusters are amd64
- Simpler testing and CI
- arm64 support needs platform-specific testing (ffmpeg, ImageMagick)

**Future (v0.2.0):** Add arm64 support after amd64 validation.

### 14. Ingress Configuration

**Decision:** Generic Ingress annotations only, controller-agnostic.

**Rationale:**
- nginx-ingress is going EOL soon
- Users have different ingress controllers (Traefik, HAProxy, Caddy, Istio)
- Avoid controller-specific configuration snippets (security risk)

**Implementation:**
- Provide generic annotations (cert-manager, body size limits)
- Document controller-specific examples separately
- Let Akkoma's built-in media proxy handle caching

**Trade-offs:**
- ✅ Portable across controllers
- ✅ Simpler, safer configuration
- ❌ No built-in caching at ingress layer

**Documentation:** Provide examples for nginx, Traefik, HAProxy, Caddy in separate doc.

---

## Implementation Approach

### Iterative Vertical Slices

**Philosophy:** Deliver working software incrementally, not in phases.

Each iteration produces a deployable, testable system.

### Iteration 1: End-to-End Minimum (Day 1-2)

**Goal:** Single pod running Akkoma with in-cluster PostgreSQL

**Scope:**
- [ ] Deployment (basic, no init containers)
- [ ] PostgreSQL StatefulSet (simple, single instance)
- [ ] Service for Akkoma
- [ ] Service for PostgreSQL
- [ ] Hardcoded ConfigMap with minimal config
- [ ] Basic Secret (hardcoded values)
- [ ] Chart.yaml, values.yaml scaffold

**Success criteria:**
- `helm install akkoma ./charts/akkoma` succeeds
- Pod starts and reaches Running state
- Can port-forward and see Akkoma web UI
- Manual database creation works

**Testing:**
```bash
helm install akkoma ./charts/akkoma
kubectl port-forward svc/akkoma 4000:4000
curl http://localhost:4000/api/v1/instance
```

**Exit criteria:** Working deployment with manual setup.

---

### Iteration 2: Database Initialization (Day 3-4)

**Goal:** Automated database setup and migrations

**Scope:**
- [ ] PostgreSQL initdb ConfigMap (setup_db.sql)
- [ ] wait-for-db init container
- [ ] db-migrate init container
- [ ] Test upgrade path (helm upgrade preserves data)

**Success criteria:**
- Database and extensions created automatically
- Migrations run on first install
- Migrations run on upgrades
- Data persists across pod restarts

**Testing:**
```bash
helm install akkoma ./charts/akkoma
kubectl exec -it deployment/akkoma -- ./bin/pleroma_ctl user new admin admin@example.com --admin
helm upgrade akkoma ./charts/akkoma --set image.tag=new-version
# Verify user still exists
```

**Exit criteria:** Zero manual database setup required.

---

### Iteration 3: Configuration & Secrets (Day 5-6)

**Goal:** Helm-templated config and secret generation

**Scope:**
- [ ] Helm-templated prod.secret.exs ConfigMap
- [ ] Helm lookup-based secret generation
- [ ] External secrets support (dual-mode)
- [ ] Environment variable injection to pods
- [ ] values.yaml structure (basic/advanced)

**Success criteria:**
- Can configure domain, admin email via values.yaml
- Secrets generated on install, preserved on upgrade
- External secrets mode works (test with pre-created Secret)
- All sensitive values come from Secrets (not ConfigMap)

**Testing:**
```bash
# Test generated secrets
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=test.example.com \
  --set akkoma.adminEmail=admin@test.example.com

# Test external secrets
kubectl create secret generic akkoma-external \
  --from-literal=secret-key-base=$(openssl rand -hex 64)
helm install akkoma ./charts/akkoma \
  --set externalSecret.enabled=true \
  --set externalSecret.name=akkoma-external
```

**Exit criteria:** Configuration fully Helm-managed, no hardcoded values.

---

### Iteration 4: Storage & Frontends (Day 7-8)

**Goal:** Persistent storage for uploads and frontends

**Scope:**
- [ ] PVC for uploads
- [ ] PVC for frontends
- [ ] install-frontends init container
- [ ] Idempotency check (skip if exists)
- [ ] External S3 support (template config for S3 uploader)

**Success criteria:**
- Uploads persist across pod restarts
- Frontends installed automatically
- Frontend installation skipped on subsequent starts
- S3 configuration templated (not tested yet)

**Testing:**
```bash
helm install akkoma ./charts/akkoma

# Upload a test file via UI
# Delete pod
kubectl delete pod -l app=akkoma

# Verify upload still accessible after pod restart
```

**Exit criteria:** All persistent data survives pod restarts.

---

### Iteration 5: External Access & TLS (Day 9-10)

**Goal:** Production ingress with TLS

**Scope:**
- [ ] Ingress resource (generic annotations)
- [ ] TLS configuration
- [ ] cert-manager integration example
- [ ] Documentation for different ingress controllers
- [ ] Health check probes (liveness, readiness)

**Success criteria:**
- Can access Akkoma via HTTPS
- TLS certificate obtained (manual or cert-manager)
- Health probes prevent traffic to unhealthy pods
- Federation works (can follow remote accounts)

**Testing:**
```bash
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=akkoma.example.com \
  --set ingress.tls.secretName=akkoma-tls

# Test federation
curl https://akkoma.example.com/.well-known/webfinger?resource=acct:admin@akkoma.example.com
```

**Exit criteria:** Production-ready deployment with external access.

---

### Post-Iteration: Documentation & Polish (Day 11-12)

**Scope:**
- [ ] README.md with installation instructions
- [ ] values.yaml documentation
- [ ] Ingress controller examples (nginx, Traefik, HAProxy, Caddy)
- [ ] Troubleshooting guide
- [ ] Upgrade guide
- [ ] CHANGELOG.md

**Success criteria:**
- New user can install from README alone
- Common issues documented with solutions
- Clear upgrade instructions

---

## Future Roadmap

### v0.2.0 (Shipped)

**Focus:** Production hardening and operational features

- [x] Restricted Pod Security Standards (read-only root filesystem)
- [x] Multi-architecture support (amd64 + arm64)
- [x] Object storage bundling (Garage, replacing SeaweedFS plan)
- [x] External S3 storage support (AWS, Backblaze B2, Wasabi, Cloudflare R2)
- [x] Backup/restore documentation
- [x] Prometheus metrics with ServiceMonitor
- [x] Automated testing in CI (helm lint, kubeconform, chart-testing, multi-version K8s)
- [ ] Grafana dashboard (deferred to v0.3.0)

### v0.3.0 (Next Release)

**Focus:** Advanced deployment patterns and observability

- [ ] Grafana dashboard (BEAM VM metrics, HTTP rates, federation activity)
- [ ] High-availability PostgreSQL (CloudNativePG operator support)
- [ ] Migration tooling (PVC to S3)
- [ ] Media pruning CronJob
- [x] NetworkPolicy templates (shipped in v0.1.0)
- [ ] PodDisruptionBudget (if HA supported)
- [ ] Frontend version override (customize pleroma-fe/admin-fe versions)

### Beyond v1.0

**Contingent on Akkoma upstream development:**

- [ ] Horizontal scaling (if Akkoma adds clustering support)
- [ ] Read replicas (if Akkoma supports read-only mode)
- [ ] Geographic distribution (multi-region federation)

---

## Appendix A: Akkoma Architecture Reference

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                  Akkoma Application                     │
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────┐  │
│  │   Phoenix     │  │   ActivityPub │  │  Pleroma  │  │
│  │   Web Server  │  │   Federation  │  │   Core    │  │
│  │   (Port 4000) │  │   Protocol    │  │   Logic   │  │
│  └───────────────┘  └───────────────┘  └───────────┘  │
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────┐  │
│  │   Upload      │  │   Media       │  │  Rich     │  │
│  │   Handler     │  │   Proxy       │  │  Media    │  │
│  └───────────────┘  └───────────────┘  └───────────┘  │
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────┐  │
│  │   User        │  │   Timeline    │  │  Search   │  │
│  │   Management  │  │   Generator   │  │  Engine   │  │
│  └───────────────┘  └───────────────┘  └───────────┘  │
└─────────────────────────────────────────────────────────┘
           │                    │                │
           ▼                    ▼                ▼
┌──────────────────┐  ┌──────────────┐  ┌──────────────┐
│   PostgreSQL     │  │   Uploads    │  │  Frontends   │
│   Database       │  │   Storage    │  │  (Static)    │
│   (Port 5432)    │  │   (PVC/S3)   │  │  (PVC)       │
└──────────────────┘  └──────────────┘  └──────────────┘
```

### Data Flow

```
User Request → Ingress → Service → Pod
                                    │
                                    ├─→ Phoenix (HTTP)
                                    │   │
                                    │   ├─→ ActivityPub (Federation)
                                    │   │   └─→ Remote Instances
                                    │   │
                                    │   ├─→ Media Handler
                                    │   │   └─→ Uploads Storage
                                    │   │
                                    │   └─→ Ecto (ORM)
                                    │       └─→ PostgreSQL
                                    │
                                    └─→ Background Jobs
                                        └─→ Task Queue
```

---

## Appendix B: Command Reference

### Helm Commands

```bash
# Install chart
helm install akkoma ./charts/akkoma -f values.yaml

# Upgrade chart
helm upgrade akkoma ./charts/akkoma -f values.yaml

# Rollback
helm rollback akkoma 1

# Uninstall
helm uninstall akkoma

# Template (dry-run)
helm template akkoma ./charts/akkoma -f values.yaml

# Lint
helm lint charts/akkoma

# Package
helm package charts/akkoma

# Debug
helm install akkoma ./charts/akkoma --dry-run --debug
```

### Kubectl Commands

```bash
# View pods
kubectl get pods -l app.kubernetes.io/name=akkoma

# View logs
kubectl logs -f deployment/akkoma

# View init container logs
kubectl logs deployment/akkoma -c wait-for-db
kubectl logs deployment/akkoma -c db-migrate
kubectl logs deployment/akkoma -c install-frontends

# Exec into pod
kubectl exec -it deployment/akkoma -- /bin/sh

# Port forward
kubectl port-forward svc/akkoma 4000:4000

# View events
kubectl get events --sort-by='.lastTimestamp'

# View secrets
kubectl get secret akkoma-secrets -o yaml

# View configmap
kubectl get configmap akkoma-config -o yaml
```

### Akkoma Management Commands

```bash
# Inside pod (via kubectl exec)

# Run migrations
./bin/pleroma_ctl migrate

# Create user
./bin/pleroma_ctl user new username email@example.com --admin

# Reset password
./bin/pleroma_ctl user reset_password username

# Install frontend
./bin/pleroma_ctl frontend install pleroma-fe --ref stable

# Remote console
./bin/pleroma_ctl remote_console

# Database operations
./bin/pleroma_ctl database remove_embedded_objects
./bin/pleroma_ctl database prune_objects

# Instance information
./bin/pleroma_ctl instance stats
```

---

## Appendix C: Troubleshooting Guide

### Common Issues

#### Pod CrashLoopBackOff

**Symptoms:**
```bash
kubectl get pods
NAME                      READY   STATUS             RESTARTS   AGE
akkoma-5d8f7c4b9c-x7k2l   0/1     CrashLoopBackOff   5          5m
```

**Diagnosis:**
```bash
kubectl logs deployment/akkoma
kubectl logs deployment/akkoma -c wait-for-db
kubectl logs deployment/akkoma -c db-migrate
kubectl describe pod -l app=akkoma
```

**Common Causes:**
1. Database connection failed
2. Configuration missing or invalid
3. Migrations failed
4. Insufficient resources

**Solutions:**
- Check init container logs
- Verify database credentials
- Ensure PostgreSQL is running: `kubectl get pods -l app=postgresql`
- Increase resource limits

#### Database Connection Issues

**Symptoms:**
- Connection timeout
- Authentication failed
- Database doesn't exist

**Diagnosis:**
```bash
# Check PostgreSQL logs
kubectl logs statefulset/akkoma-postgresql

# Test connectivity from pod
kubectl exec -it deployment/akkoma -- sh
pg_isready -h akkoma-postgresql -p 5432 -U akkoma
```

**Solutions:**
- Verify PostgreSQL is running
- Check service DNS resolution: `nslookup akkoma-postgresql`
- Confirm credentials match in Secret
- Check PostgreSQL initdb logs

#### Frontend Not Loading

**Symptoms:**
- Web UI shows blank page
- Console errors for missing files
- `/api/v1/instance` works but UI doesn't

**Diagnosis:**
```bash
# Check init container logs
kubectl logs deployment/akkoma -c install-frontends

# Check frontends volume
kubectl exec -it deployment/akkoma -- ls -la /opt/akkoma/instance/static/frontends
```

**Solutions:**
- Delete pod to re-run init container: `kubectl delete pod -l app=akkoma`
- Check PVC is bound: `kubectl get pvc akkoma-frontends`
- Verify volume permissions (fsGroup: 1000)
- Manually install: `kubectl exec -it deployment/akkoma -- ./bin/pleroma_ctl frontend install pleroma-fe --ref stable`

#### Configuration Not Applied

**Symptoms:**
- Changes to values.yaml not reflected
- Old configuration still active

**Diagnosis:**
```bash
# Check current config
kubectl exec -it deployment/akkoma -- cat /opt/akkoma/config/prod.secret.exs

# Compare with values
helm get values akkoma

# Check ConfigMap
kubectl get configmap akkoma-config -o yaml
```

**Solutions:**
- Verify `helm upgrade` completed: `helm ls`
- Restart pods: `kubectl rollout restart deployment/akkoma`
- Check for typos in values.yaml
- Verify ConfigMap updated: `kubectl get configmap akkoma-config -o yaml`

#### Secrets Regenerated on Upgrade

**Symptoms:**
- All users logged out after upgrade
- API tokens invalid
- "Invalid credentials" errors

**Cause:** Secrets were regenerated (lookup function didn't find existing Secret)

**Solutions:**
- Extract secrets from previous deployment: `helm get values akkoma-old > old-values.yaml`
- Reinstall with old secrets:
  ```bash
  helm upgrade akkoma ./charts/akkoma \
    --set akkoma.secretKeyBase=<old-value> \
    --set akkoma.signingSalt=<old-value>
  ```
- Use external secrets to prevent regeneration

---

## Appendix D: References

### Akkoma Documentation

- [Akkoma Docs](https://docs.akkoma.dev/)
- [Alpine Installation](https://docs.akkoma.dev/stable/installation/alpine_linux_en/)
- [Debian Installation](https://docs.akkoma.dev/stable/installation/debian_based_en/)
- [Docker Installation](https://docs.akkoma.dev/stable/installation/docker_en/)
- [OTP Releases](https://docs.akkoma.dev/stable/installation/otp_en/)
- [Configuration Reference](https://docs.akkoma.dev/stable/configuration/cheatsheet/)

### Helm Best Practices

- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Chart Template Guide](https://helm.sh/docs/chart_template_guide/)
- [Values Files](https://helm.sh/docs/chart_template_guide/values_files/)

### Kubernetes Resources

- [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

### Related Projects

- [Mastodon Helm Chart](https://github.com/mastodon/chart)
- [PostgreSQL Official Image](https://hub.docker.com/_/postgres)

---

**End of Design Document**

*This document is a living document and will be updated as implementation progresses and requirements evolve.*
