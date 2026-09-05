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
            - name: namespace
              value: {{ include "apps-generator.namespace" . }}
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
        - uses: argocd-update
          config:
            apps:
              - name: {{ $app.name }}
                namespace: {{ $root.Values.argo.namespace }}
                sources:
                  - repoURL: {{ $root.Values.mainRepo }}
                    # Quoted deliberately. Every Kargo expression in a step
                    # config is wrapped in explicit YAML quotes here: an
                    # unquoted expression containing a ternary reads to a
                    # lenient YAML parser as complex-mapping-key syntax
                    # (`? key` / `: value`), so the field silently becomes a
                    # map and Kargo rejects it as "given: object".
                    desiredRevision: "${{ "{{" }} outputs['render'].commit {{ "}}" }}"
  {{- with dig "kargo" "verification" (dict) $app.settings }}
  # Opt in per app -- see defaultSettings.kargo.verification in values.yaml.
  # Without this block Kargo falls back to implicit verification: Freight counts
  # as verified once the referenced Argo CD Applications report Healthy. That is
  # a real signal, but it says the workload started, not that it works.
  verification:
{{ toYaml . | indent 4 }}
  {{- end }}
{{- end }}
