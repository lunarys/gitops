Reconciles what `03_meta/02_kargo_meta` renders for each app's own Kargo
control plane:

- `apps-kargo` -- one Application, two sources: `_rendered/kargo-resources/`
  (per-app Namespace, Kargo Project, ProjectConfig, Warehouse, Stage(s);
  root = `05_apps`) and `_rendered/bootstrap-kargo-resources/`, the same for
  `02_bootstrap`'s portable components (root = `02_bootstrap`)
- `apps-kargo-project` -- the AppProject it belongs to, scoped narrowly to
  `kargo-app-*` and `kargo-apps-generator`

Kept separate from both `01_app_of_apps` and `02_kargo_meta` on purpose:

- Not `01_app_of_apps`, because that chart is Argo CD resources only --
  nothing here may depend on a CRD that doesn't exist at bootstrap time,
  and everything in this chart references `kargo.akuity.io` objects that
  only arrive with `05_apps`.
- Not `02_kargo_meta`, even though both are Kargo-adjacent and both are
  hand-applied once Kargo is up: `02_kargo_meta` *produces* the render this
  chart *reconciles* -- a different responsibility, not worth conflating
  even though the cost of doing so would only have been operational.

Only ever meaningful on the prod cluster -- Kargo itself runs prod-only, so
there is no per-environment split here at all, same as `02_kargo_meta`.

Applied by hand, once Kargo is up (after `02_kargo_meta`):

    helm upgrade --install apps-kargo . -f ../../gitops-values.yaml
