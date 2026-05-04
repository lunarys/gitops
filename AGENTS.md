# GitOps Repository Guide for AI Agents

This document describes the structure and patterns used in this GitOps repository for Kubernetes deployments via ArgoCD.

## Repository Structure

This gitops repo works alongside a separate `helm-charts` repo:

```
k8s/                             # Parent directory
├── gitops/                      # This repository
│   └── 03_apps/
│       ├── apps/                # Application definitions
│       │   └── <app-name>/
│       │       ├── app.yaml     # Helm chart reference (external charts)
│       │       ├── Chart.yaml   # Local chart definition (alternative to app.yaml)
│       │       ├── values.yaml  # Helm values
│       │       ├── secrets.yaml # ExternalSecrets configuration
│       │       └── resources/   # Additional K8s manifests (ConfigMaps, etc.)
│       ├── charts/
│       │   └── application-wrapper/  # ArgoCD Application generator
│       └── values.yaml          # Global defaults (externalsecrets version, etc.)
│
└── helm-charts/                 # Separate repository (custom Helm charts)
    ├── templates/               # generic-service chart templates (Deployment, Service, etc.)
    ├── values.yaml              # generic-service default values
    └── charts/                  # Subcharts
        └── externalsecrets/     # ExternalSecrets subchart for Bitwarden integration
```

This structure depends on the actual way repositories were checked out. This is the recommended way though.

## helm-charts Repository

The `helm-charts` repo contains custom Helm charts used by applications in this gitops repo:

- **generic-service** (root chart) - A reusable chart for deploying services with Deployments, Services, Ingress, etc.

Subcharts in `charts/`:
- **externalsecrets** - Generates ExternalSecret resources for pulling secrets from Bitwarden
- **generic-cronjob** - CronJob resource generation
- **autoscale** - HorizontalPodAutoscaler configuration
- **networkpolicy** - NetworkPolicy resource generation
- **localstorage** - Local PersistentVolume/PVC provisioning
- **longhornstorage** - Longhorn-based PersistentVolumeClaim provisioning
- **smbstorage** - SMB/CIFS-based storage provisioning

Applications can reference these charts or use external charts from public repositories.

## Application Definition Patterns

### External Helm Charts
For charts from external repositories, create `app.yaml`:
```yaml
helm:
  chart: <chart-name>
  version: <version>
  repo: <repository-url>
```

### Local Helm Charts
Use `Chart.yaml` instead of `app.yaml` only when custom templates are required or multiple Helm charts need to be combined as dependencies. For everything else, prefer the simpler `app.yaml` form.

## ExternalSecrets Pattern (Bitwarden)

### Available ClusterSecretStores
- `bitwarden-login` - Fetches `username` or `password` from login items
- `bitwarden-fields` - Fetches custom fields by name
- `bitwarden-notes` - Fetches the notes field (supports multiline)
- `bitwarden-attachments` - Fetches attachment content (requires Bitwarden Pro)

### secrets.yaml Structure
```yaml
secrets:
  <kubernetes-secret-name>:
    commonRemoteKey: "<bitwarden-item-uuid>"  # Default UUID for all fields
    fields:
      <field-name>:
        storeRefName: bitwarden-login|bitwarden-fields|bitwarden-notes
        remoteProperty: username|password|<field-name>  # Property to fetch
        remoteKey: "<uuid>"  # Override commonRemoteKey for this field
```

### Bitwarden Free Tier Limitations
- **No attachments** - Use Secure Notes with the notes field for multiline content
- **Fields don't support multiline** - Use notes field instead
- **One notes field per item** - Create separate items for multiple multiline values

### Pattern for Multiline Secrets (Free Tier)
Create separate Bitwarden Secure Note items, each with content in the notes field:
```yaml
secrets:
  my-secret:
    fields:
      multiline-content:
        storeRefName: bitwarden-notes
        remoteKey: "<secure-note-uuid>"
```

### Pattern for Passwords
Use a Login item with password field and custom fields:
```yaml
secrets:
  password-secret:
    commonRemoteKey: "<login-item-uuid>"
    fields:
      password:
        storeRefName: bitwarden-login
        remoteProperty: password
      other-secret:
        storeRefName: bitwarden-fields
        remoteProperty: <custom-field-name>
```

## Environment-Specific Overrides

Files can have environment suffixes:
- `values.yaml` - Base values
- `values-test.yaml` - Test environment overrides
- `values-prod.yaml` - Production environment overrides
- `secrets.yaml` / `secrets-test.yaml` / `secrets-prod.yaml` - Same pattern for secrets

## Helm Chart Patterns

### step-certificates Chart
- `inject.enabled` and `existingSecrets.enabled` are **mutually exclusive**
- For GitOps: Use `existingSecrets.enabled: true` with pre-created ConfigMaps/Secrets
- ConfigMaps can be stored in `resources/` directory in git
- Secrets should come from ExternalSecrets

### Generic Pattern for External Charts with Secrets
1. Set chart to use existing/external secrets (`existingSecrets.enabled: true` or similar)
2. Create `secrets.yaml` to define ExternalSecrets from Bitwarden
3. Put non-sensitive config in `values.yaml` or `resources/` ConfigMaps
4. Reference secret names in `values.yaml`

## File Naming Conventions

| File | Purpose |
|------|---------|
| `app.yaml` | External Helm chart reference |
| `Chart.yaml` | Local Helm chart definition |
| `values.yaml` | Helm values (non-sensitive) |
| `secrets.yaml` | ExternalSecrets configuration |
| `network.yaml` | CiliumNetworkPolicy via the networkpolicy preset chart (separate from the app). Alternatively the generic-service chart's built-in `networkPolicy` can be used in `values.yaml`. |
| `resources/*.yaml` | Additional K8s manifests deployed to the cluster |
| `resources-prod/*.yaml` | Production-only additional manifests |
| `resources-test/*.yaml` | Test-only additional manifests |
| `*-test.yaml` / `*-prod.yaml` | Environment-specific overrides |

## Network Policy Pattern

Use `network.yaml` with the networkpolicy preset chart for apps that need namespace isolation:

```yaml
preset:
  namespaceIsolation: true   # allow same-namespace traffic by default
  ingress:
    fromIngressController: true  # default: Traefik can reach the app
    fromKubeApi: true            # if app registers admission webhooks
  egress:
    toKubeApi: true              # if app talks to k8s API
    toFQDNs:                     # specific external hosts (preferred over toWorld)
      - api.example.com
    toWorld: true                # broad internet access (avoid unless needed)
```

Apps without a network policy (in either `network.yaml` or `values.yaml`) will be flagged by the Kyverno `require-namespace-networkpolicy` ClusterPolicy (Audit mode).

## Env-Specific Resource Directories

For resources that differ per environment (e.g. CA certificates, cluster-specific config), use `resources-prod/` and `resources-test/` instead of `resources/`. The application-wrapper automatically adds the env-specific path source based on the `environment` value in the cluster's values file.

Example: `step-ca/resources-prod/` contains prod CA certs; a `resources-test/` directory would contain test CA certs.

## Ingress Access Control

Internal services use `ingressClassName: traefik` — the IP allowlist (`common-internal-access-allowlist-with-cluster`) is applied automatically via Traefik entrypoint defaults; no per-ingress annotation needed.

Public services use `ingressClassName: traefik-external` — rate limiting, CrowdSec bouncer, GeoBlock, and security headers are applied automatically via entrypoint defaults.


## Security Guidelines

### What CAN go in git
- Public certificates
- Non-sensitive configuration (URLs, ports, policies)
- Encrypted keys (if encryption is strong, e.g., PBES2 with high iterations)
- Bitwarden item UUIDs (not sensitive)
- Helm values referencing secret names

### What MUST NOT go in git
- Plaintext passwords
- Unencrypted private keys
- API tokens/keys
- Personal information (emails, names) - use internal domains instead

## Reference Applications

Good examples to follow:
- `longhorn/` - Simple ExternalSecrets with environment-specific UUIDs
- `crowdsec/` - Multiple secrets with field mappings (bitwarden-fields + bitwarden-login)
- `step-ca/` - ConfigMaps in git + Secrets via ExternalSecrets pattern
