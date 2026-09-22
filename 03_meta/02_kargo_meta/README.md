The Kargo flow that renders the generator's output onto the stage branches.

- `kargo-apps-generator` -- Namespace, Project, ProjectConfig
- ClusterPromotionTask `render-and-open-pr` -- the task every per-app Stage
  invokes, shared by all of them
- the git credential every promotion clones and pushes with
- Warehouse `sources` -- watches what the generator reads
- Stage `argo-resources-test` -> `stage/test:_rendered/argo-resources/`
- Stage `argo-resources-prod` -> `stage/prod:_rendered/argo-resources/`
- Stage `kargo-resources`     -> `stage/prod:_rendered/kargo-resources/`

Each Stage clones the repo, copies the app tree into the generator chart,
renders it, and opens a PR against the stage branch. A Stage name is also the
directory it writes and the Argo CD Application that reconciles it, so the three
cannot drift apart.


Settings
--------

`values.yaml` holds what only this chart decides; everything else comes from
`gitops-values.yaml` at the repository root.

- `appsDir` -- the directory the app tree is assembled into inside the
  generator chart. The `copy` step writes it and the `helm-template` step
  passes the same string to the generator with `--set`, so the two halves of
  the contract have one declaration.
- `warehouse.interval` / `.freightCreationPolicy` / `.discoveryLimit` -- how
  structural change is discovered.
- `autoPromotion.argo.test` / `.argo.prod` / `.kargo` -- off, deliberately.
  Not because auto-promotion could reach a cluster on its own: it opens a PR
  and parks, like every promotion here. It is about sequencing. These Stages
  are ungated, so auto-promotion opens the prod PR the moment the test one
  appears, for every commit that touches a generator input -- and each one
  holds that Stage's only promotion slot until someone resolves it.


Separate from `03_apps_bootstrap` because these are Kargo resources, and the
Kargo CRDs do not exist at bootstrap time -- Kargo arrives with `05_apps`. A
tier is defined by what is available when it runs, so anything needing a CRD
that bootstrap cannot provide is not a bootstrap resource.

The task and the credential live here rather than with the Kargo install in
`05_apps/kargo`, and for different reasons. The task is a Kargo CR: it cannot be
applied in the same pass that installs the Kargo CRDs, which is the same tier
rule that put this whole directory outside `03_apps_bootstrap` -- a resource
whose prerequisites do not exist yet is not a resource of that tier. The
credential belongs to the flow rather than to the control plane: the install
never reads it, and no promotion can run without it. It lands in
`kargo-shared-resources`, a namespace the install creates, so `05_apps/kargo`
has to be up first.

Applied by hand, once Kargo is up:

    helm dependency build 06_apps_kargo
    helm upgrade --install kargo-apps-generator 06_apps_kargo -f gitops-values.yaml

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
  annotation, formatted `kargo-apps-generator:<stage>`, on the Applications
  named `argo-resources` and `kargo-resources`. Those Applications are
  `03_apps_bootstrap`'s to create.
- **The `copy` step's directory semantics** are undocumented upstream; see the
  note in `_helpers.tpl`.
