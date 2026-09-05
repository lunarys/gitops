{{- /*
  The previous version enumerated every Helm repository any app in the project
  pulled from, so Argo's source allowlist would permit them. After pre-rendering
  an Application only ever reads the gitops repo, so that loop is gone and the
  AppProject's remaining job is namespace restriction -- which is the part that
  was actually load-bearing.
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
    - {{ .root.Values.mainRepo }}
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
