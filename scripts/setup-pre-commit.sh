#!/bin/bash
# Setup script for pre-commit hooks using Python virtual environment
# This script creates a venv, installs pre-commit, and sets up hooks
# without polluting the system Python installation

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv"
PRE_COMMIT_CONFIG="$REPO_ROOT/.pre-commit-config.yaml"

echo "Setting up pre-commit hooks with Python virtual environment..."
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed"
    echo "Please install Python 3 to use pre-commit hooks"
    exit 1
fi

# Check Python version (pre-commit requires Python >= 3.8)
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
    echo "Error: Python 3.8 or higher is required"
    echo "Current version: Python $PYTHON_VERSION"
    echo "pre-commit-hooks requires Python >= 3.8"
    echo ""
    echo "Please upgrade Python:"
    echo "  macOS: brew install python@3.11"
    echo "  Linux: sudo apt-get install python3.8 (or higher)"
    echo "  Or download from: https://www.python.org/downloads/"
    exit 1
fi

echo "Python version check: $PYTHON_VERSION (✓ compatible)"

# Check if .pre-commit-config.yaml exists
if [ ! -f "$PRE_COMMIT_CONFIG" ]; then
    echo "Error: .pre-commit-config.yaml not found"
    echo "Expected location: $PRE_COMMIT_CONFIG"
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo "✓ Virtual environment created at: $VENV_DIR"
else
    echo "✓ Virtual environment already exists at: $VENV_DIR"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --quiet --upgrade pip

# Install pre-commit
echo "Installing pre-commit..."
pip install --quiet pre-commit

# Verify installation
if ! command -v pre-commit &> /dev/null; then
    echo "Error: pre-commit installation failed"
    exit 1
fi

echo "✓ pre-commit installed successfully"
echo ""

# Install pre-commit hooks
echo "Installing pre-commit hooks..."
cd "$REPO_ROOT"
pre-commit install

echo ""
echo "✓ Pre-commit hooks installed successfully!"
echo ""

# Show pre-commit version
PRE_COMMIT_VERSION=$(pre-commit --version)
echo "Installed version: $PRE_COMMIT_VERSION"
echo ""

# Instructions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Setup complete!"
echo ""
echo "Usage Instructions:"
echo ""
echo "1. Activate the virtual environment (before using pre-commit):"
echo "   source .venv/bin/activate"
echo ""
echo "2. Run pre-commit on staged files:"
echo "   pre-commit run"
echo ""
echo "3. Run pre-commit on all files:"
echo "   pre-commit run --all-files"
echo ""
echo "4. Update hooks (when .pre-commit-config.yaml changes):"
echo "   pre-commit autoupdate"
echo ""
echo "5. Deactivate virtual environment (when done):"
echo "   deactivate"
echo ""
echo "Note: The virtual environment is located at:"
echo "   $VENV_DIR"
echo ""
echo "Tip: Add this to your .gitignore (if not already there):"
echo "   .venv/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

