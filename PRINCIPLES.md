# Deployment Principles

This document captures the guiding principles behind how applications are deployed in this cluster.
It complements `AGENTS.md` (patterns) and `SECURITY.md` (security architecture) with the *why*.

---

## 1. Declarative Infrastructure (GitOps)

All cluster state is committed to git. ArgoCD drives reconciliation — no manual `kubectl apply`
or in-cluster edits. If something isn't in git, it doesn't exist (or will be pruned).

## 2. Least Privilege

Applied at every layer:

- **Network**: Namespace isolation on by default. Egress uses specific `toFQDNs` or
  `toNetworkLabels` rather than broad `toWorld`. Ingress is explicitly enumerated.
- **RBAC**: Minimal verbs (`get`, `list`, `watch`), no wildcards, scoped to the minimum
  resource set. Namespace-scoped `Role` preferred over `ClusterRole` where possible.
- **Pod security**: Non-root by default (`runAsNonRoot: true`, UID 1000), drop ALL capabilities
  and add back only what is specifically required (e.g. `SYS_CHROOT`, `NET_BIND_SERVICE`),
  `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`.
- **Ingress**: Internal-only by default via the internal Traefik instance (IP allowlist).
  Public exposure is opt-in, routed through the external Traefik instance.

Deviations from these defaults are explicit and justified.

## 3. Secrets Never in Git

No plaintext passwords, unencrypted private keys, or API tokens are committed to git.
Only Bitwarden item UUIDs appear in `secrets.yaml` / `values.yaml` — these are not sensitive.
Secrets are delivered to pods via the ExternalSecrets operator, which fetches from Bitwarden at
deploy time. Deletion policy is `Delete`: secrets are cleaned up when the ExternalSecret is removed.

Encrypted keys (e.g. PBES2 with strong parameters) may go in git as a last resort when there is
no practical alternative, but this is the exception.

## 4. Defense in Depth

No single control is relied upon. Security is layered:

| Layer | Mechanism | Applies to |
|-------|-----------|------------|
| Network traffic | Cilium CiliumNetworkPolicy (L3/L4/L7) | All pods |
| Internal access control | Traefik IP allowlist middleware | Internal services |
| External attack detection | CrowdSec + Traefik-external bouncer | Public services |
| Security headers | Traefik-external entrypoint defaults (HSTS, X-Frame-Options) | External routes |
| Rate limiting | Traefik-external | Public routes |
| Internal TLS | step-ca + cert-manager (`*.svc.elda` domains) | Internal services |
| External TLS | Let's Encrypt via cert-manager | Public services |
| Secrets management | ExternalSecrets + Bitwarden | All secrets |
| Storage encryption | Longhorn LUKS | Sensitive PVCs |

## 5. Determinism / Pinned Versions

Helm chart versions are always pinned explicitly (never `*` or floating ranges). Container image
tags are pinned (never `:latest`). Dependency updates are handled by Renovate, which creates
deliberate PRs rather than silent drift. This ensures deployments are reproducible and rollbacks
are predictable.

## 6. Separation of Concerns

Each cross-cutting concern lives in its own file when deploying external Helm charts:

| File | Concern |
|------|---------|
| `app.yaml` / `Chart.yaml` | Chart definition |
| `values.yaml` | Non-sensitive configuration |
| `secrets.yaml` | Secret references (Bitwarden UUIDs) |
| `network.yaml` | Network policies |
| `resources[-env]/` | Environment-specific K8s manifests |

When using the `generic-service` chart, secrets and network policy can be configured directly
in `values.yaml` via the `externalsecrets` and `networkpolicy` subcharts — separate files are
optional in that case.

## 7. Official Charts for Complex Services; generic-service for Simple Services

Well-maintained official Helm charts are preferred for complex, stateful, or security-critical
services (cert-manager, cloudnative-pg, authentik, CrowdSec, Longhorn, step-ca). These charts
encode operational knowledge that would be expensive to replicate.

For standard HTTP services — stateless apps, simple daemons, hobby workloads — the in-house
`generic-service` chart is used. It provides secure defaults out of the box (non-root, seccomp,
internal TLS, IP allowlist), reduces boilerplate, and keeps configuration consistent.

## 8. Secure Defaults in generic-service

The `generic-service` chart encodes the security baseline so per-app configs don't need to repeat
it:
- Pod: `runAsNonRoot: true`, UID 1000 / GID 3000, fsGroup 2000, `seccompProfile: RuntimeDefault`
- Container: `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- Ingress: TLS on by default (internal issuer); external ingress disabled by default
- Network: namespace isolation preset available; internal ingress controller access on by default

Overrides exist for apps that genuinely need elevated permissions, but they must be explicit.

## 9. Network Segmentation via Labels

Cross-namespace service-to-service access uses custom pod labels as network handles rather than
broad namespace-level or CIDR-based rules:

- `custom.network/postgresdb: egress` — pods that need outbound access to the database tier
- `custom.network/external-ingress: ingress` — pods that accept traffic from the external ingress
- `custom.network/homeassistant-integrated: egress` — IoT integration tier

This avoids granting overly broad network access while keeping policies legible.
`toFQDNs` is preferred over `toWorld` for any external egress that can be scoped to known hostnames.

## 10. Environment Parity

Applications that only run in production, or where the default config is correct for both
environments, use a single `values.yaml`. Environment-specific overrides (`values-{env}.yaml`,
`secrets-{env}.yaml`) are added only when values genuinely differ between clusters.

The test cluster is primarily used to validate cluster-level infrastructure, not to mirror every
production app. Not every service needs a test instance.

## 11. Encrypted Storage at Rest

Sensitive PVCs (e.g. Longhorn volumes for private keys, media) use LUKS block encryption
(`aes-xts-plain64` + `argon2i` PBKDF). Encryption keys are sourced from Bitwarden at runtime —
they are never stored unencrypted in git or on the host filesystem.
