{{/*
Garage fullname (scoped to parent release)
*/}}
{{- define "garage.fullname" -}}
{{ .Release.Name }}-garage
{{- end -}}

{{/*
Garage labels
*/}}
{{- define "garage.labels" -}}
app.kubernetes.io/name: garage
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: object-storage
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Garage selector labels
*/}}
{{- define "garage.selectorLabels" -}}
app.kubernetes.io/name: garage
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: object-storage
{{- end -}}

{{/*
Garage secret name helper
*/}}
{{- define "garage.secretName" -}}
{{- if .Values.existingSecret -}}
{{ .Values.existingSecret }}
{{- else -}}
{{ include "garage.fullname" . }}
{{- end -}}
{{- end -}}

{{/*
Resolve a generated garage secret value, returning base64 for a Secret `data:` field.
Precedence: explicit value > existing in-cluster value > random. The in-cluster
lookup only succeeds during `helm install`/`helm upgrade`.

Args (dict): ctx (root context), value (plaintext), key (data key), length (random length).
*/}}
{{- define "garage.resolveSecret" -}}
{{- if .value -}}
{{- .value | b64enc -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace (include "garage.fullname" .ctx) -}}
{{- if and $existing $existing.data (index $existing.data .key) -}}
{{- index $existing.data .key -}}
{{- else -}}
{{- randAlphaNum (.length | int) | b64enc -}}
{{- end -}}
{{- end -}}
{{- end -}}
