{{- /*
  Where the rendered tree lands. Same helper, same reasoning, as
  04_apps_generator's apps-generator.renderedRepo: defaults to mainRepo --
  renderedRepo is set only to try the workflow against a scratch repo.
*/ -}}
{{- define "app-of-apps.renderedRepo" -}}
{{ .Values.renderedRepo | default .Values.mainRepo }}
{{- end }}
