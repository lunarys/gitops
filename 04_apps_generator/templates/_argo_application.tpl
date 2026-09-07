{{- /*
  The previous version was 122 lines, 82 of them a multi-source block: one
  source per chart, one for the shared externalsecrets chart, one for
  networkpolicy, a ref-only source so those could reach value files, one for the
  private repo, and one each for resources/ and resources-<env>/ -- every one
  conditional on which files the app happened to have.

  Pre-rendering deletes all of it. There is exactly one source: a directory of
  plain manifests on a stage branch. Nothing here varies with the app's chart or
  its version, so the Application resource stops changing when the app changes,
  which is what removes the wrapper-before-app sync ordering problem.
*/ -}}
{{- define "apps-generator.application" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .app.name }}
  namespace: {{ .root.Values.argo.namespace }}
  annotations:
    # Restricts which Kargo Stage may drive this Application. Stage names are
    # bare `test`/`prod` because the Kargo Project already namespaces them.
    kargo.akuity.io/authorized-stage: {{ include "apps-generator.kargoProjectName" . }}:{{ .env }}
spec:
  project: {{ .app.name }}-project
  destination:
    namespace: {{ include "apps-generator.namespace" . }}
    server: {{ .root.Values.argo.server }}
  source:
    repoURL: {{ .root.Values.mainRepo }}
    # Kargo pins the exact commit via argocd-update; this is the fallback.
    targetRevision: {{ .root.Values.renderedBranchPrefix }}{{ .env }}
    path: {{ .root.Values.renderedRoot }}/{{ .root.Values.renderedAppsDir }}/{{ .app.name }}
    directory:
      recurse: true
  syncPolicy:
    automated:
      enabled: {{ dig "autoSync" false .app.settings }}
      selfHeal: {{ dig "selfHeal" true .app.settings }}
      {{- if dig "prune" false .app.settings }}
      # Excluded when disabled: an explicit `prune: false` leaves the
      # Application permanently OutOfSync.
      prune: true
      {{- end }}
    syncOptions:
      # Workload namespaces are created by Argo. This is NOT true of the Kargo
      # Project namespaces, which are emitted as explicit labelled Namespace
      # manifests instead -- see _kargo_project.tpl.
      - CreateNamespace=true
      - ServerSideApply={{ dig "serverSideApply" true .app.settings }}
{{- end }}
