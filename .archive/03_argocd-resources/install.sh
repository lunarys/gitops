if [ -z "$1" ]; then
  echo "Usage: $0 <test|prod>"
  exit 1
fi

if [ "$1" != "test" ] && [ "$1" != "prod" ]; then
  echo "Error: Invalid environment. Use 'test' or 'prod'."
  exit 1
fi

helm install argocd-apps . --namespace infra-argocd --create-namespace --values values.yaml --values values-"$1".yaml
