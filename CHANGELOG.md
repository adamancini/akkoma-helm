# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.5] - 2026-06-21

### Changed

- Release to verify ArgoCD automated sync picks up new chart versions; no functional chart changes.

## [0.4.4] - 2026-06-21

### Added

- GitOps-safe secret management. Every generated secret now resolves with the precedence **explicit value > existing in-cluster value > random**, so values stay stable under `helm template`/ArgoCD where Helm's `lookup` is unavailable:
  - `postgresql.password` / `postgresql.existingSecret` / `postgresql.existingSecretPasswordKey` for the bundled PostgreSQL StatefulSet
  - `secrets.secretKeyBase` / `secrets.signingSalt` / `secrets.releaseCookie` for the Akkoma application secrets
  - `garage.adminToken` / `garage.rpcSecret` / `garage.existingSecret` for the Garage subchart

### Fixed

- Bundled PostgreSQL StatefulSet now references the password Secret via the `akkoma.postgresql.secretName`/`passwordKey` helpers, so `postgresql.existingSecret` and a custom password key wire through to Postgres itself.
- Random secrets are no longer regenerated on every render under GitOps tooling when an explicit value or existing Secret is provided.

## [0.4.3] - 2026-06-21

### Changed

- Release to exercise the CD pipeline (image build + chart publish); no functional chart changes.

## [0.4.0] - 2026-02-09

### Added

- Application-level hardening options based on [Akkoma hardening guide](https://docs.akkoma.dev/stable/configuration/hardening/)
- Secure cookie flag (`hardening.secureCookieFlag`) for HTTPS-only cookies with `__Host-` prefix, enabled by default
- Separate upload domain support (`hardening.mediaBaseUrl`) for content isolation from user-uploaded media
- HTTP security headers (`hardening.httpSecurity`) with Strict-Transport-Security, Referrer-Policy, XSS protection, frame denial, CSP, and MIME sniffing prevention, enabled by default

## [0.3.1] - 2026-02-07

### Fixed

- Fix login/upload crash caused by Helm rendering `upload_limit` as scientific notation (`1.6e+07`), which Elixir parsed as a float instead of an integer, crashing Plug.Parsers.MULTIPART on `POST /oauth/token`

## [0.3.0] - 2026-02-07

### Added

- Frontend version override: parameterized `frontends.pleromaFe.ref`, `frontends.adminFe.ref`, and custom build URL support via `frontends.*.url`
- Grafana dashboard: opt-in ConfigMap (`metrics.grafana.enabled`) with upstream Akkoma dashboard and sidecar discovery labels
- Media pruning CronJob: scheduled `pleroma_ctl database prune_objects` via `mediaPruning.enabled` with configurable schedule, keep-followed, keep-threads, keep-non-public, limit, prune-orphaned-activities, and vacuum options
- CloudNativePG support: operator-managed PostgreSQL via CNPG Cluster CR (`postgresql.cnpg.enabled`) as an alternative to the bundled StatefulSet, with configurable instances, storage, PostgreSQL parameters, and backup settings

### Changed

- Bumped chart version from 0.2.3 to 0.3.0
- Extended CI test matrix with dedicated values files for frontend override, Grafana dashboard, media pruning, and CNPG configurations

## [0.2.3] - 2026-02-07

### Changed

- Use bare semver (e.g. `v0.2.3`) as GitHub Release title instead of tag name

## [0.2.2] - 2026-02-07

### Changed

- Bump Alpine base image from 3.19 to 3.23 (Dockerfile, init containers, garage-setup Job)

## [0.2.1] - 2026-02-07

### Fixed

- Disable tzdata autoupdate to prevent crashes on read-only root filesystem
- Fix release workflow git config not applying to gh-pages clone
- Scope yamllint to non-template files (Helm templates are not valid YAML)
- Add `security-events: write` permission for Trivy SARIF upload in CI

## [0.2.0] - 2026-02-07

### Added

- Read-only root filesystem (`readOnlyRootFilesystem: true`) for all containers
- tmpfs volume at `/tmp` (64Mi, memory-backed) for BEAM VM scratch space
- `RELEASE_TMP` and `ERL_CRASH_DUMP` environment variables for Elixir release compatibility
- Prometheus metrics support (`metrics.enabled`) with built-in Akkoma metrics endpoint
- ServiceMonitor resource for Prometheus Operator (`metrics.serviceMonitor.enabled`)
- Prometheus pod annotations for annotation-based discovery
- External S3 storage support (`storage.type: s3`) for AWS, Backblaze B2, Wasabi, Cloudflare R2
- S3 credentials via Kubernetes Secret (generated or existing)
- Garage S3-compatible object storage subchart (`garage.enabled`)
- Automated Garage setup Job (layout assignment, key creation, bucket provisioning)
- RBAC resources for Garage setup Job (namespace-scoped Secret management)
- CI test value files for all configuration modes (default, external-db, external-secrets, s3, metrics, garage, full)
- Multi-version Kubernetes schema validation in CI (1.28-1.31)
- Multi-architecture container image support (amd64 + arm64)
- QEMU setup in build workflow for cross-platform builds

### Changed

- `readOnlyRootFilesystem` flipped from `false` to `true` in default values
- All init containers now have `readOnlyRootFilesystem: true`
- `wait-for-db` init container now has explicit `readOnlyRootFilesystem: true`
- `install-frontends` init container now mounts tmpfs at `/tmp` for downloads
- Dockerfile now uses `TARGETARCH` for automatic architecture selection
- Updated GitHub Actions to latest versions (Helm v3.16.0, chart-testing v2.7.0, kind v1.10.0, build-push-action v6, scan-action v4, gh-release v2)
- CI now validates all `charts/akkoma/ci/*.yaml` value files during lint
- Kubeconform version bumped to v0.6.7

### Fixed

- Removed hardcoded `AKKOMA_FLAVOUR=amd64-musl` from Dockerfile (now derived from `TARGETARCH`)

## [0.1.0] - 2026-02-06

### Added

- Akkoma Deployment with OTP release container image (v3.17.0)
- Bundled PostgreSQL 15 StatefulSet with persistent storage
- Automatic database initialization (citext, pg_trgm, uuid-ossp extensions)
- Automatic database migration via init container
- Automatic frontend installation (Pleroma-FE and Admin-FE)
- Persistent storage for uploads (50Gi default) and frontends (5Gi default)
- Helm lookup-based secret generation (preserved across upgrades)
- External secrets support (Sealed Secrets, ESO, Vault)
- Separate secrets by scope (application vs database, least privilege)
- Ingress resource with TLS and cert-manager annotation support
- NetworkPolicy for Akkoma (ingress controller, DNS, PostgreSQL, federation)
- NetworkPolicy for PostgreSQL (Akkoma-only ingress, DNS egress)
- External PostgreSQL support
- Security-hardened containers (non-root UID 1000, seccomp RuntimeDefault, dropped capabilities)
- Startup probe (150s), liveness probe, readiness probe
- Recreate deployment strategy (single-instance pattern)
- No CPU limits (allows BEAM scheduler bursting)
- ConfigMap-based Elixir configuration with environment variable injection
- Admin-FE database configuration management (configurable_from_database)
- Progressive disclosure values.yaml structure

### Known Limitations

- Single replica only (Akkoma does not support horizontal scaling)
- Frontend versions pinned to "stable" (no version override)
- `helm template --dry-run` shows different secret values than actual install (expected Helm lookup behavior)
- Uninstall/reinstall requires deleting PostgreSQL PVC to avoid password mismatch

[0.4.0]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.4.0
[0.3.1]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.3.1
[0.3.0]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.3.0
[0.2.3]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.2.3
[0.2.2]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.2.2
[0.2.1]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.2.1
[0.2.0]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.2.0
[0.1.0]: https://github.com/adamancini/akkoma-helm/releases/tag/chart-v0.1.0
