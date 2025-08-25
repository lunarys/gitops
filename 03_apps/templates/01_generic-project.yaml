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
    {{- if and (eq "app" .settings.variant) (index .settings.files "app.yaml" "helm" "repo") }}
    # repo from app.yaml
    - {{ index .settings.files "app.yaml" "helm" "repo" }}
    {{- end }}
    {{- /* if eq "chart" .settings.variant }}
      {{- range $dep := (index .settings "files" "Chart.yaml" "dependencies" | required "Helm Chart does not have dependencies") }}
    - {{ .repository }}
      {{- end }}
    {{- end */}}
  destinations:
    - namespace: {{ include "apps-wrapper.namespace" . }}
      server: {{ include "apps-wrapper.server" . }}
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: false
{{- end }}
