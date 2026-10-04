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
      echo "  -d, --directory DIR       App directory: Chart.yaml or app.yaml (default: current directory)"
      echo "  -e, --env ENVIRONMENT     Environment (test, prod, dev, etc.)"
      echo "  -p, --prefix PREFIX       App file prefix for multi-app directories (e.g. policy-reporter)"
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

cd "$DIRECTORY"

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

# Values files, mirroring 04_apps_generator's discovery (templates/_scan.tpl), so a
# local render and a promotion render layer the same files in the same order:
#   values.yaml, values-<label>.part.yaml, values-<env>.yaml, values-<label>-<env>.part.yaml
# each group in byte order. A fragment whose label ends in -<environment> belongs to that
# environment only; the environment names are the generator's.
GENERATOR_ENVS="test prod"
discover_values() {
  local dir="$1" env="$2" f stem e is_env
  local LC_ALL=C
  if [ -f "$dir/values.yaml" ]; then printf '%s\n' "$dir/values.yaml"; fi
  for f in "$dir"/values-*.part.yaml; do
    [ -f "$f" ] || continue
    stem="$(basename "$f" .part.yaml)"
    stem="${stem#values-}"
    is_env=false
    for e in $GENERATOR_ENVS; do
      if [[ "$stem" == *-"$e" ]]; then is_env=true; fi
    done
    if [ "$is_env" = false ]; then printf '%s\n' "$f"; fi
  done
  [ -n "$env" ] || return 0
  if [ -f "$dir/values-$env.yaml" ]; then printf '%s\n' "$dir/values-$env.yaml"; fi
  for f in "$dir"/values-*-"$env".part.yaml; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done
}

# Build values file options (use relative paths since we've already cd'd into DIRECTORY)
values_file_option=""
if [ -n "$PREFIX" ]; then
  # Multi-app directories (<prefix>-app.yaml) predate fragments: base and environment only.
  if [ -f "${PREFIX}-values.yaml" ]; then
    values_file_option="$values_file_option -f ${PREFIX}-values.yaml"
  fi
  if [ -n "$ENVIRONMENT" ] && [ -f "${PREFIX}-values-${ENVIRONMENT}.yaml" ]; then
    values_file_option="$values_file_option -f ${PREFIX}-values-${ENVIRONMENT}.yaml"
  fi
else
  for f in $(discover_values . "$ENVIRONMENT"); do
    values_file_option="$values_file_option -f $f"
  done
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
  # Local Helm chart: the directory itself. Named like the generator names it:
  # settings.yaml applicationName / namespace, else the directory.
  RELEASE_NAME="${PREFIX:-$APPNAME}"
  if [ -z "$PREFIX" ] && [ -f "settings.yaml" ]; then
    RELEASE_NAME="$(yq -r ".applicationName // \"$RELEASE_NAME\"" settings.yaml)"
  fi
  NAMESPACE="$RELEASE_NAME"
  if [ -z "$PREFIX" ] && [ -f "settings.yaml" ]; then
    NAMESPACE="$(yq -r ".namespace // \"$NAMESPACE\"" settings.yaml)"
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
  echo "Error: no Chart.yaml or app.yaml found in $(pwd)" >&2
  exit 1
fi

# Additional ArgoCD sources: --include-network, --include-secrets, --include-resources
if [ "$INCLUDE_NETWORK" = true ] || [ "$INCLUDE_SECRETS" = true ] || [ "$INCLUDE_RESOURCES" = true ]; then
  GLOBAL_VALUES="$SCRIPT_DIR/../03_apps/values.yaml"
  if [ ! -f "$GLOBAL_VALUES" ]; then
    echo "Warning: global values.yaml not found at $GLOBAL_VALUES, skipping additional sources" >&2
  else
    MAIN_HELM_REPO="$(yq ".mainHelmRepo" "$GLOBAL_VALUES")"

    SIDECAR_DIR="."

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
        # Each file as its own document: a bare cat runs the last document of one file
        # into the first of the next, and the diff silently loses objects.
        if [ -d "$SIDECAR_DIR/resources" ]; then
          for f in "$SIDECAR_DIR/resources/"*.yaml; do [ -f "$f" ] && { echo "---"; cat "$f"; echo; }; done
        fi
        if [ -n "$ENVIRONMENT" ] && [ -d "$SIDECAR_DIR/resources-${ENVIRONMENT}" ]; then
          for f in "$SIDECAR_DIR/resources-${ENVIRONMENT}/"*.yaml; do [ -f "$f" ] && { echo "---"; cat "$f"; echo; }; done
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
