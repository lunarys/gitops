# GitOps

## Road to production

- [ ] cert-manager
- [ ] replicated storage
- [ ] node local storage
- [ ] replicated database
  - [Bitnami / MariaDB](https://github.com/bitnami/charts/tree/main/bitnami/mariadb-galera)?
- [ ] backup
  - [Velero](https://velero.io/)?
- [ ] network security
- [ ] k8s resource permissions
- [ ] external secrets
- [ ] base settings / owasp

### Helm Chart features

- [ ] internal / external access
- [ ] host + cert
- [ ] service kind / ip address
- [ ] persistent storage
- [ ] database

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

### Secrets

- [ ] [External secrets](https://external-secrets.io/latest/provider/bitwarden-secrets-manager/)
