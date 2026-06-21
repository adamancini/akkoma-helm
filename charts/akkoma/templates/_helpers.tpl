{{/*
Expand the name of the chart.
*/}}
{{- define "akkoma.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "akkoma.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "akkoma.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akkoma.labels" -}}
helm.sh/chart: {{ include "akkoma.chart" . }}
{{ include "akkoma.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akkoma.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akkoma.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
PostgreSQL host helper
Priority: external > cnpg > bundled
*/}}
{{- define "akkoma.postgresql.host" -}}
{{- if .Values.postgresql.external.enabled -}}
{{ .Values.postgresql.external.host }}
{{- else if .Values.postgresql.cnpg.enabled -}}
{{ include "akkoma.fullname" . }}-cnpg-rw
{{- else -}}
{{ include "akkoma.fullname" . }}-postgresql
{{- end -}}
{{- end -}}

{{/*
PostgreSQL secret name helper
Priority: external > cnpg > bundled
*/}}
{{- define "akkoma.postgresql.secretName" -}}
{{- if .Values.postgresql.external.enabled -}}
{{ .Values.postgresql.external.passwordSecret }}
{{- else if .Values.postgresql.cnpg.enabled -}}
{{ include "akkoma.fullname" . }}-cnpg-app
{{- else if .Values.postgresql.existingSecret -}}
{{ .Values.postgresql.existingSecret }}
{{- else -}}
{{ include "akkoma.fullname" . }}-postgresql
{{- end -}}
{{- end -}}

{{/*
PostgreSQL password key helper
Priority: external > cnpg > bundled
*/}}
{{- define "akkoma.postgresql.passwordKey" -}}
{{- if .Values.postgresql.external.enabled -}}
{{ .Values.postgresql.external.passwordKey | default "password" }}
{{- else if .Values.postgresql.cnpg.enabled -}}
password
{{- else if .Values.postgresql.existingSecret -}}
{{ .Values.postgresql.existingSecretPasswordKey | default "postgres-password" }}
{{- else -}}
postgres-password
{{- end -}}
{{- end -}}

{{/*
Akkoma secret name helper (for external secrets support)
*/}}
{{- define "akkoma.secretName" -}}
{{- if .Values.externalSecret.enabled -}}
{{ .Values.externalSecret.name }}
{{- else -}}
{{ include "akkoma.fullname" . }}-secrets
{{- end -}}
{{- end -}}

{{/*
S3 secret name helper
*/}}
{{- define "akkoma.s3SecretName" -}}
{{- if .Values.storage.s3.existingSecret -}}
{{ .Values.storage.s3.existingSecret }}
{{- else -}}
{{ include "akkoma.fullname" . }}-s3
{{- end -}}
{{- end -}}

{{/*
Resolve a generated secret value, returning a base64-encoded string suitable for
a Secret `data:` field. Precedence: explicit value > existing in-cluster value > random.

The in-cluster lookup only succeeds during `helm install`/`helm upgrade`; under
`helm template` (e.g. ArgoCD), it returns empty, so an explicit value is the only
way to keep a value stable across GitOps renders.

Args (dict):
  ctx        - root context (.)
  value      - explicit plaintext value ("" to fall back)
  secretName - name of the Secret to look up for preservation
  key        - data key within that Secret
  length     - length of the random fallback
*/}}
{{- define "akkoma.resolveSecret" -}}
{{- if .value -}}
{{- .value | b64enc -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace .secretName -}}
{{- if and $existing $existing.data (index $existing.data .key) -}}
{{- index $existing.data .key -}}
{{- else -}}
{{- randAlphaNum (.length | int) | b64enc -}}
{{- end -}}
{{- end -}}
{{- end -}}
