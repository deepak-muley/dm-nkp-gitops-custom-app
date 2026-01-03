#!/bin/bash
set -euo pipefail

# DEPRECATED: This script is deprecated. Use setup-monitoring-helm.sh instead.
# This script now redirects to the Helm-based setup.

echo "⚠️  WARNING: This script is deprecated."
echo "   Please use: ./scripts/setup-monitoring-helm.sh"
echo ""
echo "   Or use the Makefile target: make setup-monitoring-helm"
echo ""
echo "Redirecting to Helm-based setup..."
echo ""

# Redirect to Helm-based setup
exec ./scripts/setup-monitoring-helm.sh "$@"

