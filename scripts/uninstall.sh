#!/bin/bash
set -x
PPD="$(pwd)"

ENV=""
DIRECTORY=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--env)
			ENV="$2"
			shift 2
			;;
		-h|--help)
			echo "Usage: $0 [--env ENVIRONMENT] [DIRECTORY]"
			echo ""
			echo "Options:"
			echo "  --env ENV      Use kubeconfig at ~/.kube/config-ENV"
			echo "  -h, --help     Show this help message"
			echo ""
			echo "Arguments:"
			echo "  DIRECTORY      Directory to uninstall from (defaults to current directory)"
			echo ""
			echo "Examples:"
			echo "  $0 --env prod"
			echo "  $0 --env prod /path/to/app"
			echo "  $0 /path/to/app"
			exit 0
			;;
		*)
			DIRECTORY="$1"
			shift
			;;
	esac
done

# Validate directory is provided
if [ -z "$DIRECTORY" ]; then
	DIRECTORY="."
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

cd "$DIRECTORY"

DIRNAME="$(basename "$(pwd)")"
#GROUPNAME="$(basename "$(dirname "$(pwd)")" | cut -d_ -f2)"

helm uninstall "$DIRNAME" --namespace "$DIRNAME"
