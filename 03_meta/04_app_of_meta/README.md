Self-manages `01_app_of_apps`, `02_kargo_meta` and `03_apps_kargo` as Helm
charts, once each has been hand-applied:

- `meta-app-of-apps` -- self-manages `01_app_of_apps` (both environments)
- `meta-kargo-apps-generator` -- self-manages `02_kargo_meta` (prod only)
- `meta-apps-kargo` -- self-manages `03_apps_kargo` (prod only)

Named `meta-*` rather than after the chart each one tracks: these are release
trackers, not app-of-apps instances themselves.

No Kargo process for these -- Argo re-reads git unconditionally, so its own
app-of-apps can safely manage itself this way (same pattern already used for
`02_bootstrap/01_argocd`'s own self-management inside `01_app_of_apps`,
generalized to the rest of the meta tier).

Must be applied strictly after the charts it manages already exist on the
cluster, since it takes over Applications a human already created by hand.
Its own two AppProjects (`app-of-meta-project`, `kargo-meta-project`) are
dedicated and created by this chart itself, deliberately not reused from
`01_app_of_apps` or `02_kargo_meta` -- otherwise app-of-meta's own
applicability would depend on a project one of its self-managed children
creates.

Applied by hand, once per cluster (prod also brings up the two prod-only
Applications above):

    helm upgrade --install app-of-meta . -f ../../gitops-values.yaml -f values-<env>.yaml
