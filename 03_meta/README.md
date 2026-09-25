Meta-declarations for Argo and Kargo themselves:

    01_app_of_apps  The Argo CD app-of-apps that deploys other Applications
                    (argocd-apps, bootstrap-argo-resources). Argo CD
                    resources only, hand-applied per cluster.
    02_kargo_meta   The Kargo Project that renders per-app Applications and
                    Kargo Projects onto the stage branches.
    03_apps_kargo   The Argo-side counterpart to 02_kargo_meta: reconciles
                    the per-app Kargo control-plane objects it renders.
    04_app_of_meta  The Argo Application that self-manages the three above.

None of these are updated or rendered by Kargo.
Argo directly deploys these.
