#!/bin/bash
set -x
PPD="$(pwd)"

DIRECTORY="${1:-"."}"
APPFILE="app.yaml"

cd "$DIRECTORY"

DIRNAME="$(basename "$(pwd)")"
GROUPNAME="$(basename "$(dirname "$(pwd)")" | cut -d_ -f2)"

REPOSITORY="$(yq ".helm.repo" "$APPFILE")"
CHART="$(yq ".helm.chart" "$APPFILE")"
VERSION="$(yq ".helm.version" "$APPFILE")"

if [ -f "$DIRECTORY/values.yaml" ]; then
	values_file_option="-f values.yaml"
else
	values_file_option=""
fi

if grep -q "^oci://" <<< "$REPOSITORY"; then
  location="${REPOSITORY%/}/$CHART"
else
  location="--repo ${REPOSITORY%/} $CHART"
fi

# --devel when beta chart
helm install "$DIRNAME" $location --version "$VERSION" --create-namespace --namespace "$GROUPNAME-$DIRNAME" $values_file_option

