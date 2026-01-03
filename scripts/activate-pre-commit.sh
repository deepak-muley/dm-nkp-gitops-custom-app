#!/bin/bash
# Helper script to activate the pre-commit virtual environment
# Usage: source scripts/activate-pre-commit.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    echo "Please run: ./scripts/setup-pre-commit.sh first"
    return 1 2>/dev/null || exit 1
fi

source "$VENV_DIR/bin/activate"
echo "✓ Pre-commit virtual environment activated"
echo "  Run 'deactivate' to exit"
