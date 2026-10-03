Kargo, as two different releases of this chart:

- **prod** -- the control plane (API, UI, webhooks, management controller) and
  the controller for the `prod` shard plus everything unsharded. Also the
  identity the test controller authenticates as
  (`templates/test-shard-identity.yaml`).
- **test** -- only a controller, for the `test` shard. It reconciles the Kargo
  resources in prod through a kubeconfig, and Argo CD in its own cluster.

**The promotion task and the git credential are not here** -- they are in
`03_meta/02_kargo_meta`: a Kargo CR cannot be applied in the same pass that
installs the Kargo CRDs, and the credential belongs to the flow that uses it
rather than to the control plane. What this chart does provide for them is
`kargo-shared-resources` -- the namespace that credential lands in, and the
RBAC that lets the controller read Secrets there.


Bootstrap
---------

Kargo renders this repository, and this app is part of what gets rendered, so
the first install cannot come from a promotion. Same shape as Argo CD: install
by hand once, then let the Application adopt it.

Prod first:

    helm dependency build 05_apps/kargo
    helm upgrade --install kargo 05_apps/kargo -n kargo --create-namespace \
      -f 05_apps/kargo/values.yaml \
      -f 05_apps/kargo/values-network.part.yaml \
      -f 05_apps/kargo/values-prod.yaml \
      -f 05_apps/kargo/values-network-prod.part.yaml \
      -f 05_apps/kargo/values-secrets-prod.part.yaml

Then the kubeconfig for the test controller, stored as a Bitwarden secure note
whose item ID goes into `values-secrets-test.part.yaml`:

    05_apps/kargo/mint-test-kubeconfig.sh > kubeconfig.yaml

Then test -- in namespace `kargo` as well: the controller's heartbeat Lease
lands in the prod namespace of the same name, which is where the identity may
write it.

    helm upgrade --install kargo 05_apps/kargo -n kargo --create-namespace \
      -f 05_apps/kargo/values.yaml \
      -f 05_apps/kargo/values-network.part.yaml \
      -f 05_apps/kargo/values-test.yaml \
      -f 05_apps/kargo/values-network-test.part.yaml \
      -f 05_apps/kargo/values-secrets-test.part.yaml

The hand install and the rendered one must agree, which is what the seeded
stage-branch render is for -- render `05_apps` locally first, and the directory
Argo CD adopts is the one that was just applied.


Not yet resolved
----------------

- **Prod API address.** The test controller reaches a single prod node
  (placeholder in `mint-test-kubeconfig.sh` and `values-network-test.part.yaml`);
  prod has no API VIP.
- **What promotions actually reach out to.** Rendering builds each app's chart
  dependencies, so egress is scoped by shape rather than by host list: HTTPS,
  to any name resolved through the DNS proxy, and nothing else. Once real
  promotions have run, `hubble observe` says what that set really is, and it
  can be narrowed from evidence if it turns out to be worth it.
