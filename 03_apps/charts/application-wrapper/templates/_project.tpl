{{- define "apps-wrapper.project" -}}
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: {{ include "apps-wrapper.name" . }}-project
spec:
  description: Project for application {{ include "apps-wrapper.name" . }} 
  sourceRepos:
    # my generic app helm charts, including subcharts for secrets, smb-storage, ...
    - {{ .root.Values.mainHelmRepo }}
    # this repo, containing the wrapper chart or the values.yaml file 
    - {{ include "apps-wrapper.repoUrl" . }}
    {{- range $app, $settings := .settings.apps }}
      {{- if and (hasKey $settings.files "app.yaml") (index $settings.files "app.yaml" "helm" "repo") }}
    # repo from {{ .settings.prefix }}app.yaml
    - {{ index $settings.files "app.yaml" "helm" "repo" | trimPrefix "oci://" }}
      {{- end }}
    {{- end }}
  destinations:
    {{- $server := include "apps-wrapper.server" . }}
    - namespace: {{ include "apps-wrapper.namespace" . }}
      server: {{ $server }}
    {{- if index .settings "settings" "additionalNamespaces" }}
    {{- range $ns := (index .settings "settings" "additionalNamespaces") }}
    - namespace: {{ $ns }}
      server: {{ $server }}
    {{- end }}
    {{- end }}
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: false
{{- end }}
