# Akkoma Helm Chart v0.3.0 Plan

## Context

v0.2.3 is released with production hardening (read-only root filesystem, multi-arch, S3/Garage, metrics). The v0.3.0 roadmap focuses on observability, operator-managed PostgreSQL, operational automation, and frontend flexibility. All new features are opt-in with backward-compatible defaults.

---

## Iteration 1: Frontend Version Override

**Goal:** Replace hardcoded `stable` ref with parameterized values. Support custom build URLs.

**Files to modify:**
- `charts/akkoma/values.yaml` -- add `frontends` section
- `charts/akkoma/templates/deployment.yaml` -- parameterize install-frontends init container
- `charts/akkoma/templates/configmap-akkoma.yaml` -- parameterize frontend config refs

**Files to create:**
- `charts/akkoma/ci/frontend-override-values.yaml`

**Changes:**

1. Add to values.yaml (in ADVANCED section, before `garage`):
   ```yaml
   frontends:
     pleromaFe:
       ref: "stable"
       url: ""  # Custom build URL override
     adminFe:
       ref: "stable"
       url: ""
   ```

2. In deployment.yaml `install-frontends` init container, replace hardcoded `stable` with template refs:
   - Directory check: `/frontends/pleroma-fe/{{ ref }}` and `/frontends/admin-fe/{{ ref }}`
   - Download URL: use `.Values.frontends.*.url` if set, else default CDN with ref substituted
   - Extract path: `/frontends/pleroma-fe/{{ ref }}/`

3. In configmap-akkoma.yaml, parameterize the frontend config:
   ```elixir
   primary: %{"name" => "pleroma-fe", "ref" => "{{ .Values.frontends.pleromaFe.ref }}"},
   admin: %{"name" => "admin-fe", "ref" => "{{ .Values.frontends.adminFe.ref }}"}
   ```

**Backward compat:** Default `ref: "stable"` produces identical behavior to v0.2.3.

**Test:** `helm template` with `--set frontends.pleromaFe.ref=develop`, verify init container and configmap use `develop`.

---

## Iteration 2: Grafana Dashboard ConfigMap

**Goal:** Ship the upstream Akkoma Grafana dashboard as a ConfigMap with sidecar discovery labels.

**Files to modify:**
- `charts/akkoma/values.yaml` -- extend `metrics` section with `grafana` subsection

**Files to create:**
- `charts/akkoma/templates/configmap-grafana-dashboard.yaml`
- `charts/akkoma/ci/grafana-dashboard-values.yaml`

**Changes:**

1. Add to values.yaml under `metrics`:
   ```yaml
   metrics:
     grafana:
       enabled: false
       labels:
         grafana_dashboard: "1"
       annotations: {}
   ```

2. Create `configmap-grafana-dashboard.yaml`:
   - Condition: `metrics.enabled AND metrics.grafana.enabled`
   - Labels: chart labels + `metrics.grafana.labels` (default `grafana_dashboard: "1"` for sidecar)
   - Data: embed dashboard JSON from Akkoma source `installation/grafana_dashboard.json`
   - ~20 panels: BEAM VM, HTTP rates, federation, DB queries, job processing

3. Fetch dashboard JSON from `https://akkoma.dev/AkkomaGang/akkoma/raw/branch/stable/installation/grafana_dashboard.json` and embed as-is (no Helm templating inside JSON).

**Test:** Template with grafana enabled, verify ConfigMap has `grafana_dashboard: "1"` label. Verify NOT rendered when disabled.

---

## Iteration 3: Media Pruning CronJob

**Goal:** CronJob running `pleroma_ctl database prune_objects` on a schedule.

**Files to modify:**
- `charts/akkoma/values.yaml` -- add `mediaPruning` section

**Files to create:**
- `charts/akkoma/templates/cronjob-media-prune.yaml`
- `charts/akkoma/ci/media-prune-values.yaml`

**Changes:**

1. Add to values.yaml:
   ```yaml
   mediaPruning:
     enabled: false
     schedule: "0 3 * * 0"  # 3 AM every Sunday
     options:
       keepFollowed: "posts"  # none, posts, full
       keepThreads: true
       keepNonPublic: true
       limit: 0
       pruneOrphanedActivities: true
       vacuum: false
     successfulJobsHistoryLimit: 3
     failedJobsHistoryLimit: 1
   ```

2. Create `cronjob-media-prune.yaml`:
   - Reuse same env vars, volume mounts, and security context as `db-migrate` init container
   - `concurrencyPolicy: Forbid` (prevent overlapping runs)
   - Build command flags from `.Values.mediaPruning.options.*`
   - Mount config ConfigMap + tmpfs (no uploads PVC needed -- pruning is DB-only)
   - Include S3 env vars conditionally (same pattern as deployment)

**Test:** Template with mediaPruning enabled, verify CronJob and command flags. Verify NOT rendered when disabled.

---

## Iteration 4: CloudNativePG Cluster CR

**Goal:** Deploy a CNPG Cluster CR for operator-managed PostgreSQL, disabling the bundled StatefulSet.

**Files to modify:**
- `charts/akkoma/values.yaml` -- add `postgresql.cnpg` section
- `charts/akkoma/templates/_helpers.tpl` -- update host/secret/passwordKey helpers for CNPG
- `charts/akkoma/templates/deployment.yaml` -- refactor DB_PASSWORD key references (3 occurrences)
- `charts/akkoma/templates/postgresql-statefulset.yaml` -- add CNPG exclusion
- `charts/akkoma/templates/service-postgresql.yaml` -- add CNPG exclusion
- `charts/akkoma/templates/secret-postgresql.yaml` -- add CNPG exclusion
- `charts/akkoma/templates/configmap-postgresql-init.yaml` -- add CNPG exclusion
- `charts/akkoma/templates/networkpolicy-akkoma.yaml` -- CNPG pod selector for egress
- `charts/akkoma/templates/networkpolicy-postgresql.yaml` -- add CNPG exclusion

**Files to create:**
- `charts/akkoma/templates/cnpg-cluster.yaml`
- `charts/akkoma/ci/cnpg-values.yaml`

**Changes:**

1. Add to values.yaml under `postgresql`:
   ```yaml
   postgresql:
     cnpg:
       enabled: false
       instances: 1
       storage:
         size: 10Gi
         storageClass: ""
       imageName: "ghcr.io/cloudnative-pg/postgresql:16"
       parameters: {}
       backup:
         enabled: false
         barmanObjectStore: {}
         volumeSnapshot:
           enabled: false
           className: ""
   ```

2. Add `akkoma.postgresql.passwordKey` helper to `_helpers.tpl`:
   - external → `passwordKey` value (default `password`)
   - cnpg → `password` (CNPG auto-generates `<cluster>-app` Secret with this key)
   - bundled → `postgres-password`

3. Update `akkoma.postgresql.host` helper:
   - cnpg → `{{ fullname }}-cnpg-rw` (CNPG's read-write service)

4. Update `akkoma.postgresql.secretName` helper:
   - cnpg → `{{ fullname }}-cnpg-app` (CNPG's auto-generated app Secret)

5. Refactor 3 DB_PASSWORD occurrences in deployment.yaml (lines 59, 114, 254) from inline logic to `{{ include "akkoma.postgresql.passwordKey" . }}`

6. Update 4 PostgreSQL templates to exclude when CNPG enabled:
   ```
   {{- if and (not .Values.postgresql.external.enabled) (not .Values.postgresql.cnpg.enabled) }}
   ```

7. Create `cnpg-cluster.yaml`:
   - `apiVersion: postgresql.cnpg.io/v1`, `kind: Cluster`
   - `bootstrap.initdb` with database, owner, and `postInitApplicationSQL` for extensions (citext, pg_trgm, uuid-ossp)
   - Storage, instances, parameters from values
   - Optional backup config

8. Update NetworkPolicy akkoma egress to target CNPG pods via `cnpg.io/cluster` label when CNPG enabled.

**Mutual exclusivity:** external > cnpg > bundled (checked in order in helpers).

**Test:** Template with CNPG enabled, verify: Cluster CR rendered, StatefulSet/Service/Secret/ConfigMap-init NOT rendered, deployment points to `-cnpg-rw` host and `-cnpg-app` secret. All existing CI values still pass.

---

## Iteration 5: Documentation & Polish

**Goal:** Bump version, update all docs, add CI coverage.

**Files to modify:**
- `charts/akkoma/Chart.yaml` -- bump to 0.3.0
- `CHANGELOG.md` -- add v0.3.0 entry
- `README.md` -- new sections for all 4 features, updated tables
- `DESIGN.md` -- mark v0.3.0 items as shipped
- `charts/akkoma/templates/NOTES.txt` -- conditional notes for CNPG, pruning, Grafana
- `charts/akkoma/ci/full-values.yaml` -- add frontend, mediaPruning, grafana settings

---

## Iteration Order

```
1. Frontend Version Override (no dependencies, smallest scope)
2. Grafana Dashboard (no dependencies, standalone template)
3. Media Pruning CronJob (no dependencies, standalone template)
4. CloudNativePG Cluster CR (largest scope, touches helpers used by 1-3)
5. Documentation & Polish (must be last)
```

## Verification

Each iteration:
1. `helm lint charts/akkoma --strict`
2. All CI value files pass `helm template`
3. Committed separately

Final verification:
- Fresh install on CMX k3s cluster with default values
- Upgrade from v0.2.3 to v0.3.0 (verify no breaking changes)
- Template all CI value files against K8s 1.28-1.31 with kubeconform
