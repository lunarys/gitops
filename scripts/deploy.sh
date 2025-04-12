#!/bin/bash
set -x
PPD="$(pwd)"

DIRECTORY="$1"
APPFILE="app.yaml"

cd "$DIRECTORY"

DIRNAME="$(basename "$(pwd)")"
GROUPNAME="$(basename "$(dirname "$(pwd)")" | cut -d_ -f2)"

REPOSITORY="$(yq ".helm.repo" "$APPFILE")"
CHART="$(yq ".helm.chart" "$APPFILE")"
VERSION="$(yq ".helm.version" "$APPFILE")"

# --devel when beta chart
# TODO: missing values file
helm install "$DIRNAME" --repo "${REPOSITORY%/}" "$CHART" --version "$VERSION" --create-namespace --namespace "$GROUPNAME-$DIRNAME"

