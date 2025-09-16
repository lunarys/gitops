if [ -z "$1" ]; then
    echo "ERROR: Enter environment for values file (test/prod)"
    exit 1
else
    VALUES_FILE="values-$1.yaml"
fi

helm dependency update
helm upgrade --install cilium . \
  --namespace kube-system \
  -f values.yaml \
  -f "$VALUES_FILE" 

find resources/ resources-$1/ -name "*.yaml" -exec kubectl apply -n kube-system -f {} \;
