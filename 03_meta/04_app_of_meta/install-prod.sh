helm upgrade --install app-of-meta . -f ../../gitops-values.yaml -f values-prod.yaml --kubeconfig ~/.kube/config-prod
