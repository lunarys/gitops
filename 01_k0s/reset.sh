#!/bin/bash

# Script to reset k0s cluster with variant support
# Usage: ./reset.sh <variant>
# Examples:
#   ./reset.sh test        # Uses k0s-test-cluster.yaml
#   ./reset.sh rpi01       # Uses k0s-rpi01-cluster.yaml

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

echo "Resetting k0s cluster with variant: $VARIANT"
echo "Using cluster config: $CLUSTER_CONFIG"
echo "Using common config: $COMMON_CONFIG"

# Confirm before reset
read -p "Are you sure you want to reset the cluster? This will destroy all data! [y/N]: " -r confirm
confirm=${confirm:-N}

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Reset cancelled."
    exit 0
fi

echo "Resetting cluster..."
k0sctl reset --config "$CLUSTER_CONFIG" --config "$COMMON_CONFIG" --debug --force

echo "Cluster reset completed!"
