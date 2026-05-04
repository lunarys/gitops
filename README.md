# k8s GitOps

Personal homelab Kubernetes cluster — a space for experimenting and running self-hosted workloads.
Managed declaratively via GitOps: everything in this repo is what runs in the cluster.
There are small exceptions I don't want to make public. 
These are placed in a quite similar, private repository.

## Repository Structure


- `01_k0s` - k0s cluster configuration and setup scripts
- `02_bootstrap` - Core cluster components bootstrapped before ArgoCD takes over
- `03_apps/apps` - All application deployments, managed as ArgoCD app-of-apps
- `scripts` - Utility scripts

Conventions, patterns, and security architecture are documented in [AGENTS.md](AGENTS.md),
[SECURITY.md](SECURITY.md), and [PRINCIPLES.md](PRINCIPLES.md).

## Cluster Bootstrap

The cluster runs [k0s](https://k0sproject.io/). Before ArgoCD can manage the rest,
a few components are bootstrapped in order:

1. **Cilium** — CNI, must be available before any workloads can run
2. **ArgoCD** — takes over management of everything that follows
3. **Secrets** — secrets for repository and bitwarden access 
4. **Traefik** — internal ingress controller instance

## Core Components

- **Orchestration** — [ArgoCD](https://argo-cd.readthedocs.io/) manages all deployments.
Changes to this repo are reconciled automatically into the cluster.

- **Networking** — [Cilium](https://cilium.io/) as the CNI with eBPF-based network policies
and L2 load balancing. [Traefik](https://traefik.io/) handles ingress — a separate internal
instance (IP allowlist) and an external instance (CrowdSec, rate limiting, GeoBlock).

- **Storage** — [Longhorn](https://longhorn.io/) for replicated block storage,
[local-path-provisioner](https://github.com/rancher/local-path-provisioner) for node-local volumes,
and [csi-driver-smb](https://github.com/kubernetes-csi/csi-driver-smb) for NAS mounts.

- **Databases** — [CloudNativePG](https://cloudnative-pg.io/) operator for PostgreSQL.

- **Secrets** — [External Secrets](https://external-secrets.io/) pulls secrets from Bitwarden
at deploy time. No secrets are stored in git.

- **TLS** — [step-ca](https://smallstep.com/docs/step-ca/) acts as an internal CA;
[cert-manager](https://cert-manager.io/) handles certificate lifecycle and Let's Encrypt
for public-facing services.

- **Security** — [CrowdSec](https://www.crowdsec.net/) for threat detection,
[Kyverno](https://kyverno.io/) for policy enforcement.

## Related Repositories

- [helm-charts](https://github.com/lunarys/generic-helm-chart) — custom Helm charts used by apps in this repo; simplifies interaction with core components
- [gitops-private](https://github.com/lunarys/gitops-private) — private workload configurations, private repository
