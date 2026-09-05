#!/bin/bash
#set -x
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PPD="$(pwd)"

# Default values
DIRECTORY="."
ENVIRONMENT=""
PREFIX=""
DRY_RUN=false
TEMPLATE_ONLY=false
UNINSTALL=false
INCLUDE_NETWORK=false
INCLUDE_SECRETS=false
INCLUDE_RESOURCES=false
OVERLAY=""

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
    -p|--prefix)
      PREFIX="$2"
      shift 2
      ;;
    -o|--overlay)
      OVERLAY="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --experimental)
      EXPERIMENTAL_HELM_CHART=true
      echo "⚠️  Using local, experimental Helm chart version!"
      shift
      ;;
    --template)
      TEMPLATE_ONLY=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    --include-network)
      INCLUDE_NETWORK=true
      shift
      ;;
    --include-secrets)
      INCLUDE_SECRETS=true
      shift
      ;;
    --include-resources)
      INCLUDE_RESOURCES=true
      shift
      ;;
    --include-all)
      INCLUDE_NETWORK=true
      INCLUDE_SECRETS=true
      INCLUDE_RESOURCES=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -d, --directory DIR       Directory containing app.yaml (default: current directory)"
      echo "  -e, --env ENVIRONMENT     Environment (test, prod, dev, etc.)"
      echo "  -p, --prefix PREFIX       App file prefix for multi-app directories (e.g. policy-reporter)"
      echo "  -o, --overlay DIR         Render the overlay in DIR: a second release of the same chart,"
      echo "                            with DIR/values.yaml layered on top of the base values"
      echo "      --dry-run             Print the helm command that would be run (don't execute)"
      echo "      --template            Render the Helm chart templates without installing"
      echo "      --uninstall           Uninstall the Helm release"
      echo "      --include-network     Also render/apply network.yaml via the networkpolicy chart"
      echo "      --include-secrets     Also render/apply secrets.yaml via the externalsecrets chart"
      echo "      --include-resources   Also render/apply raw manifests from resources/ and resources-{env}/"
      echo "      --include-all         Shorthand for all three --include-* flags"
      echo "  -h, --help                Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --directory /path/to/app --env test"
      echo "  $0 -d ../myapp -e prod"
      echo "  $0 --env test"
      echo "  $0 --dry-run --env test"
      echo "  $0 --template --env test"
      echo "  $0 --template --include-all --env prod"
      echo "  $0 -d apps/kyverno --prefix policy-reporter --env prod"
      echo "  $0 -d 02_bootstrap/03_traefik --overlay external --env prod"
      echo "  $0 -d apps/kyverno --prefix policy-reporter --env prod --uninstall"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

APPFILE="${PREFIX:+${PREFIX}-}app.yaml"

# --prefix and --overlay both select "which release in this directory", but with opposite
# value semantics: a prefix *replaces* the base values, an overlay *layers* on top of them.
if [ -n "$PREFIX" ] && [ -n "$OVERLAY" ]; then
  echo "Error: --prefix and --overlay are mutually exclusive" >&2
  exit 1
fi
case "$OVERLAY" in
  */*|.|..)
    echo "Error: --overlay must be a single directory name, got '$OVERLAY'" >&2
    exit 1
    ;;
esac

cd "$DIRECTORY"

# An overlay is declared by a hidden .overlay.yaml marker, which carries the release name.
# Hidden, and excluded via .helmignore, because unlike every other file in the directory it
# is metadata for tooling and is never an input to a deployment. The name is never derived
# from the directory name -- it must match the Argo Application that deploys this overlay.
# NOTE: one overlay exists today (traefik-external); revisit before generalizing further.
if [ -n "$OVERLAY" ]; then
  OVERLAY_MARKER="$OVERLAY/.overlay.yaml"
  if [ ! -f "$OVERLAY_MARKER" ]; then
    echo "Error: $DIRECTORY/$OVERLAY_MARKER not found -- '$OVERLAY' is not a declared overlay" >&2
    exit 1
  fi
  OVERLAY_NAME="$(yq -r '.name // ""' "$OVERLAY_MARKER")"
  if [ -z "$OVERLAY_NAME" ]; then
    echo "Error: $DIRECTORY/$OVERLAY_MARKER must declare a 'name'" >&2
    exit 1
  fi
  OVERLAY_NAMESPACE="$(yq -r '.namespace // .name' "$OVERLAY_MARKER")"
fi

# Check if environment is set, if not ask for confirmation (skip for uninstall)
if [ "$UNINSTALL" = false ] && [ -z "$ENVIRONMENT" ]; then
  echo "⚠️  No environment specified. This will install using only base values.yaml"
  echo "Available environment files in this directory:"
  for values_file in ${PREFIX:+${PREFIX}-}values-*.yaml; do
    if [ -f "$values_file" ]; then
      env_name=$(basename "$values_file" .yaml | sed "s/${PREFIX:+${PREFIX}-}values-//")
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

# Build values file options (use relative paths since we've already cd'd into DIRECTORY)
values_file_option=""

# Add base values.yaml if it exists
if [ -f "${PREFIX:+${PREFIX}-}values.yaml" ]; then
    values_file_option="-f ${PREFIX:+${PREFIX}-}values.yaml"
fi

# Add environment-specific values file if specified
if [ -n "$ENVIRONMENT" ] && [ -f "${PREFIX:+${PREFIX}-}values-${ENVIRONMENT}.yaml" ]; then
    values_file_option="$values_file_option -f ${PREFIX:+${PREFIX}-}values-${ENVIRONMENT}.yaml"
fi

# Overlay values layer on top of the base ones, so the order is
# values.yaml -> values-<env>.yaml -> <overlay>/values.yaml -> <overlay>/values-<env>.yaml.
# Note the consequence: the overlay's base values win over the parent's env-specific values.
if [ -n "$OVERLAY" ]; then
    if [ -f "$OVERLAY/values.yaml" ]; then
        values_file_option="$values_file_option -f $OVERLAY/values.yaml"
    fi
    if [ -n "$ENVIRONMENT" ] && [ -f "$OVERLAY/values-${ENVIRONMENT}.yaml" ]; then
        values_file_option="$values_file_option -f $OVERLAY/values-${ENVIRONMENT}.yaml"
    fi
fi

if [ -n "$ENVIRONMENT" ]; then
  export KUBECONFIG="$HOME/.kube/config-$ENVIRONMENT"
fi

if [ -f "$APPFILE" ]; then
  # External chart referenced via app.yaml
  CHART="$(yq ".helm.chart" "$APPFILE")"
  VERSION="$(yq ".helm.version" "$APPFILE")"
  REPOSITORY="$(yq ".helm.repo" "$APPFILE")"
  if [ "$REPOSITORY" = "null" ] || [ -z "$REPOSITORY" ]; then
    REPOSITORY="oci://ghcr.io/lunarys/charts"
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
  elif [ -n "$PREFIX" ]; then
    RELEASE_NAME="$PREFIX"
  else
    RELEASE_NAME="$APPNAME"
  fi

  # An overlay is its own release in its own namespace, both taken from the marker
  if [ -n "$OVERLAY" ]; then
    NAMESPACE="$OVERLAY_NAMESPACE"
    RELEASE_NAME="$OVERLAY_NAME"
  fi

  if [ "$EXPERIMENTAL_HELM_CHART" == "true" ]; then
    helm_charts_dir="$(realpath "$SCRIPT_DIR/../../helm-charts")"
    subchart_dir="$helm_charts_dir/charts/$CHART"
    if [ -d "$subchart_dir" ]; then
      location="$subchart_dir"
    else
      location="$helm_charts_dir"
      values_file_option="-f $helm_charts_dir/values.yaml $values_file_option"
    fi
  elif grep -q "^oci://" <<< "$REPOSITORY"; then
    location="${REPOSITORY%/}/$CHART"
  else
    location="--repo ${REPOSITORY%/} $CHART"
  fi

  # --version is invalid for local directory paths (experimental mode)
  version_flag="--version $VERSION"
  if [ "$EXPERIMENTAL_HELM_CHART" == "true" ]; then
    version_flag=""
  fi

  if [ "$UNINSTALL" = true ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "Dry run mode - would execute:"
      echo "helm uninstall \"$RELEASE_NAME\" --namespace \"$NAMESPACE\""
    else
      helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
    fi
  elif [ "$DRY_RUN" = true ]; then
    echo "Dry run mode - would execute:"
    echo "helm upgrade --install \"$RELEASE_NAME\" $location $version_flag --create-namespace --namespace \"$NAMESPACE\" $values_file_option"
  elif [ "$TEMPLATE_ONLY" = true ]; then
    helm template "$RELEASE_NAME" $location $version_flag --namespace "$NAMESPACE" $values_file_option
  else
    helm upgrade --install "$RELEASE_NAME" $location $version_flag --create-namespace --namespace "$NAMESPACE" $values_file_option
  fi

elif [ -f "Chart.yaml" ]; then
  # Local Helm chart: the directory itself is the chart
  NAMESPACE="$APPNAME"
  RELEASE_NAME="${PREFIX:-$APPNAME}"

  # An overlay is its own release in its own namespace, both taken from the marker
  if [ -n "$OVERLAY" ]; then
    NAMESPACE="$OVERLAY_NAMESPACE"
    RELEASE_NAME="$OVERLAY_NAME"
  fi

  if [ "$UNINSTALL" = true ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "Dry run mode - would execute:"
      echo "helm uninstall \"$RELEASE_NAME\" --namespace \"$NAMESPACE\""
    else
      helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
    fi
  elif [ "$DRY_RUN" = true ]; then
    echo "Dry run mode - would execute:"
    echo "helm dependency build ."
    echo "helm upgrade --install \"$RELEASE_NAME\" . --create-namespace --namespace \"$NAMESPACE\" $values_file_option"
  elif [ "$TEMPLATE_ONLY" = true ]; then
    { helm dependency build . 2>/dev/null || helm dependency update .; } >&2
    helm template "$RELEASE_NAME" . --namespace "$NAMESPACE" $values_file_option
  else
    helm dependency build . 2>/dev/null || helm dependency update .
    helm upgrade --install "$RELEASE_NAME" . --create-namespace --namespace "$NAMESPACE" $values_file_option
  fi

else
  echo "Error: no app.yaml or Chart.yaml found in $(pwd)" >&2
  exit 1
fi

# Additional ArgoCD sources: --include-network, --include-secrets, --include-resources
if [ "$INCLUDE_NETWORK" = true ] || [ "$INCLUDE_SECRETS" = true ] || [ "$INCLUDE_RESOURCES" = true ]; then
  GLOBAL_VALUES="$SCRIPT_DIR/../03_apps/values.yaml"
  if [ ! -f "$GLOBAL_VALUES" ]; then
    echo "Warning: global values.yaml not found at $GLOBAL_VALUES, skipping additional sources" >&2
  else
    MAIN_HELM_REPO="$(yq ".mainHelmRepo" "$GLOBAL_VALUES")"

    # Sidecar sources are taken from the overlay directory ALONE and are never inherited
    # from the parent, mirroring 03_apps/templates/00_traefik-external-application.yaml.
    # Inheriting them would be actively wrong: traefik-external would render the internal
    # instance's permissive network policy instead of its own restrictive one.
    SIDECAR_DIR="."
    if [ -n "$OVERLAY" ]; then
      SIDECAR_DIR="$OVERLAY"
    fi

    if [ "$INCLUDE_NETWORK" = true ]; then
      NETWORK_FILE="$SIDECAR_DIR/${PREFIX:+${PREFIX}-}network.yaml"
      if [ -f "$NETWORK_FILE" ]; then
        NETWORK_CHART="$(yq ".networkPolicyChart" "$GLOBAL_VALUES")"
        _NETWORK_VERSION="$(yq ".version" "$NETWORK_FILE")"
        if [ "$_NETWORK_VERSION" = "null" ] || [ -z "$_NETWORK_VERSION" ]; then
          _NETWORK_VERSION="$(yq ".networkPolicyChartVersion" "$GLOBAL_VALUES")"
        fi
        NETWORK_LOCATION="${MAIN_HELM_REPO%/}/$NETWORK_CHART"
        if [ "$UNINSTALL" = true ]; then
          if [ "$DRY_RUN" = true ]; then
            echo "helm uninstall \"$RELEASE_NAME-network\" --namespace \"$NAMESPACE\""
          else
            helm uninstall "$RELEASE_NAME-network" --namespace "$NAMESPACE" || true
          fi
        elif [ "$DRY_RUN" = true ]; then
          echo "helm upgrade --install \"$RELEASE_NAME-network\" \"$NETWORK_LOCATION\" --version \"$_NETWORK_VERSION\" --namespace \"$NAMESPACE\" -f \"$NETWORK_FILE\""
        elif [ "$TEMPLATE_ONLY" = true ]; then
          helm template "$RELEASE_NAME" "$NETWORK_LOCATION" --version "$_NETWORK_VERSION" --namespace "$NAMESPACE" -f "$NETWORK_FILE"
        else
          helm upgrade --install "$RELEASE_NAME-network" "$NETWORK_LOCATION" --version "$_NETWORK_VERSION" --namespace "$NAMESPACE" -f "$NETWORK_FILE"
        fi
      fi
    fi

    if [ "$INCLUDE_SECRETS" = true ]; then
      SECRETS_FILE="$SIDECAR_DIR/${PREFIX:+${PREFIX}-}secrets.yaml"
      if [ -f "$SECRETS_FILE" ]; then
        SECRETS_CHART="$(yq ".secretsChart" "$GLOBAL_VALUES")"
        _SECRETS_VERSION="$(yq ".version" "$SECRETS_FILE")"
        if [ "$_SECRETS_VERSION" = "null" ] || [ -z "$_SECRETS_VERSION" ]; then
          _SECRETS_VERSION="$(yq ".secretsChartVersion" "$GLOBAL_VALUES")"
        fi
        SECRETS_LOCATION="${MAIN_HELM_REPO%/}/$SECRETS_CHART"
        secrets_values="-f $SECRETS_FILE"
        if [ -n "$ENVIRONMENT" ] && [ -f "$SIDECAR_DIR/${PREFIX:+${PREFIX}-}secrets-${ENVIRONMENT}.yaml" ]; then
          secrets_values="$secrets_values -f $SIDECAR_DIR/${PREFIX:+${PREFIX}-}secrets-${ENVIRONMENT}.yaml"
        fi
        if [ "$UNINSTALL" = true ]; then
          if [ "$DRY_RUN" = true ]; then
            echo "helm uninstall \"$RELEASE_NAME-secrets\" --namespace \"$NAMESPACE\""
          else
            helm uninstall "$RELEASE_NAME-secrets" --namespace "$NAMESPACE" || true
          fi
        elif [ "$DRY_RUN" = true ]; then
          echo "helm upgrade --install \"$RELEASE_NAME-secrets\" \"$SECRETS_LOCATION\" --version \"$_SECRETS_VERSION\" --skip-crds --namespace \"$NAMESPACE\" $secrets_values"
        elif [ "$TEMPLATE_ONLY" = true ]; then
          helm template "$RELEASE_NAME" "$SECRETS_LOCATION" --version "$_SECRETS_VERSION" --skip-crds --namespace "$NAMESPACE" $secrets_values
        else
          helm upgrade --install "$RELEASE_NAME-secrets" "$SECRETS_LOCATION" --version "$_SECRETS_VERSION" --skip-crds --namespace "$NAMESPACE" $secrets_values
        fi
      fi
    fi

    if [ "$INCLUDE_RESOURCES" = true ]; then
      if [ "$UNINSTALL" = true ]; then
        : # No-op: kubectl delete would require knowing resource types/names; handle manually
      elif [ "$DRY_RUN" = true ]; then
        if [ -d "$SIDECAR_DIR/resources" ]; then echo "kubectl apply -f $SIDECAR_DIR/resources/"; fi
        if [ -n "$ENVIRONMENT" ] && [ -d "$SIDECAR_DIR/resources-${ENVIRONMENT}" ]; then
          echo "kubectl apply -f \"$SIDECAR_DIR/resources-${ENVIRONMENT}/\""
        fi
      elif [ "$TEMPLATE_ONLY" = true ]; then
        if [ -d "$SIDECAR_DIR/resources" ]; then
          for f in "$SIDECAR_DIR/resources/"*.yaml; do [ -f "$f" ] && cat "$f"; done
        fi
        if [ -n "$ENVIRONMENT" ] && [ -d "$SIDECAR_DIR/resources-${ENVIRONMENT}" ]; then
          for f in "$SIDECAR_DIR/resources-${ENVIRONMENT}/"*.yaml; do [ -f "$f" ] && cat "$f"; done
        fi
      else
        if [ -d "$SIDECAR_DIR/resources" ]; then kubectl apply -f "$SIDECAR_DIR/resources/"; fi
        if [ -n "$ENVIRONMENT" ] && [ -d "$SIDECAR_DIR/resources-${ENVIRONMENT}" ]; then
          kubectl apply -f "$SIDECAR_DIR/resources-${ENVIRONMENT}/"
        fi
      fi
    fi
  fi
fi
