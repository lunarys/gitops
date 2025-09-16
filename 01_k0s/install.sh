#!/bin/bash

# Script to install k0s cluster with variant support
# Usage: ./install.sh <variant>
# Examples:
#   ./install.sh test        # Uses k0s-test-cluster.yaml
#   ./install.sh rpi01       # Uses k0s-rpi01-cluster.yaml

set -e

# Check if variant is provided
if [[ -z "$1" ]]; then
    echo "Error: Variant argument is required!"
    echo ""
    echo "Usage: $0 <variant>"
    echo ""
    echo "Available variants:"
    ls k0s-*-cluster.yaml 2>/dev/null | sed 's/k0s-\(.*\)-cluster\.yaml/  \1/' || echo "  No cluster configurations found"
    exit 1
fi

VARIANT="$1"

# Configuration files
CLUSTER_CONFIG="k0s-${VARIANT}-cluster.yaml"
COMMON_CONFIG="k0s-cluster-config.yaml"

# Kubeconfig paths
KUBE_DIR="$HOME/.kube"
KUBECONFIG_FILE="$KUBE_DIR/config-${VARIANT}"
MAIN_KUBECONFIG="$KUBE_DIR/config"

# Check if cluster config exists
if [[ ! -f "$CLUSTER_CONFIG" ]]; then
    echo "Error: Cluster configuration file '$CLUSTER_CONFIG' not found!"
    echo "Available variants:"
    ls k0s-*-cluster.yaml 2>/dev/null | sed 's/k0s-\(.*\)-cluster\.yaml/  \1/' || echo "  No cluster configurations found"
    exit 1
fi

# Check if common config exists
if [[ ! -f "$COMMON_CONFIG" ]]; then
    echo "Error: Common configuration file '$COMMON_CONFIG' not found!"
    exit 1
fi

echo "Installing k0s cluster with variant: $VARIANT"
echo "Using cluster config: $CLUSTER_CONFIG"
echo "Using common config: $COMMON_CONFIG"

# Create kube directory if it doesn't exist
mkdir -p "$KUBE_DIR"

# Apply k0s configuration
echo "Applying k0s configuration..."
k0sctl apply \
    --config "$CLUSTER_CONFIG" \
    --config "$COMMON_CONFIG" \
    --kubeconfig-out "$KUBECONFIG_FILE" \
    "--debug"

echo "Cluster installation completed!"
echo "Kubeconfig saved to: $KUBECONFIG_FILE"

# Update main kubeconfig if it doesn't exist
if [[ ! -f "$MAIN_KUBECONFIG" ]]; then
    echo "Setting $KUBECONFIG_FILE as the main kubeconfig..."
    cp "$KUBECONFIG_FILE" "$MAIN_KUBECONFIG"
    chmod 600 "$MAIN_KUBECONFIG"
    echo "Main kubeconfig updated: $MAIN_KUBECONFIG"
else
    echo ""
    echo "Main kubeconfig already exists."
    read -p "Do you want to merge the new kubeconfig with the existing one? [Y/n]: " -r merge_choice
    merge_choice=${merge_choice:-Y}  # Default to Y if empty
    
    if [[ $merge_choice =~ ^[Yy]$ ]]; then
        echo "Merging kubeconfigs..."
        # Backup existing config
        cp "$MAIN_KUBECONFIG" "$MAIN_KUBECONFIG.backup"
        # Merge configs
        KUBECONFIG="$MAIN_KUBECONFIG:$KUBECONFIG_FILE" kubectl config view --flatten > /tmp/merged-kubeconfig
        mv /tmp/merged-kubeconfig "$MAIN_KUBECONFIG"
        chmod 600 "$MAIN_KUBECONFIG"
        echo "Kubeconfigs merged successfully!"
        echo "Backup saved to: $MAIN_KUBECONFIG.backup"
    else
        echo "Kubeconfig not merged. To use this cluster manually:"
        echo "  export KUBECONFIG=$KUBECONFIG_FILE"
    fi
fi

# Ensure proper permissions on variant-specific kubeconfig
chmod 600 "$KUBECONFIG_FILE"
