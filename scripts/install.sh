#!/bin/bash
#set -x
set -e
PPD="$(pwd)"

# Default values
DIRECTORY="."
ENVIRONMENT=""
DRY_RUN=false
TEMPLATE_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--directory)
      DIRECTORY="$2"
      shift 2
      ;;
    -e|--env|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --template)
      TEMPLATE_ONLY=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -d, --directory DIR     Directory containing app.yaml (default: current directory)"
      echo "  -e, --env ENVIRONMENT   Environment (test, prod, dev, etc.)"
      echo "      --dry-run           Print the helm command that would be run (don't execute)"
      echo "      --template          Render the Helm chart templates without installing"
      echo "  -h, --help              Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --directory /path/to/app --env test"
      echo "  $0 -d ../myapp -e prod"
      echo "  $0 --env test"
      echo "  $0 --dry-run --env test"
      echo "  $0 --template --env test"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

APPFILE="app.yaml"

cd "$DIRECTORY"

# Check if environment is set, if not ask for confirmation
if [ -z "$ENVIRONMENT" ]; then
  echo "⚠️  No environment specified. This will install using only base values.yaml"
  echo "Available environment files in this directory:"
  for values_file in values-*.yaml; do
    if [ -f "$values_file" ]; then
      env_name=$(basename "$values_file" .yaml | sed 's/values-//')
      echo "  - $env_name (use --env $env_name)"
    fi
  done
  echo
  read -p "Continue without environment-specific values? [y/N]: " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
fi

DIRNAME="$(basename "$(pwd)")"
# Remove numeric prefix if it exists (e.g., 00_cilium -> cilium)
APPNAME="$(echo "$DIRNAME" | sed 's/^[0-9][0-9]*_//')"
#GROUPNAME="$(basename "$(dirname "$(pwd)")" | cut -d_ -f2)"

CHART="$(yq ".helm.chart" "$APPFILE")"
VERSION="$(yq ".helm.version" "$APPFILE")"
REPOSITORY="$(yq ".helm.repo" "$APPFILE")"
if [ "$REPOSITORY" = "null" ] || [ -z "$REPOSITORY" ]; then
  REPOSITORY="oci://registry.gitlab.com/juulun/helm-charts/charts"
fi

# Check for argo settings and use them if available
ARGO_NAMESPACE="$(yq ".argo.namespace" "$APPFILE")"
ARGO_APPNAME="$(yq ".argo.appName" "$APPFILE")"

# Use argo settings if they exist, otherwise use defaults
if [ "$ARGO_NAMESPACE" != "null" ] && [ -n "$ARGO_NAMESPACE" ]; then
  NAMESPACE="$ARGO_NAMESPACE"
else
  NAMESPACE="$APPNAME"
fi

if [ "$ARGO_APPNAME" != "null" ] && [ -n "$ARGO_APPNAME" ]; then
  RELEASE_NAME="$ARGO_APPNAME"
else
  RELEASE_NAME="$APPNAME"
fi

# Build values file options
values_file_option=""

# Add base values.yaml if it exists
if [ -f "$DIRECTORY/values.yaml" ]; then
    values_file_option="-f values.yaml"
fi

# Add environment-specific values file if specified
if [ -n "$ENVIRONMENT" ] && [ -f "$DIRECTORY/values-${ENVIRONMENT}.yaml" ]; then
    values_file_option="$values_file_option -f values-${ENVIRONMENT}.yaml"
fi

if grep -q "^oci://" <<< "$REPOSITORY"; then
  location="${REPOSITORY%/}/$CHART"
else
  location="--repo ${REPOSITORY%/} $CHART"
fi

export KUBECONFIG="$HOME/.kube/config-$ENVIRONMENT"

# --devel when beta chart
if [ "$DRY_RUN" = true ]; then
  echo "Dry run mode - would execute:"
  echo "helm install \"$RELEASE_NAME\" $location --version \"$VERSION\" --create-namespace --namespace \"$NAMESPACE\" $values_file_option"
elif [ "$TEMPLATE_ONLY" = true ]; then
  helm template "$RELEASE_NAME" $location --version "$VERSION" --namespace "$NAMESPACE" $values_file_option
else
  helm upgrade --install "$RELEASE_NAME" $location --version "$VERSION" --create-namespace --namespace "$NAMESPACE" $values_file_option
fi
