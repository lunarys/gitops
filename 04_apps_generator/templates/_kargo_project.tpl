{{- /*
  One Kargo Project per app, and the namespace it lives in.

  The Namespace is emitted EXPLICITLY rather than left to Kargo's Project
  controller. Both would work, but only this way is the ordering deterministic:
  the Warehouse and Stages below are namespaced into this namespace, and Argo
  applies them in one sync. Argo's built-in kind ordering puts Namespace first,
  so it exists before anything lands in it.

  Sync waves would NOT have fixed this. Argo has no health check for
  kargo.akuity.io/Project, so it treats the CR as Healthy the instant it is
  applied and moves on -- before the controller has created any namespace.

  The kargo.akuity.io/project label is what permits Kargo to adopt a
  pre-existing namespace; without it the Project never initializes. Which is
  also why the Application applying these manifests must NOT set
  CreateNamespace: an auto-created namespace would not carry the label.

  keep-namespace makes Argo the single owner, so deleting the Project does not
  race Argo's prune for the same namespace.
*/ -}}
{{- define "apps-generator.kargoProject" -}}
{{- $ns := include "apps-generator.kargoProjectName" . -}}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ $ns }}
  labels:
    kargo.akuity.io/project: "true"
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: {{ $ns }}
  annotations:
    kargo.akuity.io/keep-namespace: "true"
---
{{- /*
  Kargo already defaults to manual promotion, so this block is belt-and-braces.
  It is worth the objects: auto-promotion into the test cluster is the one
  failure this design must not have, because that cluster is powered off most of
  the time and promotions would queue against a controller that is not running.
*/ -}}
apiVersion: kargo.akuity.io/v1alpha1
kind: ProjectConfig
metadata:
  name: {{ $ns }}
  namespace: {{ $ns }}
spec:
  promotionPolicies:
    - stageSelector:
        name: test
      autoPromotionEnabled: false
    - stageSelector:
        name: prod
      autoPromotionEnabled: false
{{- end }}
