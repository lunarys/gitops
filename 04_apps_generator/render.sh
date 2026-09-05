#!/usr/bin/env bash
#
# Render the meta resources locally -- the same three renders the platform
# Stages perform in Kargo.
#
# Helm's .Files can only read inside the chart directory, and the apps live in
# a sibling (../05_apps). So this assembles a workspace with the apps copied to
# <chart>/apps/, which is exactly what the promotion's `copy` step does before
# helm-template. Nothing is written to the repository.
#
# Usage: ./render.sh [out-dir]      (default: ./.render, gitignored)

set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$(cd "$CHART_DIR/../05_apps" && pwd)"
OUT="${1:-$CHART_DIR/.render}"

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT

cp -r "$CHART_DIR" "$WS/chart"
rm -rf "$WS/chart/.render" "$WS/chart/templates_old"
cp -r "$APPS_DIR" "$WS/chart/apps"

mkdir -p "$OUT"

render() {
  local name="$1" values="$2" dest="$3"
  printf '%-28s -> %s\n' "$name" "${dest#"$OUT"/}" >&2
  helm template meta "$WS/chart" \
    -f "$WS/chart/values.yaml" \
    -f "$WS/chart/$values" \
    > "$dest"
}

render "argo (test)"  values-argo-test.yaml "$OUT/argo-test.yaml"
render "argo (prod)"  values-argo-prod.yaml "$OUT/argo-prod.yaml"
render "kargo"        values-kargo.yaml     "$OUT/kargo.yaml"

echo >&2
for f in "$OUT"/*.yaml; do
  printf '  %-24s %3s objects\n' "$(basename "$f")" "$(grep -c '^kind:' "$f" || true)" >&2
done
