{{- /*
  One Warehouse per app.

  Note the two different identifiers. The resource is named after the
  APPLICATION (settings.yaml applicationName, else the directory), matching the
  Argo CD Application. includePaths uses the DIRECTORY, because Kargo filters
  Freight by repository path and the path is what it is regardless of what the
  app calls itself.

  Deliberately unsharded. It is reconciled by the prod controller, which runs
  with isDefault: true, so Freight discovery keeps running while the test
  cluster is off. That is the property the whole offline-test design rests on --
  and if the prod controller ever loses isDefault, nothing reconciles these and
  no Freight is ever created, with no error to explain why.
*/ -}}
{{- define "apps-generator.warehouse" -}}
{{- $path := printf "%s/%s" (.root.Values.appRoot | trimSuffix "/") .app.dir -}}
{{- $policy := dig "kargo" "freightCreationPolicy" "Automatic" .app.settings -}}
{{- /*
  Checked here rather than left to Kargo's webhook: a bad value in one app's
  settings.yaml would otherwise only surface as a partial Argo sync failure
  against the generated file, which is a much worse signal than a failed render.
*/ -}}
{{- if not (has $policy (list "Automatic" "Manual")) -}}
  {{- fail (printf "%s: kargo.freightCreationPolicy must be \"Automatic\" or \"Manual\", got %q" .app.dir $policy) -}}
{{- end -}}
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: {{ .app.name }}
  namespace: {{ include "apps-generator.kargoProjectName" . }}
spec:
  interval: {{ dig "kargo" "interval" "5m" .app.settings }}
  freightCreationPolicy: {{ $policy }}
  subscriptions:
    - git:
        repoURL: {{ .root.Values.mainRepo }}
        branch: {{ .root.Values.sourceBranch }}
        commitSelectionStrategy: NewestFromBranch
        includePaths:
          - {{ $path }}/
        excludePaths:
          # Docs and examples sit inside the app directory but cannot affect the
          # rendered output, so they should not produce release candidates.
          #
          # regex rather than glob for the markdown rule, because it has to
          # match at any depth (adguard-home/docker/README.md is two levels in)
          # and the glob dialect Kargo uses is not documented -- whether `**`
          # spans separators, and whether `a/**/*.md` also matches `a/READ.md`,
          # varies by library and would fail silently. Plain strings, as used
          # for the directories below, are exact path matches.
          - regex:^{{ $path }}/.*\.md$
          - {{ $path }}/example/
          - {{ $path }}/examples/
          {{- range $p := (dig "kargo" "excludePaths" (list) .app.settings) }}
          - {{ $path }}/{{ $p | trimPrefix "/" }}
          {{- end }}
        discoveryLimit: {{ dig "kargo" "discoveryLimit" 20 .app.settings }}
{{- end }}
