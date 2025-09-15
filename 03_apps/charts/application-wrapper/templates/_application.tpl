{{- define "apps-wrapper.application" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ include "apps-wrapper.name" . }}
spec:
  destination:
    namespace: {{ include "apps-wrapper.namespace" . }}
    server: {{ include "apps-wrapper.server" . }}
  project: {{ include "apps-wrapper.name" . }}-project
  sources:
  {{- if eq "chart" .settings.variant }}
    # from Chart.yaml
    - helm:
        version: v3
        valueFiles:
          - values.yaml
          {{- if include "apps-wrapper.targetValuesFile" .root }}
          - {{ include "apps-wrapper.targetValuesFile" .root }}
          {{- end }}
        ignoreMissingValueFiles: true
      repoURL: {{ include "apps-wrapper.repoUrl" . }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      path: {{ include "apps-wrapper.fullpath" . }}
  {{- end }}
  {{- if eq "app" .settings.variant }}
    # from app.yaml
    {{- $defaultHelmRepo := .root.Values.mainHelmRepo }}
    {{- with (index .settings.files "app.yaml") }}
    - repoURL: {{ .helm.repo | default $defaultHelmRepo | quote }}
      {{- if .helm.chart }}
      chart: {{ .helm.chart | quote }}
      {{- else if .helm.path }}
      path: {{ .helm.path | quote }}
      {{- else }}
        {{ fail "Either 'helm.chart' or 'helm.path' setting is required in app.yaml" }}
      {{- end }}
      targetRevision: {{ .helm.version | quote }}
    {{- end }}
      helm:
        #releaseName: ''
        skipCrds: true  # <-- TODO: not used everywhere
        valueFiles:
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/values.yaml'
          {{- if include "apps-wrapper.targetValuesFile" .root }}
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ include "apps-wrapper.targetValuesFile" .root }}'
          {{- end }}
        ignoreMissingValueFiles: true
  {{- end }}
  {{- if index .settings.files "secrets.yaml" }}
    # secrets
    - repoURL: {{ .root.Values.mainHelmRepo }}
      chart: {{ .root.Values.secretsChart }}
      targetRevision: {{ index .settings.files "secrets.yaml" "version" | default .root.Values.secretsChartVersion }}
      helm:
        skipCrds: true
        valueFiles:
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/secrets.yaml'
          {{- if include "apps-wrapper.targetSecretsFile" .root }}
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ include "apps-wrapper.targetSecretsFile" .root }}'
          {{- end }}
  {{- end }}
  {{- if index .settings.files "network.yaml" }}
    # network policy
    - repoURL: {{ .root.Values.mainHelmRepo }}
      chart: {{ .root.Values.networkPolicyChart }}
      targetRevision: {{ index .settings.files "network.yaml" "version" | default .root.Values.networkPolicyChartVersion }}
      helm:
        skipCrds: true
        valueFiles:
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/network.yaml'
  {{- end }}
  {{- if or (eq "app" .settings.variant) (index .settings.files "secrets.yaml") (index .settings.files "network.yaml") }}
    # repo reference for values.yaml for app.yaml, network.yaml or secrets.yaml for secrets
    - repoURL: {{ include "apps-wrapper.repoUrl" . }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      ref: repo
  {{- end }}
  {{- if include "apps-wrapper.hasAdditionalResources" . }}
    # additional resources
    - repoURL: {{ include "apps-wrapper.repoUrl" . }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      path: '{{ include "apps-wrapper.fullpath" . }}/resources'
  {{- end }}
  syncPolicy:
    automated:
      enabled: {{ include "apps-wrapper.autoSyncEnabled" . }}
      selfHeal: true
      prune: false
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true  # cloudnative-pg threw an error otherwise  # TODO: could be used everywhere?
{{- end }}
