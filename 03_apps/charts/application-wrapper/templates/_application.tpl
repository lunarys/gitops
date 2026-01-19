{{- define "apps-wrapper.application" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ include "apps-wrapper.name" . }}
spec:
  destination:
    namespace: {{ include "apps-wrapper.namespace" . }}
    server: {{ include "apps-wrapper.server" . }}
  project: {{ .settings.project }}-project
  sources:
  {{- $appFilesPrefix := .settings.prefix }}
  {{- if hasKey .settings.files "Chart.yaml" }}
    # from Chart.yaml
    - helm:
        version: v3
        skipCrds: {{ .settings.settings.skipCrds }}
        valueFiles:
          - {{ $appFilesPrefix }}values.yaml
          {{- if include "apps-wrapper.targetValuesFile" .root }}
          - {{ $appFilesPrefix }}{{ include "apps-wrapper.targetValuesFile" .root }}
          {{- end }}
          {{- if and .root.Values.privateRepoEnabled .root.Values.privateRepo (include "apps-wrapper.hasPrivateSettings" .) (include "apps-wrapper.targetValuesFile" .root) }}
          - $privateRepo/config/{{ .settings.name }}/{{ $appFilesPrefix }}{{ include "apps-wrapper.targetValuesFile" .root }}
          {{- end }}
        ignoreMissingValueFiles: true
      repoURL: {{ include "apps-wrapper.repoUrl" . }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      path: {{ include "apps-wrapper.fullpath" . }}
  {{- end }}
  {{- if hasKey .settings.files "app.yaml" }}
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
        skipCrds: {{ .settings.settings.skipCrds }}
        valueFiles:
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ $appFilesPrefix }}values.yaml'
          {{- if include "apps-wrapper.targetValuesFile" .root }}
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ $appFilesPrefix }}{{ include "apps-wrapper.targetValuesFile" .root }}'
          {{- end }}
          {{- if and .root.Values.privateRepoEnabled .root.Values.privateRepo (include "apps-wrapper.hasPrivateSettings" .) (include "apps-wrapper.targetValuesFile" .root) }}
          - $privateRepo/config/{{ .settings.project }}/{{ $appFilesPrefix }}{{ include "apps-wrapper.targetValuesFile" .root }}
          {{- end }}
        ignoreMissingValueFiles: true
  {{- end }}
  {{- if hasKey .settings.files "secrets.yaml" }}
    # secrets
    - repoURL: {{ .root.Values.mainHelmRepo }}
      chart: {{ .root.Values.secretsChart }}
      targetRevision: {{ index .settings.files "secrets.yaml" "version" | default .root.Values.secretsChartVersion }}
      helm:
        skipCrds: true
        valueFiles:
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ $appFilesPrefix }}secrets.yaml'
          {{- if include "apps-wrapper.targetSecretsFile" .root }}
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ $appFilesPrefix }}{{ include "apps-wrapper.targetSecretsFile" .root }}'
          {{- end }}
  {{- end }}
  {{- if hasKey .settings.files "network.yaml" }}
    # network policy
    - repoURL: {{ .root.Values.mainHelmRepo }}
      chart: {{ .root.Values.networkPolicyChart }}
      targetRevision: {{ index .settings.files "network.yaml" "version" | default .root.Values.networkPolicyChartVersion }}
      helm:
        skipCrds: true
        valueFiles:
          - '$repo/{{ include "apps-wrapper.fullpath" . }}/{{ $appFilesPrefix }}network.yaml'
  {{- end }}
  {{- if or (hasKey .settings.files "app.yaml") (hasKey .settings.files "secrets.yaml") (hasKey .settings.files "network.yaml") }}
    # repo reference for values.yaml for app.yaml, network.yaml or secrets.yaml for secrets
    - repoURL: {{ include "apps-wrapper.repoUrl" . }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      ref: repo
  {{- end }}
  {{- if and .root.Values.privateRepoEnabled .root.Values.privateRepo (include "apps-wrapper.hasPrivateSettings" .) (include "apps-wrapper.targetValuesFile" .root) }}
    # private repo for values.yaml
    - repoURL: {{ .root.Values.privateRepo }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      ref: privateRepo
  {{- end }}
  {{- if include "apps-wrapper.hasAdditionalResources" . }}
    # additional resources
    - repoURL: {{ include "apps-wrapper.repoUrl" . }}
      targetRevision: {{ include "apps-wrapper.targetRevision" . }}
      path: '{{ include "apps-wrapper.fullpath" . }}/{{ $appFilesPrefix }}resources'
  {{- end }}
  syncPolicy:
    automated:
      enabled: {{ .settings.settings.autoSync }}
      selfHeal: {{ .settings.settings.selfHeal }}
      {{- if .settings.settings.prune }}
      {{- /* This setting is excluded when disabled, as it leads to OutOfSync after a Sync of the Application resources for some reason */ -}}
      prune: {{ .settings.settings.prune }}
      {{- end }}
    syncOptions:
      - CreateNamespace=true
      {{- if hasKey .settings.settings "serverSideApply" }}
      - ServerSideApply={{ .settings.settings.serverSideApply }}
      {{- end }}
{{- end }}
