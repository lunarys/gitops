This is the stuff that initially needs to be applied to the cluster for Argo to take over:

- Argo App of apps (+ the argo project)

Argo CD resources only. Nothing here may depend on a CRD that does not exist
yet, which rules out Kargo resources and ExternalSecrets -- both arrive with
`05_apps`.

---

Should bootstrap all locations that spawn apps (from _rendered):

    - bootstrap-apps (combine with above?)
    - gitops-apps
    - gitops-private-apps
