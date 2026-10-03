#!/usr/bin/env bash
#
# Prints the kubeconfig the test shard's controller uses to reach the prod
# control plane. Store the output as a Bitwarden secure note and put its item
# ID into values-secrets-test.part.yaml.
#
# Usage: ./mint-test-kubeconfig.sh > kubeconfig.yaml

set -euo pipefail

PROD_KUBECONFIG="${PROD_KUBECONFIG:-$HOME/.kube/config-prod}"
# TODO: placeholder, no prod API VIP yet. Must match values-network-test.part.yaml.
SERVER="${SERVER:-https://10.0.1.40:6443}"
NAMESPACE=kargo
SECRET=kargo-controller-test-token
USER_NAME=kargo-controller-test

kc() { kubectl --kubeconfig "$PROD_KUBECONFIG" -n "$NAMESPACE" "$@"; }

token="$(kc get secret "$SECRET" -o jsonpath='{.data.token}' | base64 -d)"
ca="$(kc get secret "$SECRET" -o jsonpath='{.data.ca\.crt}')"
if [ -z "$token" ] || [ -z "$ca" ]; then
  echo "$NAMESPACE/$SECRET has no token yet -- is testShardIdentity enabled in prod?" >&2
  exit 1
fi

# Fails on TLS if prod's serving certificate doesn't cover $SERVER (k0s:
# spec.api.sans), on 401 if the token is wrong, on 403 if the binding is.
cafile="$(mktemp)"
trap 'rm -f "$cafile"' EXIT
echo "$ca" | base64 -d > "$cafile"
code="$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$cafile" \
  -H "Authorization: Bearer $token" \
  "$SERVER/apis/kargo.akuity.io/v1alpha1/stages?limit=1")"
if [ "$code" != "200" ]; then
  echo "listing Stages as $USER_NAME against $SERVER returned HTTP $code" >&2
  exit 1
fi

cat <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: prod
    cluster:
      server: $SERVER
      certificate-authority-data: $ca
users:
  - name: $USER_NAME
    user:
      token: $token
contexts:
  - name: prod
    context:
      cluster: prod
      user: $USER_NAME
current-context: prod
EOF
