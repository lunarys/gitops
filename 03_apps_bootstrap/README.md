This is the stuff that initially needs to be applied to the cluster for Argo to take over:

- Argo App of apps (+ the argo project)


Argo CD resources only. Nothing here may depend on a CRD that does not exist
yet, which rules out Kargo resources and ExternalSecrets -- both arrive with
`05_apps`. The Kargo flow that keeps the app of apps updated lives in
`06_apps_kargo`.
