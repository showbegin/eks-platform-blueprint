{{/*
Common labels applied to all resources.
*/}}
{{- define "microservice.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Values.app.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.app.name }}
environment: {{ .Values.environment | quote }}
{{- end }}

{{/*
Selector labels (subset of common labels — must remain stable across versions).
*/}}
{{- define "microservice.selectorLabels" -}}
app.selector: {{ .Values.app.selector }}
app: {{ .Values.app.fullname }}
{{- end }}

{{/*
Service account name — uses the chart-managed SA by default.
*/}}
{{- define "microservice.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (printf "%s-sa" .Values.app.name) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{/*
Full hostname (hostname.domain).
*/}}
{{- define "microservice.fullHostname" -}}
{{- printf "%s.%s" .Values.hostname .Values.domain -}}
{{- end }}

{{/*
IRSA role ARN.
*/}}
{{- define "microservice.irsaRoleArn" -}}
{{- printf "arn:aws:iam::%s:role/%s-%s" (toString .Values.awsAccountId) .Values.environment .Values.serviceAccount.irsa.roleSuffix -}}
{{- end }}

{{/*
Vault secret path. Defaults to secret/data/${app.name}/${environment}.
*/}}
{{- define "microservice.vaultSecretPath" -}}
{{- if .Values.vault.secretPath -}}
{{ .Values.vault.secretPath }}
{{- else -}}
{{ printf "secret/data/%s/%s" .Values.app.name .Values.environment }}
{{- end -}}
{{- end }}
