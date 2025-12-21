{{- define "apps-wrapper.namespace" -}}
{{ dig "settings" "namespace" .settings.name .settings }}
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
{{- if hasKey .settings.settings "autoSync" -}}
{{ .settings.settings.autoSync }}
{{- else -}}
false
{{- end -}}
{{- end }}

{{- define "apps-wrapper.hasPrivateSettings" -}}
{{- if .settings.settings.privateSettings -}}
true
{{- end -}}
{{- end }}
