#!/bin/bash
set -eo pipefail  # Exit on error, undefined variables, and pipe failures

# This script safely handles passwords and secrets with special characters
# including: $, `, \, ", ', spaces, and other shell metacharacters
# by using temporary files instead of environment variables

SCRIPT_DIR="$(dirname "$0")"
ENV=""
FILES=()

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--env)
			ENV="$2"
			shift 2
			;;
		-h|--help)
			echo "Usage: $0 [--env ENVIRONMENT] [files...]"
			echo ""
			echo "Options:"
			echo "  --env ENV      Use kubeconfig at ~/.kube/config-ENV"
			echo "  -h, --help     Show this help message"
			echo ""
			echo "Examples:"
			echo "  $0 --env prod"
			echo "  $0 --env prod *.yaml"
			echo "  $0 --env test secret.yaml"
			exit 0
			;;
		*)
			FILES+=("$1")
			shift
			;;
	esac
done

# If no files specified, use all yaml files in script directory
if [ ${#FILES[@]} -eq 0 ]; then
	FILES=("$SCRIPT_DIR"/*.yaml)
fi

# Set kubeconfig if environment is specified
if [ -n "$ENV" ]; then
	KUBECONFIG_FILE="$HOME/.kube/config-$ENV"
	if [ ! -f "$KUBECONFIG_FILE" ]; then
		echo "Error: kubeconfig file not found: $KUBECONFIG_FILE"
		exit 1
	fi
	export KUBECONFIG="$KUBECONFIG_FILE"
	echo "Using kubeconfig: $KUBECONFIG_FILE"
fi

for file in "${FILES[@]}"; do
    echo "Processing yaml file: $file"
    manifest="$(yq "$file")"

    # Extract namespace from manifest (defaults to 'default' if not specified)
    namespace="$(echo "$manifest" | yq '.metadata.namespace // "default"')"
    echo "Target namespace: $namespace"

    # Check if namespace exists, create if it doesn't
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        echo "Namespace '$namespace' does not exist. Creating..."
        kubectl create namespace "$namespace"
        echo "Namespace '$namespace' created successfully."
    else
        echo "Namespace '$namespace' already exists."
    fi

	for key in $(echo "$manifest" | yq ".stringData | keys[]"); do
		value="$(echo "$manifest" | yq ".stringData.$key")"

		if [ -z "$value" ]; then
			echo "Enter value for '$key':"
		else
			echo "Enter value for '$key' (default='$value'):"
		fi

		read -r newValue
		#if [ -z "$newValue" ]; then
		#	echo no value
		#else
		#	echo value $newValue
		#fi

		if [ -n "$newValue" ]; then
			# Use a temporary file to safely pass the value to yq
			# This completely avoids shell interpretation of special characters
			tmpfile=$(mktemp)
			trap 'rm -f "$tmpfile"' EXIT  # Ensure cleanup on script exit
			printf '%s' "$newValue" > "$tmpfile"
			manifest="$(echo "$manifest" | yq ".stringData.$key = load_str(\"$tmpfile\")")"
			rm -f "$tmpfile"
		fi
	done

	echo "New manifest:"
	echo "---"
	echo "$manifest" | yq
	echo "---"

	echo "Apply manifest? (Y/n)"
	read -r confirmation
	if [ -z "$confirmation" ] || [ "$confirmation" == "y" ] || [ "$confirmation" == "Y" ]; then
		echo "Applying manifest for $file..."
		echo "$manifest" | kubectl apply -f -
	else
		echo "WARN: Not applying manifest for $file"
	fi
done
