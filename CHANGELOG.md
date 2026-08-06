# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.9] - 2026-08-06

### Fixed

- Resolved all 35 open Trivy/CodeQL security-scanning alerts (`charts/security/code-scanning`):
  - `postgresql-statefulset.yaml`'s container had no container-level `securityContext` at all. Added `allowPrivilegeEscalation: false`, `capabilities: {drop: [ALL]}`, and `readOnlyRootFilesystem: true` (with new `tmp`/`run-postgresql` emptyDir mounts for the paths Postgres needs writable), matching the pattern already used elsewhere in the chart. Verified locally against the real `postgres:15-alpine` image before committing.
  - Added resource requests/limits to the three `deployment.yaml` init containers (`wait-for-db`, `db-migrate`, `install-frontends`), which previously had none, via new `initContainerResources.*` values. `db-migrate` is sized close to the main container's own footprint (1Gi/2Gi memory), not a lightweight-script allocation — it boots the identical BEAM/OTP release just to run `pleroma_ctl migrate`, so under-sizing it risks OOMKill on release boot alone. Added a CPU limit to `postgresql.resources` (unlike the main `akkoma` container, there's no BEAM-scheduler reason to omit one for Postgres).
  - Suppressed genuine false positives via `.trivyignore`, each with a documented reason: `configmap-akkoma.yaml`'s "ConfigMap with secrets"/"sensitive content" findings (a mix of `System.get_env(...)` references — env var names, not values — and non-sensitive fields like the admin contact email and the `prod.secret.exs` filename matching on the word "secret"; none of it is real secret material), and "workloads in the default namespace" (a scan-harness artifact — CI's chart rendering doesn't set a namespace; real deployments never target `default`).
  - Added `trivy.yaml`/`trivy-data/ksv0125.yaml` declaring `ghcr.io` a trusted registry for the "restrict container images to trusted registries" check. Verified against Trivy's own Rego source that bare Docker Hub images (`postgres:15-alpine`, `alpine:3.23`) were never actually the trigger — the check exempts registry-unqualified image references entirely; the real hit was this chart's own `ghcr.io/adamancini/akkoma` image, since Trivy's default trusted list only covers Azure/ECR/GCR.
  - Also suppressed (with justification) the sole remaining `CPU not limited` finding on the main `akkoma` container, which deliberately has no CPU limit (see `values.yaml`'s `resources` comment) for BEAM scheduler bursting.

### Changed

- **Renumbered the container UID/GID from 1000/999 to 10001** for both the Akkoma app (Dockerfile's `akkoma` user) and the bundled PostgreSQL StatefulSet, resolving the "runs with UID/GID <= 10000" findings. Verified locally that `postgres:15-alpine` initializes and runs cleanly under an overridden UID.
  - **Upgrade note:** if you have an *existing* installation with PGDATA already on disk (owned by UID 999 under default 0700 permissions), a fresh UID 10001 won't be able to read those files. Override `postgresql.podSecurityContext` back to UID/GID 999, or migrate ownership of the PVC's data, before upgrading. New installations are unaffected.

## [0.4.8] - 2026-08-06

### Fixed

- 0.4.7's fix resolved the upstream Akkoma `stable` alias once per build and used that to tag the image, but still built the image itself against the literal `stable` alias — and `stable` is a moving pointer, not an immutable release: it can advance to a new unreleased commit under the same version number (`git describe` output like `3.19.0-N-g<sha>`) between separate CI runs, so the pushed tag was not guaranteed to match the image contents, and two builds of the same nominal version were not reproducible.
- `build-image.yml` no longer resolves anything from the network. It now reads the pinned `appVersion` directly out of `charts/akkoma/Chart.yaml` and passes that exact string as the `AKKOMA_VERSION` build-arg, which resolves to an immutable, version-specific path upstream (confirmed present for both current and historical releases, e.g. `v3.17.0`, `v3.19.0`). The same value is used as the image tag. Every build of a given commit now downloads the same bits, and bumping the Akkoma version is now a deliberate, visible change to `appVersion` rather than something that can silently drift on an ordinary `main` rebuild.
- No functional chart changes; `appVersion` remains `v3.19.0`.
- Stopped tagging the container image with the chart's own SemVer (`0.4.x`, `0.4`, `0`) at all, and stopped triggering image builds off `v<chart-semver>` git tags. The chart and the image now release independently: `chart-v<semver>` alone triggers the chart release, and the image builds/tags automatically off `appVersion` whenever `Dockerfile`/`Chart.yaml`/the workflow changes on `main`. `ghcr.io/adamancini/akkoma`'s tags now only ever represent the Akkoma version running in the container, eliminating any future risk of the two version numbers colliding in the same tag namespace.

## [0.4.7] - 2026-08-06

### Fixed

- `image.tag` defaults to `Chart.AppVersion`, but no build ever pushed a tag matching that version — only tags matching the chart's own release version (e.g. `0.4.6`) were built. A one-off manual push had filled the gap for `v3.17.0` but was amd64-only, so `helm install` with default values failed to pull on arm64 (e.g. Apple Silicon).
- `build-image.yml` now resolves the current `stable` version once per run and builds against that pinned version (rather than the floating `stable` alias) for both platforms, pushing an additional multi-arch tag matching it — so `image.tag`'s default always points at a real, multi-arch image, and the pushed tag can't drift from what the image actually contains.
- Bumped `appVersion` to `v3.19.0` to match the version now resolved from `stable`.

## [0.4.6] - 2026-06-30

### Changed

- Release to test CD pipeline; no functional chart changes.

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
