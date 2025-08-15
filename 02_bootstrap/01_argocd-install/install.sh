ARGOCD_NS='argocd'

if [ -z "$1" ]; then
    echo "ERROR: Enter environment for values file (test/prod)"
    exit 1
else
    VALUES_FILE="values-$1.yaml"
fi


helm install argocd . \
  --namespace "$ARGOCD_NS" \
  --create-namespace \
  -f values.yaml \
  -f "$VALUES_FILE" 
