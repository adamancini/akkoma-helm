# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- No S3 upload support (local storage only, S3 templated but untested)
- No read-only root filesystem (planned for v0.2.0)
- Frontend versions pinned to "stable" (no version override)
- `helm template --dry-run` shows different secret values than actual install (expected Helm lookup behavior)
- Uninstall/reinstall requires deleting PostgreSQL PVC to avoid password mismatch

[0.1.0]: https://github.com/adamancini/akkoma-helm/releases/tag/v0.1.0
