{{- /*
  One Stage per app per environment, named plainly `test` / `prod` because the
  per-app Kargo Project already namespaces them.

  Carries several things learned by running this against a real Kargo instance
  rather than by reading the docs -- each marked below. They are the reason this
  file should be edited carefully rather than rewritten from the reference docs.
*/ -}}
{{- define "apps-generator.stage" -}}
{{- $root := .root -}}
{{- $app := .app -}}
{{- $env := .env -}}
{{- /*
  The promotion task renders from a clone at ./src, so every path handed to it
  is workspace-relative. That layout is part of the task's contract with this
  emitter, like the var names themselves -- the alternative is prefixing inside
  the task with an expression built from map(), which would put a second
  unverified assumption on top of the JSON-encoded var below.
*/ -}}
{{- $srcDir := printf "./src/%s/%s" ($root.Values.appRoot | trimSuffix "/") $app.dir -}}
{{- $valuesFiles := list -}}
{{- range concat (dig "base" (list) $app.valuesFiles | default (list)) (dig $env (list) $app.valuesFiles | default (list)) -}}
  {{- $valuesFiles = append $valuesFiles (printf "%s/%s" $srcDir .) -}}
{{- end -}}
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: {{ $env }}
  namespace: {{ include "apps-generator.kargoProjectName" . }}
spec:
  # spec.shard, NOT the kargo.akuity.io/shard label. The Stage admission webhook
  # treats spec.shard as authoritative and derives the label from it, silently
  # stripping any label that does not match. Setting only the label -- as older
  # docs describe -- means no controller ever claims the Stage, with no error.
  #
  # A Stage runs on the shard of the cluster it changes, so a promotion never
  # half-runs against a cluster that is powered off: it does not start at all.
  shard: {{ index $root.Values.kargo.shards $env }}
  requestedFreight:
    - origin:
        kind: Warehouse
        name: {{ $app.name }}
      sources:
        {{- if and (eq $env "prod") .upstream }}
        # Production takes Freight only after test has had it. Emitted only when
        # the app is actually enabled in test -- a prod-only app has no test
        # Stage to gate on and would deadlock waiting for one.
        stages:
          - test
        {{- else }}
        direct: true
        {{- end }}
  promotionTemplate:
    spec:
      steps:
        - task:
            name: {{ $root.Values.kargo.promotionTask }}
            # Cluster-scoped so one definition serves every per-app Project.
            kind: ClusterPromotionTask
          as: render
          vars:
            - name: repoURL
              value: {{ $root.Values.mainRepo }}
            # The task only ever sees repoURL as a Kargo expression
            # (`vars.repoURL`), never the literal -- it is a shared task, not
            # this Stage. Passed separately so the task's commit provenance can
            # link to the source commit without needing mainRepo's literal
            # value itself.
            - name: sourceRepoWebURL
              value: {{ $root.Values.mainRepo | trimSuffix ".git" }}
            # Where the render is committed/pushed/PR'd. Same as repoURL
            # unless renderedRepo overrides it -- see gitops-values.yaml.
            - name: renderedRepoURL
              value: {{ include "apps-generator.renderedRepo" $root }}
            - name: app
              value: {{ $app.name }}
            # The directory, which may differ from the application name.
            - name: appDir
              value: {{ $app.dir }}
            - name: appRoot
              value: {{ $root.Values.appRoot | trimSuffix "/" }}
            - name: env
              value: {{ $env }}
            - name: targetBranch
              value: {{ $root.Values.renderedBranchPrefix }}{{ $env }}
            # The exact values files this app has, in layering order, derived
            # from the directory at render time. The task cannot work this out
            # for itself: valuesFiles is a plain []string with no glob support,
            # Kargo has no split(), and the task does not know the labels.
            #
            # Because only files that exist are listed, the task needs no
            # ignoreMissingValueFiles -- a misnamed file is one the generator
            # rejects outright rather than one Helm silently skips.
            #
            # A JSON-encoded STRING, not a YAML list: the Stage CRD types a
            # var's value as string, and the API server rejects a list there
            # ("expected string, got ... []interface {}") -- the docs' "static
            # values of any type" notwithstanding.
            #
            # The task gets a list back regardless. Checked against Kargo
            # v1.11.4's pkg/expressions/json_templates.go (EvaluateTemplate):
            # this var has no expression delimiters, so it stays a plain
            # string; the task's whole-field vars.valuesFiles expression then
            # evaluates to that string, which is json.Unmarshal'ed into an
            # array (after number/bool fail) before the step config is
            # marshalled -- so helm-template's valuesFiles sees a []string.
            - name: valuesFiles
              value: {{ toJson $valuesFiles | quote }}
            - name: namespace
              value: {{ include "apps-generator.namespace" . }}
            {{- /*
              Where the render lands, and the branch the pull request is opened
              from. Both are conventions this repository owns and the task does
              not: an app chart is rendered with its own values files only and
              never sees gitops-values.yaml, so a task that derived these itself
              would be deriving them from a second, silently divergent copy.
            */}}
            - name: outRoot
              value: {{ $root.Values.renderedRoot }}/{{ $root.Values.renderedAppsDir }}
            - name: promotionBranch
              value: {{ $root.Values.promotionBranchPrefix }}{{ $app.name }}-{{ $env }}
            # skipCrds is a RENDER decision now, not an Argo sync option.
            - name: includeCRDs
              value: {{ not (dig "skipCrds" true $app.settings) | quote }}
            - name: openPR
              value: {{ include "apps-generator.openPR" . | quote }}
        # Both environments sync and report health.
        #
        # Omitting this would be strictly worse than including it: the Stage
        # would then reference no Argo CD Application, so Kargo has no implicit
        # health signal and "verified in test" degrades to "the promotion
        # finished". There is no scenario where this step fails for lack of a
        # cluster, because the promotion only runs on that cluster's shard.
        #
        # argoSyncEnabled is the one exception: false while first trying
        # renderedRepo against a scratch repo, so nothing here ever asks a real
        # Argo CD to sync from it.
        {{- if $root.Values.argoSyncEnabled }}
        - uses: argocd-update
          config:
            apps:
              - name: {{ $app.name }}
                namespace: {{ $root.Values.argo.namespace }}
                sources:
                  # Must match the Application's actual source (set in
                  # _argo_application.tpl from the same helper), not
                  # necessarily mainRepo.
                  - repoURL: {{ include "apps-generator.renderedRepo" $root }}
                    # Quoted deliberately. Every Kargo expression in a step
                    # config is wrapped in explicit YAML quotes here: an
                    # unquoted expression containing a ternary reads to a
                    # lenient YAML parser as complex-mapping-key syntax
                    # (`? key` / `: value`), so the field silently becomes a
                    # map and Kargo rejects it as "given: object".
                    desiredRevision: "${{ "{{" }} outputs['render'].commit {{ "}}" }}"
        {{- end }}
  {{- with dig "kargo" "verification" (dict) $app.settings }}
  # Opt in per app -- see defaultSettings.kargo.verification in values.yaml.
  # Without this block Kargo falls back to implicit verification: Freight counts
  # as verified once the referenced Argo CD Applications report Healthy. That is
  # a real signal, but it says the workload started, not that it works.
  verification:
{{ toYaml . | indent 4 }}
  {{- end }}
{{- end }}
