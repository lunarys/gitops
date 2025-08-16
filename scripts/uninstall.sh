#!/bin/bash
set -x
PPD="$(pwd)"

DIRECTORY="$1"
APPFILE="app.yaml"

cd "$DIRECTORY"

DIRNAME="$(basename "$(pwd)")"
#GROUPNAME="$(basename "$(dirname "$(pwd)")" | cut -d_ -f2)"

helm uninstall "$DIRNAME" --namespace "$DIRNAME"
