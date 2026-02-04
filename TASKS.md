# Akkoma Helm Chart - Implementation Tasks

**Created:** 2026-02-04
**Status:** Ready to Start
**Approach:** Iterative vertical slices using Replicated CMX clusters

## Prerequisites

### Local Environment Setup

- [ ] Helm 3.x installed
- [ ] kubectl installed and configured
- [ ] Docker installed (for building images with buildx)
- [ ] Replicated CLI configured
- [ ] Git repository initialized
- [ ] GitHub repository configured (for CI/CD)
- [ ] yamllint installed (for local testing)
- [ ] kubeconform installed (optional, for manifest validation)

### Replicated CMX Cluster

**Documentation:** https://docs.replicated.com/vendor/testing-how-to

```bash
# Create a CMX cluster for testing
replicated cluster create --distribution k3s --version 1.28

# Get kubeconfig
replicated cluster kubeconfig <cluster-id> > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Verify cluster access
kubectl get nodes

# When done testing
replicated cluster rm <cluster-id>
```

**CMX Benefits for this project:**
- On-demand Kubernetes clusters
- Multiple K8s distributions (k3s, kind, EKS, GKE, AKS)
- Quick provisioning (~2-5 minutes)
- Easy cleanup
- Matches production-like environments

---

## Iteration 0: Container Image Build

**Goal:** Build and test Akkoma OTP release container image

**Estimated time:** 1 day

### Tasks

#### 0.1: Create Multi-Stage Dockerfile

**Status:** Pending

**File:** `Dockerfile`

**Actions:**
- [ ] Create builder stage with elixir:1.14-alpine
- [ ] Install build dependencies (git, build-base, cmake, postgresql-client)
- [ ] Clone Akkoma from git (default: v3.13.2)
- [ ] Build OTP release with `mix release`
- [ ] Create runtime stage with alpine:3.19
- [ ] Install runtime dependencies (ncurses, postgresql-client, imagemagick, ffmpeg, exiftool)
- [ ] Create akkoma user/group (UID/GID 1000)
- [ ] Copy OTP release from builder
- [ ] Set proper ownership and permissions
- [ ] **Remove Dockerfile HEALTHCHECK** (Kubernetes will manage this)

**Dockerfile snippet:**
```dockerfile
# Stage 1: Build OTP release
FROM elixir:1.14-alpine AS builder

RUN apk add --no-cache git build-base cmake postgresql-client

ARG AKKOMA_VERSION=v3.13.2
WORKDIR /build

RUN git clone --branch ${AKKOMA_VERSION} \
    https://akkoma.dev/AkkomaGang/akkoma.git . && \
    mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
RUN mix deps.get --only prod && \
    mix do compile, release

# Stage 2: Runtime
FROM alpine:3.19

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

RUN addgroup -g 1000 akkoma && \
    adduser -D -u 1000 -G akkoma akkoma

COPY --from=builder --chown=akkoma:akkoma \
    /build/_build/prod/rel/pleroma /opt/akkoma

WORKDIR /opt/akkoma
USER akkoma
EXPOSE 4000

# Note: No HEALTHCHECK - Kubernetes manages this
CMD ["./bin/pleroma", "start"]
```

**Success criteria:**
- Image builds successfully
- Image size ~200MB
- Build time ~10-15 minutes
- Can run container locally

---

#### 0.2: Build and Test Image Locally

**Status:** Pending

**Actions:**
```bash
# Build image
docker build -t akkoma:dev .

# Check image size
docker images akkoma:dev

# Test run locally
docker run --rm -it \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e SIGNING_SALT=$(openssl rand -hex 8) \
  -e RELEASE_COOKIE=$(openssl rand -hex 64) \
  akkoma:dev ./bin/pleroma_ctl --help

# Verify user/permissions
docker run --rm akkoma:dev id
# Expected: uid=1000(akkoma) gid=1000(akkoma) groups=1000(akkoma)
```

**Success criteria:**
- Container starts successfully
- Running as UID 1000
- pleroma_ctl commands work
- Image passes basic smoke tests

---

#### 0.3: Push Image to Registry

**Status:** Pending

**Actions:**
```bash
# Tag for registry
docker tag akkoma:dev ghcr.io/adamancini/akkoma:v3.13.2
docker tag akkoma:dev ghcr.io/adamancini/akkoma:latest

# Push to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u adamancini --password-stdin
docker push ghcr.io/adamancini/akkoma:v3.13.2
docker push ghcr.io/adamancini/akkoma:latest
```

**Success criteria:**
- Image pushed to GHCR successfully
- Image is publicly accessible (or private with proper auth)
- Tags are correct

**Exit Iteration 0:**
- [ ] Container image built and tested
- [ ] Image pushed to registry
- [ ] Ready for Helm chart development

---

## Iteration 1: End-to-End Minimum

**Goal:** Single pod running Akkoma with in-cluster PostgreSQL

**Estimated time:** 2 days

### Tasks

#### 1.1: Project Structure Setup

**Status:** Pending

**Actions:**
```bash
# Create chart structure
mkdir -p charts/akkoma/templates
touch charts/akkoma/Chart.yaml
touch charts/akkoma/values.yaml
touch charts/akkoma/templates/_helpers.tpl
```

**Files to create:**
- [ ] `Chart.yaml` - Chart metadata
- [ ] `values.yaml` - Replace boilerplate with design document structure
- [ ] `templates/_helpers.tpl` - Common template helpers
- [ ] `.helmignore` - Exclude secrets and test files

**Chart.yaml content:**
```yaml
apiVersion: v2
name: akkoma
description: A Helm chart for deploying Akkoma federated social networking server
type: application
version: 0.1.0
appVersion: "v3.13.2"
keywords:
  - akkoma
  - fediverse
  - activitypub
  - social-networking
home: https://akkoma.dev
sources:
  - https://github.com/adamancini/akkoma-helm
maintainers:
  - name: adamancini
    email: your-email@example.com
```

**.helmignore content:**
```
# Secrets
secrets*.yaml
*-secrets.yaml
values.production.yaml

# Development
.git/
.gitignore
*.swp
*.bak
*~

# CI/CD
.github/
.gitlab-ci.yml
.travis.yml

# Documentation
DESIGN.md
TASKS.md
README.md
docs/
```

**Success criteria:**
- Chart structure exists
- `helm lint charts/akkoma` passes
- `.helmignore` excludes sensitive files

---

#### 1.2: Basic Deployment Template

**Status:** Pending

**File:** `templates/deployment.yaml`

**Actions:**
- [ ] Create Deployment resource
- [ ] Single replica
- [ ] Recreate strategy
- [ ] No init containers yet
- [ ] Hardcoded image (placeholder)
- [ ] Port 4000 exposed
- [ ] Basic probes (commented out for now)

**Template snippet:**
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
      app: akkoma
  template:
    metadata:
      labels:
        app: akkoma
      annotations:
        # Force pod restart on config/secret changes
        checksum/config: {{ include (print $.Template.BasePath "/configmap-akkoma.yaml") . | sha256sum }}
        checksum/secret: {{ include (print $.Template.BasePath "/secret-akkoma.yaml") . | sha256sum }}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: akkoma
        image: {{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          readOnlyRootFilesystem: false  # TODO: v0.2.0
        ports:
        - name: http
          containerPort: 4000
```

**Success criteria:**
- Template renders with `helm template`
- No errors from `helm lint`
- Security context properly configured
- Checksum annotations present

---

#### 1.3: PostgreSQL StatefulSet

**Status:** Pending

**File:** `templates/postgresql-statefulset.yaml`

**Actions:**
- [ ] Create StatefulSet resource
- [ ] Use `postgres:15-alpine` image
- [ ] Single replica
- [ ] volumeClaimTemplate for data
- [ ] Hardcoded credentials for now
- [ ] PGDATA configuration
- [ ] Add resource requests/limits

**StatefulSet snippet:**
```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999  # postgres user in official image
        runAsGroup: 999
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: postgresql
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              memory: 1Gi
```

**Success criteria:**
- PostgreSQL pod starts
- Can connect with `psql` from test pod
- Resource limits configured

---

#### 1.4: Services

**Status:** Pending

**Files:**
- `templates/service-akkoma.yaml`
- `templates/service-postgresql.yaml`

**Actions:**
- [ ] Create ClusterIP service for Akkoma (port 4000)
- [ ] Create ClusterIP service for PostgreSQL (port 5432)

**Success criteria:**
- Services created
- DNS resolution works: `nslookup akkoma`, `nslookup postgresql`

---

#### 1.5: Basic ConfigMap

**Status:** Pending

**File:** `templates/configmap-akkoma.yaml`

**Actions:**
- [ ] Create ConfigMap with minimal `prod.secret.exs`
- [ ] Hardcoded domain, email
- [ ] Hardcoded database connection (localhost for now)
- [ ] Hardcoded secrets (will fix in Iteration 3)

**Success criteria:**
- ConfigMap created
- Can read config from pod

---

#### 1.6: Basic Secret

**Status:** Pending

**File:** `templates/secret-akkoma.yaml`

**Actions:**
- [ ] Create Secret with hardcoded values
- [ ] secret-key-base (random hex)
- [ ] signing-salt (random hex)
- [ ] postgres-password (hardcoded)

**Success criteria:**
- Secret created
- Can read secrets from pod (base64 encoded)

---

#### 1.7: Build Akkoma Image (Placeholder)

**Status:** Pending

**File:** `Dockerfile`

**Actions:**
- [ ] Create multi-stage Dockerfile
- [ ] Stage 1: Build OTP release from source
- [ ] Stage 2: Runtime image with dependencies
- [ ] Use Akkoma v3.13.2 as default
- [ ] Test local build: `docker build -t akkoma:dev .`

**Success criteria:**
- Image builds successfully
- Image size ~200MB
- Can run container locally

---

#### 1.8: CMX Cluster Deploy Test

**Status:** Pending

**Actions:**
```bash
# Create CMX cluster
replicated cluster create --distribution k3s --version 1.28 --ttl 24h

# Get kubeconfig
replicated cluster kubeconfig <cluster-id> > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Load image to cluster (if not using registry)
# Note: May need to push to a registry instead for CMX

# Install chart
helm install akkoma ./charts/akkoma

# Check status
kubectl get pods -w
kubectl logs deployment/akkoma
kubectl port-forward svc/akkoma 4000:4000

# Test API endpoint
curl http://localhost:4000/api/v1/instance
```

**Success criteria:**
- Chart installs without errors
- Pods reach Running state
- Can port-forward and access Akkoma
- Database connection fails (expected - no init containers yet)

**Exit Iteration 1:**
- [ ] Chart deploys successfully
- [ ] Pods start (may crash due to DB not ready)
- [ ] Manual verification possible
- [ ] Clean up CMX cluster: `replicated cluster rm <cluster-id>`

---

## Iteration 2: Database Initialization

**Goal:** Automated database setup and migrations

**Estimated time:** 2 days

### Tasks

#### 2.1: PostgreSQL Initialization ConfigMap

**Status:** Pending

**File:** `templates/configmap-postgresql-init.yaml`

**Actions:**
- [ ] Create ConfigMap with `01-init.sql`
- [ ] SQL to create extensions (citext, pg_trgm, uuid-ossp)
- [ ] Mount to `/docker-entrypoint-initdb.d`

**SQL snippet:**
```sql
\c akkoma;

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

GRANT ALL PRIVILEGES ON DATABASE akkoma TO akkoma;
```

**Success criteria:**
- ConfigMap created
- Extensions created on PostgreSQL first start

---

#### 2.2: wait-for-db Init Container

**Status:** Pending

**File:** `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add init container to Deployment
- [ ] Use `postgres:15-alpine` image
- [ ] Loop with `pg_isready` until database ready
- [ ] Read DB_HOST from values/helpers

**Init container snippet:**
```yaml
initContainers:
- name: wait-for-db
  image: postgres:15-alpine
  command:
  - sh
  - -c
  - |
    until pg_isready -h $DB_HOST -p 5432 -U akkoma; do
      echo "Database not ready..."
      sleep 2
    done
  env:
  - name: DB_HOST
    value: akkoma-postgresql
```

**Success criteria:**
- Init container waits for PostgreSQL
- Akkoma container starts only after DB ready

---

#### 2.3: db-migrate Init Container

**Status:** Pending

**File:** `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add second init container
- [ ] Use same Akkoma image
- [ ] Run `./bin/pleroma_ctl migrate`
- [ ] Mount config volume
- [ ] Pass DB credentials via env vars

**Success criteria:**
- Migrations run on first install
- Migrations run on upgrades
- Idempotent (safe to run multiple times)

---

#### 2.3a: Add Startup Probe to Deployment

**Status:** Pending

**File:** `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add startupProbe before livenessProbe
- [ ] Allow 150s for initial startup and migrations
- [ ] Prevents pod kill during slow first boot

**Probe configuration:**
```yaml
containers:
  - name: akkoma
    startupProbe:
      httpGet:
        path: /api/v1/instance
        port: http
      initialDelaySeconds: 10
      periodSeconds: 5
      timeoutSeconds: 5
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
```

**Success criteria:**
- Startup probe configured
- Pod not killed during slow first boot
- Migrations complete successfully even if taking 60+ seconds

---

#### 2.4: Update ConfigMap for DB Connection

**Status:** Pending

**File:** `templates/configmap-akkoma.yaml` (update)

**Actions:**
- [ ] Update `prod.secret.exs` to use env vars for DB connection
- [ ] `System.get_env("DB_HOST")`
- [ ] `System.get_env("DB_USER")`
- [ ] `System.get_env("DB_PASSWORD")`

**Success criteria:**
- Config reads from environment
- No hardcoded DB credentials in ConfigMap

---

#### 2.5: Test with CMX Cluster

**Status:** Pending

**Actions:**
```bash
# Create fresh CMX cluster
replicated cluster create --distribution k3s --version 1.28

# Install chart
helm install akkoma ./charts/akkoma

# Watch init containers
kubectl get pods -w
kubectl logs deployment/akkoma -c wait-for-db
kubectl logs deployment/akkoma -c db-migrate

# Create test user
kubectl exec -it deployment/akkoma -- ./bin/pleroma_ctl user new admin admin@example.com --admin

# Test upgrade (change image tag)
helm upgrade akkoma ./charts/akkoma --set image.tag=dev-v2

# Verify user still exists
kubectl exec -it deployment/akkoma -- ./bin/pleroma_ctl user list
```

**Success criteria:**
- Database initializes automatically
- Migrations run successfully
- User creation works
- Upgrades preserve data
- Init containers complete successfully

**Exit Iteration 2:**
- [ ] Zero manual database setup required
- [ ] Migrations work on install and upgrade
- [ ] Data persists across pod restarts
- [ ] Clean up CMX cluster

---

## Iteration 3: Configuration & Secrets

**Goal:** Helm-templated config and secret generation

**Estimated time:** 2 days

### Tasks

#### 3.1: Helm Template Helpers

**Status:** Pending

**File:** `templates/_helpers.tpl`

**Actions:**
- [ ] `akkoma.fullname` helper
- [ ] `akkoma.name` helper
- [ ] `akkoma.chart` helper
- [ ] `akkoma.labels` helper
- [ ] `akkoma.selectorLabels` helper
- [ ] `akkoma.secretName` helper (for external secrets support)
- [ ] `akkoma.postgresql.host` helper
- [ ] `akkoma.postgresql.secretName` helper

**Success criteria:**
- Helpers used throughout templates
- DRY principle followed

---

#### 3.2: Values Structure (Progressive Disclosure)

**Status:** Pending

**File:** `values.yaml`

**Actions:**
- [ ] Basic configuration section (domain, adminEmail)
- [ ] Advanced configuration section (all optional)
- [ ] Comments explaining each section
- [ ] Sensible defaults
- [ ] External secrets support structure

**Structure:**
```yaml
# BASIC CONFIGURATION
akkoma:
  domain: "akkoma.example.com"      # REQUIRED
  adminEmail: "admin@example.com"   # REQUIRED
  instanceName: ""                   # Defaults to domain

ingress:
  enabled: true
  className: "nginx"
  annotations: {}
  tls:
    enabled: true
    secretName: "akkoma-tls"

# ADVANCED CONFIGURATION
externalSecret:
  enabled: false
  name: ""
  keys:
    secretKeyBase: "secret-key-base"
    signingSalt: "signing-salt"
    releaseCookie: "release-cookie"

postgresql:
  storageSize: 10Gi
  storageClass: ""
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      memory: 1Gi

storage:
  uploads:
    size: 50Gi
    storageClass: ""
  frontends:
    size: 5Gi
    storageClass: ""

instance:
  characterLimit: 5000
  registrationsOpen: false
  uploadLimit: 16000000
  description: ""

# Network security (enabled by default)
networkPolicy:
  enabled: true

# NO CPU LIMITS - Allow BEAM bursting
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    # No CPU limit
    memory: 2Gi

# Security context
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: false  # TODO: v0.2.0

image:
  repository: ghcr.io/adamancini/akkoma
  tag: ""  # Defaults to Chart.appVersion
  pullPolicy: IfNotPresent

# REMOVED - Misleading for single-instance
# autoscaling:
#   enabled: false
```

**Success criteria:**
- Clear separation of basic/advanced
- All values documented
- Defaults work out of box

---

#### 3.3: Secret Generation with Helm Lookup (Separated)

**Status:** Pending

**Files:**
- `templates/secret-akkoma.yaml` (application secrets)
- `templates/secret-postgresql.yaml` (database secrets)

**Actions:**
- [ ] Create separate Secret for application (secret-key-base, signing-salt, release-cookie)
- [ ] Create separate Secret for PostgreSQL (postgres-password)
- [ ] Use `lookup` function for both to preserve on upgrade
- [ ] Follow least privilege principle

**Application Secret (templates/secret-akkoma.yaml):**
```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace (printf "%s-secrets" (include "akkoma.fullname" .)) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "akkoma.fullname" . }}-secrets
type: Opaque
data:
  {{- if $existing }}
  secret-key-base: {{ $existing.data.secret-key-base }}
  signing-salt: {{ $existing.data.signing-salt }}
  release-cookie: {{ $existing.data.release-cookie }}
  {{- else }}
  secret-key-base: {{ randAlphaNum 64 | b64enc | quote }}
  signing-salt: {{ randAlphaNum 8 | b64enc | quote }}
  release-cookie: {{ randAlphaNum 64 | b64enc | quote }}
  {{- end }}
```

**PostgreSQL Secret (templates/secret-postgresql.yaml):**
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

**Success criteria:**
- Application and database secrets separated
- Secrets generated on first install
- Secrets preserved on upgrade
- Akkoma pods only mount application secrets
- PostgreSQL pods only mount database secrets

---

#### 3.4: External Secrets Support

**Status:** Pending

**Files:**
- `templates/_helpers.tpl` (update)
- `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add `akkoma.secretName` helper with conditional logic
- [ ] If `externalSecret.enabled`, return external secret name
- [ ] Otherwise, return generated secret name
- [ ] Update all secret references in templates
- [ ] Update environment variable references

**Helper snippets:**
```yaml
{{- define "akkoma.secretName" -}}
{{- if .Values.externalSecret.enabled -}}
{{ .Values.externalSecret.name }}
{{- else -}}
{{ include "akkoma.fullname" . }}-secrets
{{- end -}}
{{- end -}}

{{- define "akkoma.postgresql.secretName" -}}
{{- if .Values.postgresql.external.enabled -}}
{{ .Values.postgresql.external.passwordSecret }}
{{- else -}}
{{ include "akkoma.fullname" . }}-postgresql
{{- end -}}
{{- end -}}

{{- define "akkoma.validateRequired" -}}
{{- if not .Values.akkoma.domain }}
{{- fail "akkoma.domain is required" }}
{{- end }}
{{- if not .Values.akkoma.adminEmail }}
{{- fail "akkoma.adminEmail is required" }}
{{- end }}
{{- end -}}
```

**Success criteria:**
- Can use generated secrets (default)
- Can use external secrets (when enabled)
- Both modes work correctly
- Required values validated at install time

---

#### 3.5: Helm-Templated Elixir Config

**Status:** Pending

**File:** `templates/configmap-akkoma.yaml`

**Actions:**
- [ ] Template `prod.secret.exs` with values from values.yaml
- [ ] Use `System.get_env()` for all secrets
- [ ] Template domain, adminEmail, instance settings
- [ ] Template database connection
- [ ] Template upload configuration
- [ ] Add media proxy config
- [ ] Add logging config

**Config snippet:**
```elixir
import Config

config :pleroma, Pleroma.Web.Endpoint,
  url: [host: "{{ .Values.akkoma.domain }}", scheme: "https", port: 443],
  http: [ip: {0, 0, 0, 0}, port: 4000],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  signing_salt: System.get_env("SIGNING_SALT")

config :pleroma, :instance,
  name: "{{ .Values.akkoma.domain }}",
  email: "{{ .Values.akkoma.adminEmail }}",
  limit: {{ .Values.instance.characterLimit }},
  registrations_open: {{ .Values.instance.registrationsOpen }}
```

**Success criteria:**
- Config fully templated
- No hardcoded values
- All secrets come from environment

---

#### 3.6: Test with CMX Cluster

**Status:** Pending

**Actions:**
```bash
# Create CMX cluster
replicated cluster create --distribution k3s --version 1.28

# Test 1: Generated secrets (default)
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=test1.example.com \
  --set akkoma.adminEmail=admin@test1.example.com

# Verify secrets generated
kubectl get secret akkoma-secrets -o yaml

# Test upgrade preserves secrets
helm upgrade akkoma ./charts/akkoma \
  --set akkoma.domain=test1.example.com \
  --set akkoma.adminEmail=updated@test1.example.com

# Verify secrets unchanged
kubectl get secret akkoma-secrets -o yaml

# Uninstall
helm uninstall akkoma

# Test 2: External secrets
kubectl create secret generic my-external-secrets \
  --from-literal=secret-key-base=$(openssl rand -hex 64) \
  --from-literal=signing-salt=$(openssl rand -hex 8) \
  --from-literal=release-cookie=$(openssl rand -hex 64) \
  --from-literal=postgres-password=mypassword

helm install akkoma ./charts/akkoma \
  --set externalSecret.enabled=true \
  --set externalSecret.name=my-external-secrets \
  --set akkoma.domain=test2.example.com

# Verify using external secret
kubectl describe deployment akkoma | grep -A 10 "Environment"
```

**Success criteria:**
- Generated secrets work
- Secrets persist on upgrade
- External secrets work
- Configuration fully templated

**Exit Iteration 3:**
- [ ] Configuration managed by Helm
- [ ] Secrets handled properly (generated or external)
- [ ] No hardcoded sensitive values
- [ ] Clean up CMX cluster

---

## Iteration 4: Storage & Frontends

**Goal:** Persistent storage for uploads and frontends

**Estimated time:** 2 days

### Tasks

#### 4.1: Uploads PVC

**Status:** Pending

**File:** `templates/pvc-uploads.yaml`

**Actions:**
- [ ] Create PersistentVolumeClaim
- [ ] Size from values.yaml (default 50Gi)
- [ ] Optional storageClass
- [ ] ReadWriteOnce access mode

**Success criteria:**
- PVC created
- PVC bound
- Akkoma can write to volume

---

#### 4.2: Frontends PVC

**Status:** Pending

**File:** `templates/pvc-frontends.yaml`

**Actions:**
- [ ] Create PersistentVolumeClaim
- [ ] Size from values.yaml (default 5Gi)
- [ ] Optional storageClass
- [ ] ReadWriteOnce access mode

**Success criteria:**
- PVC created
- PVC bound
- Init container can write frontends

---

#### 4.3: Mount Volumes in Deployment

**Status:** Pending

**File:** `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add volume definitions
- [ ] Add volumeMounts to main container
- [ ] Mount uploads to `/opt/akkoma/uploads`
- [ ] Mount frontends to `/opt/akkoma/instance/static/frontends`

**Success criteria:**
- Volumes mounted correctly
- Permissions correct (fsGroup: 1000)

---

#### 4.4: install-frontends Init Container

**Status:** Pending

**File:** `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add third init container
- [ ] Check if frontends already installed
- [ ] If not, install pleroma-fe
- [ ] If not, install admin-fe
- [ ] Mount frontends volume
- [ ] Mount config volume

**Init container snippet:**
```yaml
- name: install-frontends
  image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
  command:
  - sh
  - -c
  - |
    if [ -d "/frontends/pleroma-fe" ] && [ -d "/frontends/admin-fe" ]; then
      echo "Frontends already installed"
      exit 0
    fi

    ./bin/pleroma_ctl frontend install pleroma-fe --ref stable
    ./bin/pleroma_ctl frontend install admin-fe --ref stable
  volumeMounts:
  - name: frontends
    mountPath: /opt/akkoma/instance/static/frontends
  - name: config
    mountPath: /opt/akkoma/config
```

**Success criteria:**
- Frontends install on first start
- Installation skipped on subsequent starts
- Frontends persist across pod restarts

---

#### 4.5: S3 Configuration Template (Not Tested Yet)

**Status:** Pending

**File:** `templates/configmap-akkoma.yaml` (update)

**Actions:**
- [ ] Add conditional for S3 uploader
- [ ] If `storage.s3.enabled`, use S3 uploader
- [ ] Otherwise, use Local uploader
- [ ] Template S3 credentials as env vars

**Config snippet:**
```elixir
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
```

**Success criteria:**
- Configuration templated
- Local uploader works (tested)
- S3 uploader templated (not tested yet, deferred)

---

#### 4.6: Test with CMX Cluster

**Status:** Pending

**Actions:**
```bash
# Create CMX cluster
replicated cluster create --distribution k3s --version 1.28

# Install chart
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=storage-test.example.com

# Wait for pods
kubectl wait --for=condition=Ready pod -l app=akkoma --timeout=300s

# Check PVCs
kubectl get pvc

# Port forward and access UI
kubectl port-forward svc/akkoma 4000:4000

# Create admin user
kubectl exec -it deployment/akkoma -- \
  ./bin/pleroma_ctl user new admin admin@storage-test.example.com --admin

# Access web UI (should load with frontends)
open http://localhost:4000

# Upload test file via UI

# Delete pod
kubectl delete pod -l app=akkoma

# Wait for new pod
kubectl wait --for=condition=Ready pod -l app=akkoma --timeout=300s

# Verify:
# - Frontends still work (not reinstalled)
# - Uploaded file still accessible
```

**Success criteria:**
- Uploads persist across pod restarts
- Frontends persist and don't reinstall
- Web UI loads correctly
- File uploads work

**Exit Iteration 4:**
- [ ] All persistent data survives pod restarts
- [ ] Frontends install automatically
- [ ] Uploads work and persist
- [ ] Clean up CMX cluster

---

## Iteration 5: External Access & TLS

**Goal:** Production ingress with TLS

**Estimated time:** 2 days

### Tasks

#### 5.1: NetworkPolicy Resources

**Status:** Pending

**Files:**
- `templates/networkpolicy-akkoma.yaml`
- `templates/networkpolicy-postgresql.yaml`

**Actions:**
- [ ] Create NetworkPolicy for Akkoma (ingress from ingress controller, egress to PostgreSQL/DNS/federation)
- [ ] Create NetworkPolicy for PostgreSQL (ingress from Akkoma only)
- [ ] Conditional with `.Values.networkPolicy.enabled`
- [ ] Document ingress controller namespace label requirements

**Akkoma NetworkPolicy snippet:**
```yaml
{{- if .Values.networkPolicy.enabled }}
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
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 4000
  egress:
    - to:  # DNS
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    - to:  # PostgreSQL
        - podSelector:
            matchLabels:
              app: postgresql
              release: {{ .Release.Name }}
      ports:
        - protocol: TCP
          port: 5432
    - to:  # Federation (HTTPS)
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
{{- end }}
```

**Success criteria:**
- NetworkPolicies created when enabled
- Akkoma can connect to PostgreSQL
- Akkoma can federate (HTTPS egress works)
- PostgreSQL isolated from unauthorized access
- Can be disabled with `networkPolicy.enabled: false`

---

#### 5.2: Ingress Resource

**Status:** Pending

**File:** `templates/ingress.yaml`

**Actions:**
- [ ] Create Ingress resource
- [ ] Conditional (if `.Values.ingress.enabled`)
- [ ] IngressClassName from values
- [ ] Host from `akkoma.domain`
- [ ] Path `/` → akkoma service
- [ ] TLS configuration
- [ ] Generic annotations only

**Template snippet:**
```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "akkoma.fullname" . }}
  annotations:
    {{- if .Values.ingress.tls.enabled }}
    cert-manager.io/cluster-issuer: {{ .Values.ingress.tls.issuer | default "letsencrypt-prod" }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  {{- if .Values.ingress.tls.enabled }}
  tls:
  - hosts:
    - {{ .Values.akkoma.domain }}
    secretName: {{ .Values.ingress.tls.secretName }}
  {{- end }}
  rules:
  - host: {{ .Values.akkoma.domain }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ include "akkoma.fullname" . }}
            port:
              number: 4000
{{- end }}
```

**Success criteria:**
- Ingress creates successfully
- Routes traffic to Akkoma
- TLS configuration present

---

#### 5.2: Health Probes

**Status:** Pending

**File:** `templates/deployment.yaml` (update)

**Actions:**
- [ ] Add livenessProbe
- [ ] Add readinessProbe
- [ ] Both use `/api/v1/instance` endpoint
- [ ] Configure delays and timeouts
- [ ] Liveness: longer initial delay (30s)
- [ ] Readiness: shorter initial delay (10s)

**Probe snippet:**
```yaml
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
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

**Success criteria:**
- Probes configured
- Unhealthy pods removed from Service
- Pod restarts if unresponsive

---

#### 5.3: Test with CMX Cluster (Limited TLS Testing)

**Status:** Pending

**Actions:**
```bash
# Create CMX cluster
replicated cluster create --distribution k3s --version 1.28

# Install chart
helm install akkoma ./charts/akkoma \
  --set akkoma.domain=akkoma.cmx.replicated.com \
  --set ingress.enabled=true \
  --set ingress.className=nginx

# Note: Full TLS testing requires real domain + cert-manager
# For CMX, test Ingress creation and routing only

# Check Ingress
kubectl get ingress
kubectl describe ingress akkoma

# Port forward to test (bypass Ingress)
kubectl port-forward svc/akkoma 4000:4000

# Test health endpoints
curl http://localhost:4000/api/v1/instance

# Test federation endpoint (should return JSON)
curl http://localhost:4000/.well-known/webfinger?resource=acct:admin@akkoma.cmx.replicated.com

# Check probes
kubectl describe pod -l app=akkoma | grep -A 5 "Liveness"
kubectl describe pod -l app=akkoma | grep -A 5 "Readiness"
```

**Success criteria:**
- Ingress resource created
- Routes configured correctly
- Health probes functioning
- Federation endpoint responds

**TLS Testing Note:**
Full TLS/federation testing requires:
- Real domain name
- DNS configured
- cert-manager installed (or manual TLS secret)
- Deferred to real environment testing

**Exit Iteration 5:**
- [ ] Ingress configured
- [ ] Health probes working
- [ ] Ready for external access (pending TLS/DNS)
- [ ] Clean up CMX cluster

---

## Post-Iteration: Documentation & Polish

**Goal:** Production-ready documentation

**Estimated time:** 2 days

### Tasks

#### D.1: README.md

**Status:** Pending

**File:** `charts/akkoma/README.md`

**Actions:**
- [ ] Project overview
- [ ] Quick start guide
- [ ] Prerequisites
- [ ] Installation instructions
- [ ] Basic configuration examples
- [ ] ⚠️ Security warnings (secret management, production requirements)
- [ ] NetworkPolicy configuration
- [ ] Upgrade instructions
- [ ] Troubleshooting section
- [ ] Links to DESIGN.md

**Key sections to include:**
- Warning about auto-generated secrets (not for production)
- External secrets setup guide (Sealed Secrets, ESO)
- NetworkPolicy requirements (ingress controller labels)
- Database backup recommendations
- Migration to external PostgreSQL

**Success criteria:**
- New user can install from README alone
- Security warnings prominent and clear
- Common issues addressed
- Clear, concise documentation

---

#### D.2: values.yaml Documentation

**Status:** Pending

**File:** `values.yaml`

**Actions:**
- [ ] Add detailed comments for every value
- [ ] Explain basic vs advanced sections
- [ ] Provide examples for common configurations
- [ ] Document external secrets usage
- [ ] Document S3 configuration (even if not tested)

**Success criteria:**
- Every value documented
- Examples provided
- Clear guidance on what to configure

---

#### D.3: Ingress Controller Examples

**Status:** Pending

**File:** `docs/ingress-examples.md`

**Actions:**
- [ ] nginx-ingress example with caching
- [ ] Traefik example
- [ ] HAProxy example
- [ ] Caddy example
- [ ] Note that nginx-ingress is EOL
- [ ] Explain Akkoma's built-in media proxy

**Success criteria:**
- Multiple controller examples
- Caching configuration explained
- Users can choose their controller

---

#### D.4: Troubleshooting Guide

**Status:** Pending

**File:** `docs/troubleshooting.md`

**Actions:**
- [ ] Pod CrashLoopBackOff scenarios
- [ ] Database connection issues
- [ ] Frontend not loading
- [ ] Configuration not applied
- [ ] Secrets regenerated on upgrade
- [ ] Common kubectl commands

**Success criteria:**
- Common issues documented
- Solutions provided
- Diagnostic commands included

---

#### D.5: Upgrade Guide

**Status:** Pending

**File:** `docs/upgrading.md`

**Actions:**
- [ ] Document upgrade process
- [ ] Explain secret preservation
- [ ] Backup recommendations
- [ ] Breaking changes (future versions)
- [ ] Rollback procedure

**Success criteria:**
- Clear upgrade instructions
- Data safety addressed
- Rollback explained

---

#### D.6: CHANGELOG.md

**Status:** Pending

**File:** `CHANGELOG.md`

**Actions:**
- [ ] Document v0.1.0 initial release
- [ ] List all features
- [ ] List known limitations
- [ ] Link to DESIGN.md and TASKS.md

**Success criteria:**
- Complete feature list
- Clear versioning
- Known issues documented

---

#### D.7: NOTES.txt Template

**Status:** Pending

**File:** `templates/NOTES.txt`

**Actions:**
- [ ] Create post-install instructions
- [ ] Show how to access the instance
- [ ] Show how to create admin user
- [ ] Warn if using auto-generated secrets
- [ ] Warn if TLS not enabled
- [ ] Link to documentation

**NOTES.txt content:**
```
Thank you for installing {{ .Chart.Name }}!

Your Akkoma instance is being deployed.

1. Get the application URL:
{{- if .Values.ingress.enabled }}
  https://{{ .Values.akkoma.domain }}
{{- else }}
  kubectl port-forward svc/{{ include "akkoma.fullname" . }} 4000:4000
  http://localhost:4000
{{- end }}

2. Create an admin user:
  kubectl exec -it deployment/{{ include "akkoma.fullname" . }} -- \
    ./bin/pleroma_ctl user new admin {{ .Values.akkoma.adminEmail }} --admin

3. Check pod status:
  kubectl get pods -l app.kubernetes.io/name={{ include "akkoma.name" . }}

4. View logs:
  kubectl logs -f deployment/{{ include "akkoma.fullname" . }}

{{- if not .Values.externalSecret.enabled }}

⚠️  WARNING: Using auto-generated secrets (not suitable for production)
For production, enable external secrets:
  helm upgrade {{ .Release.Name }} . --set externalSecret.enabled=true

{{- end }}

{{- if not .Values.ingress.tls.enabled }}

⚠️  WARNING: TLS is not enabled
Your instance will not federate correctly without HTTPS.

{{- end }}

{{- if .Values.networkPolicy.enabled }}

✓ NetworkPolicies enabled - Zero-trust networking active
  Ensure your ingress controller namespace has the correct label.

{{- end }}

For more information, visit:
- Akkoma Docs: https://docs.akkoma.dev/
- Chart Repository: https://github.com/adamancini/akkoma-helm
```

**Success criteria:**
- Post-install instructions clear
- Warnings displayed appropriately
- User can immediately create admin account

---

#### D.8: Helm Test Templates

**Status:** Pending

**File:** `templates/tests/test-connection.yaml`

**Actions:**
- [ ] Create Helm test for connection validation
- [ ] Test `/api/v1/instance` endpoint
- [ ] Use `helm.sh/hook: test` annotation

**Test template:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "akkoma.fullname" . }}-test-connection"
  labels:
    {{- include "akkoma.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['--spider', '{{ include "akkoma.fullname" . }}:4000/api/v1/instance']
  restartPolicy: Never
```

**Run tests:**
```bash
helm test akkoma
```

**Success criteria:**
- Test pod created
- Connection to Akkoma service successful
- Test passes after deployment

---

#### D.9: CI/CD Workflow Documentation

**Status:** Pending

**File:** `docs/ci-cd.md`

**Actions:**
- [ ] Document GitHub Actions workflows
- [ ] Explain chart linting
- [ ] Explain security scanning
- [ ] Explain chart release process
- [ ] Dependabot configuration

**Success criteria:**
- CI/CD process documented
- Contributors understand automation
- Release process clear

---

## CMX Cluster Management Tips

### Quick Commands

```bash
# List clusters
replicated cluster ls

# Create cluster with specific TTL
replicated cluster create --distribution k3s --version 1.28 --ttl 48h

# Extend cluster TTL
replicated cluster update <cluster-id> --ttl 72h

# Get cluster info
replicated cluster inspect <cluster-id>

# Port forward through CMX (if needed)
replicated cluster port-forward <cluster-id> <local-port>:<remote-port>

# Delete cluster
replicated cluster rm <cluster-id>
```

### Best Practices

1. **Use descriptive names:**
   ```bash
   replicated cluster create --name akkoma-iter3-config --distribution k3s
   ```

2. **Set appropriate TTLs:**
   - Active development: `--ttl 24h`
   - Testing/demo: `--ttl 4h`
   - Long-running tests: `--ttl 48h`

3. **Clean up promptly:**
   - Delete clusters when done to save resources
   - Use `replicated cluster ls` to check for forgotten clusters

4. **Test different distributions:**
   - k3s (fast, lightweight)
   - kind (local-like)
   - EKS/GKE/AKS (production-like)

5. **Export kubeconfig:**
   ```bash
   export KUBECONFIG=~/.kube/cmx-akkoma.yaml
   replicated cluster kubeconfig <cluster-id> > $KUBECONFIG
   ```

---

## Testing Checklist

After each iteration, verify:

- [ ] `helm lint charts/akkoma` passes
- [ ] `helm template charts/akkoma` renders without errors
- [ ] Chart installs successfully
- [ ] All pods reach Running state
- [ ] Logs show no errors
- [ ] Iteration-specific success criteria met
- [ ] CMX cluster cleaned up

---

## Next Steps After v0.1.0

Once all iterations complete and documentation is done:

1. **Tag release:** `git tag v0.1.0`
2. **Package chart:** `helm package charts/akkoma`
3. **Test on real cluster** (with domain + TLS)
4. **Document v0.2.0 roadmap** in DESIGN.md
5. **Create issues** for v0.2.0 features

---

**End of Task Plan**

*Update task statuses as work progresses. Mark completed tasks and note any blockers.*
