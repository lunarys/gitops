{{- /*
  Every helper takes (dict "root" $ "app" <entry from apps-generator.scan>).
*/ -}}

{{- /* The workload namespace. Defaults to the application name. */ -}}
{{- define "apps-generator.namespace" -}}
{{ dig "namespace" .app.name .app.settings }}
{{- end }}

{{- /*
  The app's Kargo Project, which is also its namespace in the prod cluster.

  The prefix is not cosmetic: without it this collides with the workload
  namespace, which is named after the directory for 22 of 23 apps. Kargo will
  not adopt a namespace that lacks the kargo.akuity.io/project label, so the
  Project would simply never initialize.
*/ -}}
{{- define "apps-generator.kargoProjectName" -}}
{{ .root.Values.kargo.projectPrefix }}{{ .app.name }}
{{- end }}

{{- /*
  Whether this app opens a PR against the stage branch for this environment.

  Accepts either shape, because an app overriding it in settings.yaml is likely
  to write the scalar form and a silent wrong answer here means a promotion
  quietly bypasses review:

    openPR: false              -- applies to both environments
    openPR: {test: false, prod: true}
*/ -}}
{{- define "apps-generator.openPR" -}}
{{- $v := dig "kargo" "openPR" (dict) .app.settings -}}
{{- if kindIs "bool" $v -}}
{{ $v }}
{{- else -}}
{{ dig .env true $v }}
{{- end -}}
{{- end }}

{{- /*
  Validates the mode/environment pair. Included unconditionally by both
  emitters, outside their mode guards, so it runs whichever render is active.

  `argo` and `kargo` differ by one character and both are valid, so a swap
  between values-argo-<env>.yaml and values-kargo.yaml would not be caught by
  checking the mode alone. The environment cross-check catches it in both
  directions: the argo files set an environment, the kargo file must not.
*/ -}}
{{- define "apps-generator.validate" -}}
{{- $mode := .Values.mode | default "" -}}
{{- if not (has $mode (list "argo" "kargo")) -}}
  {{- fail (printf "values.mode must be \"argo\" or \"kargo\", got %q -- pass values-argo-<env>.yaml or values-kargo.yaml" $mode) -}}
{{- end -}}
{{- if eq $mode "argo" -}}
  {{- if not .Values.environment -}}
    {{- fail "mode=argo requires `environment` (test or prod): Argo CD resources are rendered per cluster" -}}
  {{- end -}}
  {{- if not (has .Values.environment (list "test" "prod")) -}}
    {{- fail (printf "values.environment must be \"test\" or \"prod\", got %q" .Values.environment) -}}
  {{- end -}}
{{- else -}}
  {{- if .Values.environment -}}
    {{- fail (printf "mode=kargo must not set `environment` (got %q): Kargo resources are rendered once and cover both environments" .Values.environment) -}}
  {{- end -}}
{{- end -}}
{{- /*
  The repository-wide values live in gitops-values.yaml at the repo root, not
  in this chart, so a forgotten `-f` leaves whole blocks nil. Checked before
  reaching into them: without this the first symptom is a nil-pointer panic
  naming an inner key, which reads as a template bug rather than a missing
  values file.
*/ -}}
{{- range $key := list "mainRepo" "appRoot" "renderedBranchPrefix" "renderedRoot" "renderedAppsDir" "kargo" "argo" -}}
  {{- if not (index $.Values $key) -}}
    {{- fail (printf "values.%s is not set -- pass the repository-wide values file: helm template ... -f gitops-values.yaml -f values-<mode>.yaml" $key) -}}
  {{- end -}}
{{- end -}}
{{- if not .Values.kargo.projectPrefix -}}
  {{- fail "values.kargo.projectPrefix must not be empty: a Kargo Project creates a namespace of its own name, which would collide with the app's workload namespace" -}}
{{- end -}}
{{- end }}
