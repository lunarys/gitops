The Kargo control plane, and the conventions that make it this repository's.

- the **install** (`values.yaml`) -- API, UI and one controller, prod only;
- the **`render-and-open-pr` ClusterPromotionTask** (`templates/`), which every
  per-app Stage the generator emits invokes;
- the **git credential** (`values-secrets.part.yaml`), one Secret in
  `kargo-shared-resources` serving every Project.

The task lives here rather than in the generator because it is not generic: it
encodes where a render lands, how the pull request branch is named and what the
commit says. Its contract with `04_apps_generator/templates/_kargo_stages.tpl`
-- twelve vars, the `./src` + `./out` workspace layout, and the `commit` output
-- is written out at the top of the template.


Bootstrap
---------

Kargo renders this repository, and this app is part of what gets rendered, so
the first install cannot come from a promotion. Same shape as Argo CD: install
by hand once, then let the Application adopt it.

    helm dependency build 05_apps/kargo
    helm upgrade --install kargo 05_apps/kargo -n kargo --create-namespace \
      -f 05_apps/kargo/values.yaml \
      -f 05_apps/kargo/values-secrets.part.yaml \
      -f 05_apps/kargo/values-network.part.yaml

The hand install and the rendered one must agree, which is what the seeded
stage-branch render is for -- render `05_apps` locally first, and the directory
Argo CD adopts is the one that was just applied.


Not yet resolved
----------------

- **The test shard.** This install is prod only, and its controller claims the
  `prod` shard plus everything unsharded. Nothing claims `test`, so every test
  Stage -- each app's, and `06_apps_kargo`'s `argo-resources-test` -- sits
  Pending rather than failing. Fixing it means a second, controller-only
  release in the test cluster (`controller.shardName: test`, API, garbage
  collector, management controller and webhooks server all off) plus a
  kubeconfig Secret pointing back at this cluster, and a ServiceAccount and
  RBAC here to back it.
- **What promotions actually reach out to.** Rendering builds each app's chart
  dependencies, so egress is scoped by shape rather than by host list: HTTPS,
  to any name resolved through the DNS proxy, and nothing else. Once real
  promotions have run, `hubble observe` says what that set really is, and it
  can be narrowed from evidence if it turns out to be worth it.
