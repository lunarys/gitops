#!/bin/bash

set -e

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if environment parameter is provided
if [ -z "$1" ]; then
    echo "❌ Error: Environment parameter is required"
    echo ""
    echo "Usage: $0 <environment>"
    echo "  environment: test, prod, dev, etc."
    echo ""
    echo "Examples:"
    echo "  $0 test"
    echo "  $0 prod"
    echo ""
    echo "Available bootstrap components:"
    for component in "${COMPONENT_ORDER[@]}"; do
        echo "  - $component"
    done
    exit 1
fi

ENVIRONMENT="$1"

# Define components and their arguments
declare -A COMPONENTS=(
    ["00_cilium"]="$ENVIRONMENT"
    ["01_argocd"]="$ENVIRONMENT"
    ["02_manual-secrets"]="--env $ENVIRONMENT"
    ["03_traefik"]="$ENVIRONMENT"
)

# Component order (since associative arrays don't preserve order)
COMPONENT_ORDER=("00_cilium" "01_argocd" "02_manual-secrets" "03_traefik")

echo "🚀 Starting bootstrap process for environment: $ENVIRONMENT"
echo "=================================================="
echo

# Function to run install in a directory
install_component() {
    local component="$1"
    shift  # Remove component name from arguments
    local args=("$@")  # Remaining arguments for the component
    local dir="$SCRIPT_DIR/$component"
    
    echo "📦 Installing component: $component"
    echo "   Directory: $dir"
    if [ ${#args[@]} -gt 0 ]; then
        echo "   Arguments: ${args[*]}"
    else
        echo "   Arguments: none"
    fi
    
    # Check if component directory exists
    if [ ! -d "$dir" ]; then
        echo "   ❌ Error: Directory $dir does not exist"
        exit 1
    fi
    
    # Check if component has install.sh
    if [ -f "$dir/install.sh" ]; then
        echo "   Using local install.sh"
        cd "$dir"
        if [ ${#args[@]} -gt 0 ]; then
            bash ./install.sh "${args[@]}"
        else
            bash ./install.sh
        fi
        cd "$SCRIPT_DIR"  # Return to bootstrap directory
    else
        echo "   ❌ Error: No install.sh found in $dir"
        echo "   Each component directory must have its own install.sh script"
        exit 1
    fi
    
    echo "   ✅ $component completed"
    echo
}

# Get all numbered directories and sort them
components=("${COMPONENT_ORDER[@]}")

# Sort components by their numeric prefix
sorted_components=("${components[@]}")

echo "Found ${#sorted_components[@]} components to install:"
for component in "${sorted_components[@]}"; do
    args="${COMPONENTS[$component]}"
    if [ -n "$args" ]; then
        echo "  - $component (args: $args)"
    else
        echo "  - $component (no args)"
    fi
done
echo

# Ask for confirmation
read -p "Continue with bootstrap installation? [Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Bootstrap cancelled."
    exit 0
fi

echo "Starting installation..."
echo

# Install each component in order
for component in "${sorted_components[@]}"; do
    args="${COMPONENTS[$component]}"
    if [ -n "$args" ]; then
        install_component "$component" $args  # Don't quote to allow multiple args
    else
        install_component "$component"
    fi
done

echo "🎉 Bootstrap completed successfully for environment: $ENVIRONMENT"
echo "=================================================="
echo
echo "Next steps:"
echo "1. Verify all components are running: kubectl get pods -A"
echo "2. Check ArgoCD status: kubectl get pods -n argocd"
echo "3. Deploy applications: cd ../03_apps && helm install ..."
