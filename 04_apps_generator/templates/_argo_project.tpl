{{- /*
  An Application only ever reads the gitops repo after pre-rendering, so the
  AppProject's remaining job is namespace restriction.
*/ -}}
{{- define "apps-generator.project" -}}
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: {{ .app.name }}-project
  namespace: {{ .root.Values.argo.namespace }}
spec:
  description: Project for application {{ .app.name }}
  sourceRepos:
    # The Application's actual source (_argo_application.tpl), which is
    # mainRepo unless renderedRepo overrides it.
    - {{ include "apps-generator.renderedRepo" .root }}
  destinations:
    - namespace: {{ include "apps-generator.namespace" . }}
      server: {{ .root.Values.argo.server }}
    {{- range $ns := (dig "additionalNamespaces" (list) .app.settings) }}
    - namespace: {{ $ns }}
      server: {{ $.root.Values.argo.server }}
    {{- end }}
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: false
{{- end }}
