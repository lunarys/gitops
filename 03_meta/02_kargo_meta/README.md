The Kargo flow that renders the generator's output onto the stage branches.

- `kargo-apps-generator` -- Namespace, Project, ProjectConfig
- ClusterPromotionTask `render-and-open-pr` -- the task every per-app Stage
  invokes, shared by all of them
- the git credential every promotion clones and pushes with
- Warehouse `sources` -- watches what the generator reads
- Stage `argo-resources-test` -> `stage/test:_rendered/{argo-resources,bootstrap-argo-resources}/`
- Stage `argo-resources-prod` -> `stage/prod:_rendered/{argo-resources,bootstrap-argo-resources}/`
- Stage `kargo-resources`     -> `stage/prod:_rendered/{kargo-resources,bootstrap-kargo-resources}/`

Each Stage now runs TWO render passes -- the regular `05_apps` tree and
`02_bootstrap`'s portable components (`cilium`, `argocd`, `traefik`; never
`02_manual-secrets`, interactive secret entry) -- but still clones the repo
once, opens one PR, and drives one Promotion; see `apps-kargo.stage` in
`_helpers.tpl` for the per-pass loop.

Each Stage's two passes are reconciled by a single Application, not one
Application per directory: `03_meta/01_app_of_apps`'s `app-of-apps` for both
argo-resources Stages (test and prod), and `03_meta/03_apps_kargo`'s
`apps-kargo` for the kargo-resources Stage. 


Settings
--------

`values.yaml` holds what only this chart decides; everything else comes from
`gitops-values.yaml` at the repository root.

- `appsDir` -- the directory the app tree is assembled into inside the
  generator chart. The `copy` step writes it and the `helm-template` step
  passes the same string to the generator with `--set`, so the two halves of
  the contract have one declaration.
- `bootstrapRoot` / `bootstrapAppsDir` -- the same pair, for the second render
  pass over `02_bootstrap`'s portable components.
- `warehouse.interval` / `.freightCreationPolicy` / `.discoveryLimit` -- how
  structural change is discovered.
- `autoPromotion.argo.test` / `.argo.prod` / `.kargo` -- off, deliberately.
  Not because auto-promotion could reach a cluster on its own: it opens a PR
  and parks, like every promotion here. It is about sequencing. These Stages
  are ungated, so auto-promotion opens the prod PR the moment the test one
  appears, for every commit that touches a generator input -- and each one
  holds that Stage's only promotion slot until someone resolves it.


Separate from `03_meta/01_app_of_apps` and `03_meta/03_apps_kargo` because these
are Kargo resources, and the Kargo CRDs do not exist at bootstrap time --
Kargo arrives with `05_apps`. A tier is defined by what is available when it
runs, so anything needing a CRD that bootstrap cannot provide is not a
bootstrap resource.

The task and the credential live here rather than with the Kargo install in
`05_apps/kargo`, and for different reasons. The task is a Kargo CR: it cannot be
applied in the same pass that installs the Kargo CRDs, which is the same tier
rule that put this whole directory outside `03_meta/01_app_of_apps` -- a resource
whose prerequisites do not exist yet is not a resource of that tier. The
credential belongs to the flow rather than to the control plane: the install
never reads it, and no promotion can run without it. It lands in
`kargo-shared-resources`, a namespace the install creates, so `05_apps/kargo`
has to be up first.

Applied by hand, once Kargo is up:

    helm dependency build 03_meta/02_kargo_meta
    helm upgrade --install kargo-apps-generator 03_meta/02_kargo_meta -f gitops-values.yaml

There is deliberately no promotion flow for this directory yet: it *is* the
promotion flow, so promoting it with itself means a bad render breaks the
mechanism that would fix it. Kargo, unlike Argo CD, cannot recover by re-reading
git -- rendering is the part that breaks.


Not yet resolved
----------------

- **The Bitwarden item behind the git credential.** `values.yaml` names it by
  UUID: a login item whose username is the GitHub user and whose password is a
  token with `repo` scope. Every promotion in every Project clones, pushes and
  opens pull requests with it, so nothing promotes until it exists and
  `05_apps/kargo` has created the namespace it is written into.
- **`kargo.akuity.io/authorized-stage`.** The `argocd-update` steps require that
  annotation, formatted `kargo-apps-generator:<stage>`, on every distinct
  Application named in a Stage's `passes` list: `app-of-apps`
  (`03_meta/01_app_of_apps`'s to create, covering both argo-resources
  passes) and `apps-kargo` (`03_meta/03_apps_kargo`'s to create, covering
  both kargo-resources passes).
- **The `copy` step's directory semantics** are undocumented upstream; see the
  note in `_helpers.tpl`.
