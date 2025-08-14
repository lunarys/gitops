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

{{- define "apps-wrapper.hasAdditionalResources" -}}
{{- range $filename, $_ := .settings.files }}
{{- if hasPrefix "resources/" $filename }}
true
{{- end }}
{{- end }}
{{- end }}
