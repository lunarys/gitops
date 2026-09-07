The Kargo control plane: API, UI and one controller, prod only, plus the admin
account it reads at startup (`values-secrets.part.yaml`).

**The promotion task and the git credential are not here** -- they are in
`06_apps_kargo`, which explains why. In short: a Kargo CR cannot be applied in
the same pass that installs the Kargo CRDs, and the credential belongs to the
flow that uses it rather than to the control plane that never does.

What this chart does provide for them is `kargo-shared-resources` -- the
namespace that credential lands in, and the RBAC that lets the controller read
Secrets there. Hence this app first, `06_apps_kargo` second.


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
