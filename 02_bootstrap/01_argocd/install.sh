ARGOCD_NS='argocd'

if [ -z "$1" ]; then
    echo "ERROR: Enter environment for values file (test/prod)"
    exit 1
else
    VALUES_FILE="values-$1.yaml"
fi

helm dependency update
helm upgrade --install argocd . \
  --namespace "$ARGOCD_NS" \
  --create-namespace \
  -f values.yaml \
  -f "$VALUES_FILE" 
