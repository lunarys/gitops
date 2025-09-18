NAMESPACE='traefik'

if [ -z "$1" ]; then
    echo "ERROR: Enter environment for values file (test/prod)"
    exit 1
else
    VALUES_FILE="values-$1.yaml"
fi

helm dependency update
helm upgrade --install traefik . \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f values.yaml \
  -f "$VALUES_FILE" 


# Apply internal access allowlist middleware
if [[ -d "resources" ]]; then
    kubectl apply -n "$NAMESPACE" -f resources
fi
