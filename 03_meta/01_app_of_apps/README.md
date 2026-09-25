This is the stuff that initially needs to be applied to the cluster for Argo
to take over:

- `argocd-apps` -- the app-of-apps for the rendered application tree
  (`_rendered/argo-resources/`)
- `bootstrap-argo-resources` -- the same, for `02_bootstrap`'s portable
  components (`_rendered/bootstrap-argo-resources/`)
- `app-of-apps-project` -- the AppProject both of the above belong to

Argo CD resources only. Nothing here may depend on a CRD that does not exist
yet, which rules out Kargo resources and ExternalSecrets -- both arrive with
`05_apps`. The Argo-side counterpart for Kargo's own per-app control-plane
output (`kargo-resources` / `bootstrap-kargo-resources`) lives in
`03_meta/03_apps_kargo` instead -- a different responsibility, applied at a
different time (once Kargo itself is up), kept out of this chart on purpose.

Applied by hand, once per cluster:

    helm upgrade --install app-of-apps . -f ../../gitops-values.yaml -f values-<env>.yaml
