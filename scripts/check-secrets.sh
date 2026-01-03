#!/bin/bash
# Script to check for accidentally committed secrets or private keys
# This script should be run in CI/CD or as a pre-commit hook

set -e

EXIT_CODE=0
FOUND_ISSUES=0

echo "Checking for accidentally committed secrets and private keys..."

# Check for common private key file patterns
KEY_PATTERNS=(
    "*.key"
    "*.pem"
    "*.p12"
    "*.pfx"
    "cosign.key"
    "id_rsa"
    "id_ed25519"
    "*.private"
    "*.secret"
)

# Check for files matching key patterns
for pattern in "${KEY_PATTERNS[@]}"; do
    # Use git ls-files to check tracked files
    FILES=$(git ls-files "$pattern" 2>/dev/null || true)
    if [ -n "$FILES" ]; then
        echo "❌ ERROR: Found tracked files matching pattern: $pattern"
        echo "$FILES" | while read -r file; do
            echo "   - $file"
        done
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
        EXIT_CODE=1
    fi
done

# Check for common secret patterns in files
echo ""
echo "Checking for potential secrets in tracked files..."

# Check for cosign private keys in code/docs (should only reference, not contain)
if git grep -l "BEGIN.*PRIVATE KEY" -- '*.key' '*.pem' 2>/dev/null | grep -v ".gitignore" > /dev/null; then
    echo "❌ WARNING: Found files that may contain private keys"
    git grep -l "BEGIN.*PRIVATE KEY" -- '*.key' '*.pem' 2>/dev/null | grep -v ".gitignore"
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
    EXIT_CODE=1
fi

# Check for hardcoded tokens/keys (basic check)
SUSPICIOUS_PATTERNS=(
    "ghp_[A-Za-z0-9]{36}"
    "gho_[A-Za-z0-9]{36}"
    "ghu_[A-Za-z0-9]{36}"
    "ghs_[A-Za-z0-9]{36}"
    "ghr_[A-Za-z0-9]{36}"
    "-----BEGIN.*PRIVATE KEY-----"
    "-----BEGIN RSA PRIVATE KEY-----"
    "-----BEGIN EC PRIVATE KEY-----"
)

for pattern in "${SUSPICIOUS_PATTERNS[@]}"; do
    # Exclude .gitignore, this script, and known safe files
    MATCHES=$(git grep -E "$pattern" -- ':!.gitignore' ':!scripts/check-secrets.sh' ':!docs/*' 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
        echo "⚠️  WARNING: Found potential secrets matching pattern: $pattern"
        echo "$MATCHES" | head -5
        echo "   (showing first 5 matches, check all with: git grep '$pattern')"
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
        # Don't fail on warnings, just alert
    fi
done

# Summary
echo ""
if [ $FOUND_ISSUES -eq 0 ]; then
    echo "✓ No secrets or private keys found in tracked files"
    exit 0
else
    echo "❌ Found $FOUND_ISSUES potential security issue(s)"
    echo ""
    echo "If you find private keys or secrets:"
    echo "1. Remove them from git history: git filter-branch or BFG Repo-Cleaner"
    echo "2. Rotate the compromised keys immediately"
    echo "3. Add patterns to .gitignore"
    echo "4. Store secrets in secure secret management (GitHub Secrets, Vault, etc.)"
    exit $EXIT_CODE
fi

