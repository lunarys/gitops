{{- define "apps-wrapper.namespace" -}}
{{- /* project is set in the apps context, but not in the project context */ -}}
{{- $defaultNamespace := ternary .settings.project .settings.name (hasKey .settings "project") -}}
{{ dig "settings" "namespace" $defaultNamespace .settings }}
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
{{- $dirprefix := .settings.prefix -}}
{{- $dirname := printf "%sresources/" $dirprefix -}}
{{- range $filename, $_ := .settings.files }}
{{- if hasPrefix $dirname $filename }}
true
{{- end }}
{{- end }}
{{- end }}

{{- define "apps-wrapper.hasPrivateSettings" -}}
{{- if .settings.settings.privateSettings -}}
true
{{- end -}}
{{- end }}
