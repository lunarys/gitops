# GitOps Repository Guide for AI Agents

This document describes the structure and patterns used in this GitOps repository for Kubernetes deployments via ArgoCD.

## Repository Structure

This gitops repo works alongside a separate `helm-charts` repo:

```
k8s/                             # Parent directory
├── gitops/                      # This repository
│   ├── 01_k0s/                  # k0s cluster configuration and scripts
│   ├── 02_bootstrap/            # Core components (cilium, argocd, traefik) + manual secrets
│   │   ├── apps-<env>.yaml      # `enabled:` list of bootstrap components to render
│   │   └── <NN_component>/      # Chart.yaml, values*.yaml, settings.yaml, resources*/
│   ├── 03_meta/                 # Argo CD / Kargo self-configuration (see 03_meta/README.md)
│   ├── 04_apps_generator/       # Chart generating per-app Argo Applications/Projects and Kargo
│   │                            # Projects/Warehouses/Stages (see 04_apps_generator/README.md)
│   ├── 05_apps/                 # Application definitions
│   │   ├── apps-<env>.yaml      # `enabled:` list -- only listed apps are rendered per environment
│   │   └── <app-name>/
│   │       ├── Chart.yaml                  # Helm chart; dependencies pull in the real chart(s)
│   │       ├── settings.yaml               # optional per-app generator settings
│   │       ├── values.yaml                 # base values
│   │       ├── values-<env>.yaml           # environment overlay
│   │       ├── values-<label>.part.yaml    # values fragment (network, secrets, ...)
│   │       ├── values-<label>-<env>.part.yaml
│   │       └── resources[-<env>]/          # additional plain K8s manifests
│   ├── gitops-values.yaml       # Repository-wide settings shared by the 03_meta / 04 charts
│   └── scripts/                 # Utility scripts
│
└── helm-charts/                 # Separate repository (custom Helm charts)
    ├── templates/               # generic-service chart templates (Deployment, Service, etc.)
    ├── values.yaml              # generic-service default values
    └── charts/                  # Subcharts
        └── externalsecrets/     # ExternalSecrets subchart for Bitwarden integration
```

Flow: Kargo watches `05_apps` / `02_bootstrap`, the generator pre-renders each app to plain
manifests onto the `stage/<env>` branches via a promotion pull request, and Argo CD syncs those
rendered directories. Argo no longer renders Helm itself.

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

Every app is a directory containing a `Chart.yaml` (there is no `app.yaml` any more). To deploy
an external chart, declare it as a dependency:
```yaml
apiVersion: v2
name: <app>
type: application
version: 0.1.0
dependencies:
  - name: <chart-name>
    version: <version>
    repository: <repository-url>   # https:// or oci://
    # alias: <name>                # moves the values key if needed
```
Values for the dependency go under its chart name (or alias) in `values.yaml`.

Helper charts (`externalsecrets`, `networkpolicy`, `generic-service`, ...) are plain
dependencies too, pinned **per app**; there is no global chart version any more.
Renovate bumps them through the Helm dependency manager.

Local templates (`templates/`) can sit next to the dependencies in the same chart when needed.

### Values files

Detected by filename (`04_apps_generator/templates/_scan.tpl`); a `.yaml` that matches none of
these is an error, not ignored:

| File | Meaning |
|------|---------|
| `values.yaml` | base, always first |
| `values-<env>.yaml` | environment overlay (`test` / `prod`) |
| `values-<label>.part.yaml` | fragment, e.g. `values-network.part.yaml` (`networkpolicy:`), `values-secrets.part.yaml` (`externalsecrets:`) |
| `values-<label>-<env>.part.yaml` | environment variant of a fragment |

### Enabling an app

Add it to `05_apps/apps-test.yaml` and/or `05_apps/apps-prod.yaml` (`enabled:` list). An app
directory that is not listed is not rendered. Bootstrap components use `02_bootstrap/apps-<env>.yaml`.

### settings.yaml

Optional per-app generator settings (`applicationName`, `additionalNamespaces`, `autoSync`,
`selfHeal`, `prune`, `serverSideApply`, `skipCrds`, `kargo.*`). Defaults live in
`04_apps_generator/values.yaml` (`defaultSettings`).

## ExternalSecrets Pattern (Bitwarden)

### Available ClusterSecretStores
- `bitwarden-login` - Fetches `username` or `password` from login items
- `bitwarden-fields` - Fetches custom fields by name
- `bitwarden-notes` - Fetches the notes field (supports multiline)
- `bitwarden-attachments` - Fetches attachment content (requires Bitwarden Pro)

### Secrets fragment structure
Put this under `externalsecrets:` in `values-secrets.part.yaml` (`values-secrets-<env>.part.yaml` for
per-environment UUIDs):
```yaml
externalsecrets:
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
externalsecrets:
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
externalsecrets:
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
- `values-secrets.part.yaml` / `values-secrets-test.part.yaml` / `values-secrets-prod.part.yaml` - Same pattern for secrets fragments

## Helm Chart Patterns

### step-certificates Chart
- `inject.enabled` and `existingSecrets.enabled` are **mutually exclusive**
- For GitOps: Use `existingSecrets.enabled: true` with pre-created ConfigMaps/Secrets
- ConfigMaps can be stored in `resources/` directory in git
- Secrets should come from ExternalSecrets

### Generic Pattern for External Charts with Secrets
1. Set chart to use existing/external secrets (`existingSecrets.enabled: true` or similar)
2. Create `values-secrets.part.yaml` to define ExternalSecrets from Bitwarden
3. Put non-sensitive config in `values.yaml` or `resources/` ConfigMaps
4. Reference secret names in `values.yaml`

## File Naming Conventions

| File | Purpose |
|------|---------|
| `Chart.yaml` | Helm chart definition; dependencies reference the actual chart(s) |
| `settings.yaml` | Optional per-app generator settings (application name, namespaces, sync options) |
| `values.yaml` | Helm values (non-sensitive) |
| `values-<env>.yaml` | Environment-specific overrides |
| `values-secrets[-<env>].part.yaml` | ExternalSecrets configuration (`externalsecrets:` key) |
| `values-network[-<env>].part.yaml` | CiliumNetworkPolicy via the `networkpolicy` preset chart (`networkpolicy:` key). Alternatively the generic-service chart's built-in `networkpolicy` can be used in `values.yaml`. |
| `resources/*.yaml` | Additional K8s manifests deployed to the cluster |
| `resources-prod/*.yaml` | Production-only additional manifests |
| `resources-test/*.yaml` | Test-only additional manifests |
| `apps-<env>.yaml` | (in `05_apps/` and `02_bootstrap/`) `enabled:` list of apps rendered for that environment |

## Network Policy Pattern

Use `values-network.part.yaml` (key `networkpolicy:`, with the `networkpolicy` chart as a dependency in `Chart.yaml`) with the networkpolicy preset chart for apps that need namespace isolation:

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

Apps without a network policy (in either `values-network.part.yaml` or `values.yaml`) will be flagged by the Kyverno `require-namespace-networkpolicy` ClusterPolicy (Audit mode).

## Env-Specific Resource Directories

For resources that differ per environment (e.g. CA certificates, cluster-specific config), use `resources-prod/` and `resources-test/` instead of `resources/`. The generator (`04_apps_generator`) includes the `resources-<env>` directory matching the environment being rendered.

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
