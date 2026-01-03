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

# Function to check Python version
check_python_version() {
    local python_cmd="$1"
    if ! command -v "$python_cmd" &> /dev/null; then
        return 1
    fi
    local version
    local major
    local minor
    version=$("$python_cmd" --version 2>&1 | awk '{print $2}')
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    if [ "$major" -ge 3 ] && [ "$minor" -ge 8 ]; then
        echo "$version"
        return 0
    fi
    return 1
}

# Try to find a compatible Python version
PYTHON_CMD="python3"
PYTHON_VERSION=""

# First, try the default python3
if version=$(check_python_version "python3"); then
    PYTHON_VERSION="$version"
    echo "Found compatible Python: python3 ($PYTHON_VERSION)"
else
    # Try common Homebrew Python locations (macOS)
    echo "Default python3 is too old, searching for newer version..."
    for python_path in \
        "/usr/local/opt/python@3.14/bin/python3" \
        "/opt/homebrew/opt/python@3.14/bin/python3" \
        "/usr/local/opt/python@3.12/bin/python3" \
        "/opt/homebrew/opt/python@3.12/bin/python3" \
        "/usr/local/opt/python@3.11/bin/python3" \
        "/opt/homebrew/opt/python@3.11/bin/python3" \
        "/usr/local/opt/python@3.10/bin/python3" \
        "/opt/homebrew/opt/python@3.10/bin/python3" \
        "/usr/local/opt/python@3.9/bin/python3" \
        "/opt/homebrew/opt/python@3.9/bin/python3" \
        "/usr/local/opt/python@3.8/bin/python3" \
        "/opt/homebrew/opt/python@3.8/bin/python3" \
        "/usr/bin/python3"; do
        if [ -f "$python_path" ] && version=$(check_python_version "$python_path"); then
            PYTHON_CMD="$python_path"
            PYTHON_VERSION="$version"
            echo "Found compatible Python: $python_path ($PYTHON_VERSION)"
            break
        fi
    done
fi

# If still no compatible Python found, show error
if [ -z "$PYTHON_VERSION" ]; then
    echo "Error: Python 3.8 or higher is required"
    echo "Current default version: $(python3 --version 2>&1 | awk '{print $2}')"
    echo "pre-commit-hooks requires Python >= 3.8"
    echo ""
    echo "Please install a newer Python version:"
    echo "  macOS: brew install python@3.11"
    echo "  Linux: sudo apt-get install python3.8 (or higher)"
    echo "  Or download from: https://www.python.org/downloads/"
    exit 1
fi

echo "Using Python: $PYTHON_CMD ($PYTHON_VERSION)"

# Check if .pre-commit-config.yaml exists
if [ ! -f "$PRE_COMMIT_CONFIG" ]; then
    echo "Error: .pre-commit-config.yaml not found"
    echo "Expected location: $PRE_COMMIT_CONFIG"
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    "$PYTHON_CMD" -m venv "$VENV_DIR"
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
