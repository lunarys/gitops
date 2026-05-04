# Security Architecture

This document describes the security model for this k8s cluster (k0s + Cilium + Traefik + ArgoCD).

## Security Layers

| Layer | Tool | Status |
|-------|------|--------|
| Network traffic control | Cilium NetworkPolicy | Active |
| Ingress access control | Traefik IP allowlist middleware | Active |
| Attack detection & blocking | CrowdSec + Traefik bouncer | Active |
| SSO / Forward Auth | Authentik | Placeholder — not yet configured |
| Internal TLS | step-ca + cert-manager step-issuer | Active |
| External TLS | cert-manager + Let's Encrypt | Active |
| NetworkPolicy coverage | Kyverno (Audit mode) | Active |

## Access Control Model

### Internal services (default)
All services are internal-only by default. Route via the internal Traefik ingress class (`traefik`) — the IP allowlist (`common-internal-access-allowlist-with-cluster`, covering `10.0.0.0/20` and cluster-internal IPs) is applied automatically as an entrypoint default; no per-ingress annotation needed.
It can be restricted futher (disallow general in-cluster access) by using the `common-internal-access-allowlist` middleware.

### Public services (opt-in)
Route via the external Traefik ingress class (`traefik-external`):

```
ingressClassName: traefik-external
```

The external Traefik instance applies rate limiting, CrowdSec bouncer, GeoBlock, and security headers automatically via entrypoint defaults.

Public services additionally need:
- Authentik forward auth middleware (once configured and if they do not support their own authentication): `traefik-common-authentik-forwardauth@kubernetescrd`
- A Let's Encrypt certificate via `cert-manager.io/cluster-issuer: letsencrypt-prod`

## Adding a New Service

### Internal service (typical case)
1. Use `ingressClassName: traefik` (or the generic-service chart default) — IP allowlist applied automatically
2. Add a `network.yaml` with namespace isolation (or configure via `values.yaml` if using generic-service chart)
3. ArgoCD deploys

### Public service
1. Use `ingressClassName: traefik-external` — rate limiting, CrowdSec, GeoBlock, security headers applied automatically
2. Add Authentik forward auth middleware (after Authentik is live)
3. Add cert-manager TLS annotation: `cert-manager.io/cluster-issuer: letsencrypt-prod`
4. Add `network.yaml` with appropriate egress rules
5. Ensure external access is routed through Traefik (Cloudflare Tunnel or port forward)

## Middleware Reference

| Middleware | Applied by | Purpose |
|-----------|-----------|---------|
| `common-internal-access-allowlist-with-cluster` | internal Traefik (entrypoint default) | IP allowlist (10.0.0.0/20, 192.168.178.0/23 + cluster CIDR) |
| `common-internal-access-allowlist` | internal Traefik (optional, per-ingress) | IP allowlist without cluster CIDR |
| `common-rate-limit` | external Traefik (entrypoint default) | Rate limiting |
| `common-crowdsec-bouncer` | external Traefik (entrypoint default) | CrowdSec IP reputation check |
| `common-region-allowlist` | external Traefik (entrypoint default) | GeoBlock by region |
| `common-security-headers` | external Traefik (entrypoint default) | HSTS, X-Frame-Options, etc. |
| `common-authentik-forwardauth` | per-ingress (protected routes) | Authentik SSO forward auth |

## Certificate Issuers

| Issuer | Use case |
|--------|----------|
| `step-ca-internal` (ClusterIssuer) | Internal TLS for `*.svc.elda` domains |
| `letsencrypt-staging` | Let's Encrypt staging (testing, untrusted certs) |
| `letsencrypt-prod` | Let's Encrypt production (trusted certs for public services) |

## Kyverno Policies

| Policy | Mode | What it checks |
|--------|------|----------------|
| `require-namespace-networkpolicy` | Audit | Every non-system namespace has a CiliumNetworkPolicy |

To switch a policy to Enforce mode, change `validationFailureAction: Audit` → `validationFailureAction: Enforce`.

## Pending / TODO

- [ ] Deploy and configure Authentik (fill in secrets, add forward auth to protected ingresses)
- [ ] Switch Kyverno policies to Enforce once all violations are resolved (`kubectl get clusterpolicyreport -A`)
- [ ] Add network policies for apps that are still missing them
