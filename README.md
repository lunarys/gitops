# GitOps

## Road to production

- [ ] cert-manager
- [ ] replicated storage
- [ ] node local storage 
  - [HwameiStor](https://hwameistor.io/)?
- [ ] replicated database
  - [Bitnami / MariaDB](https://github.com/bitnami/charts/tree/main/bitnami/mariadb-galera)?
  - cloudnative-pg?
- [ ] backup
  - [Velero](https://velero.io/)?
    - [Velero UI](https://github.com/otwld/velero-ui)?`
  - VolumeSnapshot?
  - Longhorn internal?
- [ ] network security
- [ ] k8s resource permissions
- [x] external secrets
- [ ] base settings / owasp
- [ ] ArgoCD source hydrator?
- [ ] ArgoCD - App of apps as helm -> templating via values.yaml and all apps in /templates
- [ ] Clean up PVCs: Retain leaves pvcs around, but Delete removes also the data (local-path-provisioner)
- [ ] Pod Security Standards?
  - https://docs.k0sproject.io/stable/podsecurity/
  - https://kubernetes.io/docs/concepts/security/pod-security-standards/

### Helm Chart features

- [ ] internal / external access
- [ ] host + cert
- [ ] service kind / ip address
- [ ] persistent storage
- [ ] database
- [ ] external secrets

## Potential components

### Security

- [ ] [cert-manager](https://github.com/bitnami/charts/tree/main/bitnami/cert-manager)
- [ ] Admission controller

#### Security - Addons

- [ ] [trivy security scan](https://github.com/aquasecurity/trivy-operator)
- [ ] [crowdsec security](https://www.crowdsec.net/)
- [ ] [traefik modsecurity](https://plugins.traefik.io/plugins/628c9eadffc0cd18356a9799/modsecurity-plugin)

### Network

- [x] [Cilium + Hubble](https://github.com/networkpolicy/tutorial?tab=readme-ov-file)
- [ ] Default network policies

### Secrets

- [x] [External secrets](https://external-secrets.io/latest/provider/bitwarden-secrets-manager/)
