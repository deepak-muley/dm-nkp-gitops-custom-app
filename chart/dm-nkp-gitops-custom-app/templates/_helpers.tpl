{{/*
Expand the name of the chart.
*/}}
{{- define "dm-nkp-gitops-custom-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "dm-nkp-gitops-custom-app.fullname" -}}
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
{{- define "dm-nkp-gitops-custom-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dm-nkp-gitops-custom-app.labels" -}}
helm.sh/chart: {{ include "dm-nkp-gitops-custom-app.chart" . }}
{{ include "dm-nkp-gitops-custom-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dm-nkp-gitops-custom-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dm-nkp-gitops-custom-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "dm-nkp-gitops-custom-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "dm-nkp-gitops-custom-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get namespace - handles empty strings properly
*/}}
{{- define "dm-nkp-gitops-custom-app.namespace" -}}
{{- if and .Values.namespace.name (ne .Values.namespace.name "") }}
{{- .Values.namespace.name }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Get Grafana namespace - handles empty strings and missing values properly
Checks dashboards namespace first, then datasources namespace, then defaults to Release.Namespace
*/}}
{{- define "dm-nkp-gitops-custom-app.grafanaNamespace" -}}
{{- if and .Values.grafana.dashboards.namespace (ne .Values.grafana.dashboards.namespace "") }}
{{- .Values.grafana.dashboards.namespace }}
{{- else if and .Values.grafana.datasources.namespace (ne .Values.grafana.datasources.namespace "") }}
{{- .Values.grafana.datasources.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Get monitoring namespace - handles empty strings and missing values properly
*/}}
{{- define "dm-nkp-gitops-custom-app.monitoringNamespace" -}}
{{- if and .Values.monitoring.serviceMonitor.namespace (ne .Values.monitoring.serviceMonitor.namespace "") }}
{{- .Values.monitoring.serviceMonitor.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}
