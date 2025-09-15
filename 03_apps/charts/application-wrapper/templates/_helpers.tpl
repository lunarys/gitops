{{- define "apps-wrapper.namespace" -}}
{{ .settings.name }}
{{- end }}

{{- define "apps-wrapper.fullpath" -}}
{{ .root.Values.baseDir | trimAll "/" }}/{{ .settings.dir }}
{{- end }}

{{- define "apps-wrapper.name" -}}
{{ .settings.name }}
{{- end }}

{{- define "apps-wrapper.repoUrl" -}}
{{ .root.Values.mainRepo }}
{{- end }}

{{- define "apps-wrapper.targetRevision" -}}
{{ .root.Values.targetRevision }}
{{- end }}

{{- define "apps-wrapper.server" -}}
{{ .root.Values.server }}
{{- end }}

{{- define "apps-wrapper.targetValuesFile" -}}
{{- if .Values.targetValuesFile -}}
{{ .Values.targetValuesFile }}
{{- else if .Values.environment -}}
values-{{ .Values.environment }}.yaml
{{- end -}}
{{- end }}

{{- define "apps-wrapper.targetSecretsFile" -}}
{{- if .Values.targetSecretsFile -}}
{{ .Values.targetSecretsFile }}
{{- else if .Values.environment -}}
secrets-{{ .Values.environment }}.yaml
{{- end -}}
{{- end }}

{{- define "apps-wrapper.targetResourcesDir" -}}
{{- if .Values.targetResourcesDir -}}
{{ .Values.targetResourcesDir }}
{{- else if .Values.environment -}}
resources-{{ .Values.environment }}
{{- end -}}
{{- end }}

{{- define "apps-wrapper.hasAdditionalResources" -}}
{{- range $filename, $_ := .settings.files }}
{{- if hasPrefix "resources/" $filename }}
true
{{- end }}
{{- end }}
{{- end }}

{{- define "apps-wrapper.autoSyncEnabled" -}}
{{- if eq "chart" .settings.variant -}}
false
{{- else if and (eq "app" .settings.variant) -}}
  {{- if not (index .settings.files "app.yaml" "helm" "repo") -}}
    true
  {{- else if eq (index .settings.files "app.yaml" "helm" "repo") .root.Values.mainHelmRepo -}}
    true
  {{- else -}}
    false
  {{- end -}}
{{- else -}}
{{- fail "Application is neither variant 'chart' or 'app'" -}}
{{- end -}}
{{- end }}
