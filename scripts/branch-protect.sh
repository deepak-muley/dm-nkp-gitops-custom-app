#!/bin/bash
# Script to check and set up branch protection for any branch
# Usage:
#   ./branch-protect.sh [--show] [REPO_PATH] [--branch BRANCH]
#   ./branch-protect.sh --setup [REPO_PATH] [--branch BRANCH]
# Examples:
#   ./branch-protect.sh --show                                    # Show default repo/branch
#   ./branch-protect.sh --show kubernetes/kubernetes              # Show another repo
#   ./branch-protect.sh --show kubernetes/kubernetes --branch main
#   ./branch-protect.sh --setup                                   # Setup default repo/branch
#   ./branch-protect.sh --setup user/repo --branch main          # Setup specific repo/branch

set -e

# Default values
REPO="deepak-muley/dm-nkp-gitops-custom-app"
BRANCH="master"
MODE="show"  # Default to show mode

# Default protection rules that --setup would apply
SETUP_RULES=(
    "Required PR reviews: 0 approvals (solo developer)"
    "Dismiss stale reviews: Yes"
    "Require code owner reviews: No"
    "Required status checks: Yes (strict mode)"
    "Require conversation resolution: Yes"
    "Enforce admins: No (admins can bypass for PR updates)"
    "Allow force pushes: No"
    "Allow deletions: No"
    "Lock branch: No"
    "Block creations: No"
)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --setup)
            MODE="setup"
            shift
            ;;
        --show)
            MODE="show"
            shift
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [REPO_PATH]"
            echo ""
            echo "Options:"
            echo "  --show                 Show protection status (default, read-only)"
            echo "  --setup                Set up branch protection (requires write access)"
            echo "  --branch BRANCH        Branch to check/setup (default: master)"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Arguments:"
            echo "  REPO_PATH              Repository path in format owner/repo (optional)"
            echo ""
            echo "Examples:"
            echo "  $0 --show                                    # Show default repo/branch"
            echo "  $0 --show kubernetes/kubernetes              # Show another repo"
            echo "  $0 --show kubernetes/kubernetes --branch main"
            echo "  $0 --setup                                   # Setup default repo/branch"
            echo "  $0 --setup user/repo --branch main           # Setup specific repo/branch"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Treat as repo path
            if [[ "$1" =~ ^[^/]+/[^/]+$ ]]; then
                REPO="$1"
            else
                echo "Error: Invalid repository path format: $1"
                echo "Expected format: owner/repo (e.g., kubernetes/kubernetes)"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ "$MODE" = "show" ]; then
    echo "Checking branch protection status for $REPO:$BRANCH..."
else
    echo "Setting up branch protection for $REPO:$BRANCH..."
fi

# Check if GitHub CLI is installed
if ! command -v gh > /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    echo "Install it from: https://cli.github.com/"
    echo "  brew install gh"
    exit 1
fi

# Check if authenticated (only needed for setup, not for show)
if [ "$MODE" = "setup" ]; then
    if ! gh auth status > /dev/null 2>&1; then
        echo "Error: Not authenticated with GitHub CLI"
        echo "Run: gh auth login"
        exit 1
    fi
fi

# Check current branch protection status
echo ""
echo "Checking current branch protection status..."
PROTECTION_STATUS=$(gh api repos/$REPO/branches/$BRANCH/protection 2>&1 || echo "NOT_PROTECTED")

# Fetch repository access information (all collaborators and teams) - do this early
echo "Fetching repository access information..."
ADMINS=""
ALL_COLLABORATORS=""
TEAMS=""
# shellcheck disable=SC2034  # ADMIN_FETCH_ERROR may be used in future
ADMIN_FETCH_ERROR=""
COLLABORATOR_FETCH_ERROR=""
TEAM_FETCH_ERROR=""

# Get all repository collaborators with their roles
COLLABORATOR_RESPONSE=$(gh api repos/$REPO/collaborators 2>&1)
if echo "$COLLABORATOR_RESPONSE" | grep -q "\["; then
    # Valid JSON response - extract all collaborators with their permissions
    if echo "$COLLABORATOR_RESPONSE" | jq -r '.[] | "\(.login)|\(.role_name)"' > /tmp/collaborators_$$.txt 2>/dev/null; then
        if [ -s /tmp/collaborators_$$.txt ]; then
            ALL_COLLABORATORS=$(cat /tmp/collaborators_$$.txt)
            # Extract just admins
            ADMINS=$(echo "$ALL_COLLABORATORS" | grep "|admin$" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')
        fi
        rm -f /tmp/collaborators_$$.txt
    fi
elif echo "$COLLABORATOR_RESPONSE" | grep -q "403\|404\|Not Found"; then
    COLLABORATOR_FETCH_ERROR="(Access denied - need read access to repository)"
    # ADMIN_FETCH_ERROR="(Access denied - need read access to repository)"  # Unused variable
fi

# Get teams and their permissions
TEAM_RESPONSE=$(gh api repos/$REPO/teams 2>&1)
if echo "$TEAM_RESPONSE" | grep -q "\["; then
    # Valid JSON response
    if echo "$TEAM_RESPONSE" | jq -r '.[] | "\(.name)|\(.permission)"' > /tmp/teams_$$.txt 2>/dev/null; then
        if [ -s /tmp/teams_$$.txt ]; then
            TEAMS=$(cat /tmp/teams_$$.txt)
        fi
        rm -f /tmp/teams_$$.txt
    fi
elif echo "$TEAM_RESPONSE" | grep -q "403\|404\|Not Found"; then
    TEAM_FETCH_ERROR="(Access denied - need read access to repository)"
fi

if echo "$PROTECTION_STATUS" | grep -q "NOT_PROTECTED\|404\|403"; then
    if echo "$PROTECTION_STATUS" | grep -q "403"; then
        echo "⚠️  Access denied or branch protection is NOT enabled for $BRANCH"
        echo "   (403 Forbidden - may not have access or protection not enabled)"
    else
        echo "❌ Branch protection is NOT enabled for $BRANCH"
    fi

    echo ""
    echo "Summary:"
    echo "  Repository: $REPO"
    echo "  Branch: $BRANCH"
    echo "  Protection: Not enabled"

    if [ "$MODE" = "show" ]; then
        if [ -n "$ALL_COLLABORATORS" ] || [ -n "$TEAMS" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Repository Access:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            if [ -n "$ALL_COLLABORATORS" ]; then
                echo "Collaborators and Roles:"
                # Group by role
                echo "$ALL_COLLABORATORS" | while IFS='|' read -r username role; do
                    case "$role" in
                        admin)
                            echo "  [ADMIN] $username - Full repository access, can modify settings"
                            ;;
                        maintain)
                            echo "  [MAINTAIN] $username - Can manage issues/PRs, cannot modify settings"
                            ;;
                        write)
                            echo "  [WRITE] $username - Can push code, create branches"
                            ;;
                        triage)
                            echo "  [TRIAGE] $username - Can manage issues/PRs, read-only code"
                            ;;
                        read)
                            echo "  [READ] $username - Read-only access"
                            ;;
                        *)
                            echo "  [$role] $username"
                            ;;
                    esac
                done
                echo ""

                if [ -n "$ADMINS" ]; then
                    echo "Repository Administrators (can modify protection rules):"
                    echo "$ADMINS" | tr ',' '\n' | sed 's/^/  - /'
                    echo ""
                fi
            elif [ -n "$COLLABORATOR_FETCH_ERROR" ]; then
                echo "Collaborators: $COLLABORATOR_FETCH_ERROR"
                echo ""
            else
                echo "Collaborators: (None found or unable to fetch)"
                echo ""
            fi

            if [ -n "$TEAMS" ]; then
                echo "Teams and Permissions:"
                echo "$TEAMS" | while IFS='|' read -r team_name permission; do
                    case "$permission" in
                        admin)
                            echo "  [ADMIN] $team_name - Full repository access"
                            ;;
                        push)
                            echo "  [WRITE] $team_name - Can push code"
                            ;;
                        pull)
                            echo "  [READ] $team_name - Read-only access"
                            ;;
                        maintain)
                            echo "  [MAINTAIN] $team_name - Can manage issues/PRs"
                            ;;
                        triage)
                            echo "  [TRIAGE] $team_name - Can manage issues/PRs"
                            ;;
                        *)
                            echo "  [$permission] $team_name"
                            ;;
                    esac
                done
                echo ""
            elif [ -n "$TEAM_FETCH_ERROR" ]; then
                echo "Teams: $TEAM_FETCH_ERROR"
                echo ""
            else
                echo "Teams: (None found or unable to fetch)"
                echo ""
            fi
        fi
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "What --setup would do:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "The following protection rules would be applied:"
        for rule in "${SETUP_RULES[@]}"; do
            echo "  ✓ $rule"
        done
        echo ""
        if [ -n "$ADMINS" ]; then
            echo "ℹ️  Note: With 'Enforce admins' disabled, these administrators can:"
            echo "$ADMINS" | tr ',' '\n' | sed 's/^/   - /'
            echo ""
            echo "   Admins can:"
            echo "     - Update their own PR branches (push to PR branches)"
            echo "     - Bypass protection rules when needed (emergency fixes)"
            echo "     - Still use pull requests (recommended workflow)"
            echo ""
            echo "   Protection still applies to:"
            echo "     - Direct pushes to $BRANCH (blocked for everyone)"
            echo "     - Merging PRs without approval (blocked)"
            echo "     - Merging PRs with failing status checks (blocked)"
            echo ""
        fi
        echo "To apply these rules, run:"
        echo "  $0 --setup $REPO --branch $BRANCH"
        echo ""
        echo "Or using Makefile:"
        echo "  make setup-branch-protection"
        exit 0
    fi

    echo ""

    # Show admins before setup
    if [ -n "$ADMINS" ]; then
        echo "ℹ️  Note: The following administrators will have bypass privileges:"
        echo "$ADMINS" | tr ',' '\n' | sed 's/^/   - /'
        echo ""
        echo "With 'enforce_admins=false', admins can:"
        echo "  - Update their own PR branches (push to feature branches)"
        echo "  - Bypass protection rules when needed (for emergency fixes)"
        echo "  - Still use pull requests (recommended workflow)"
        echo ""
        echo "Protection still applies to:"
        echo "  - Direct pushes to $BRANCH (blocked for everyone, including admins)"
        echo "  - Merging PRs without approval (blocked)"
        echo "  - Merging PRs with failing status checks (blocked)"
        echo ""
        echo "This configuration is suitable for solo developers or small teams."
        echo ""
        read -p "Continue with setup? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Setup cancelled."
            exit 0
        fi
        echo ""
    fi

    echo "Setting up branch protection..."

    # Enable branch protection with the following rules:
    # 1. Require pull request reviews
    # 2. Require status checks to pass
    # 3. Require branches to be up to date
    # 4. Require conversation resolution before merging
    # 5. Do not allow force pushes
    # 6. Do not allow deletions
    # 7. Allow admins to bypass (for solo developers to update their own PRs)

    # Create temporary JSON file for the protection settings
    PROTECTION_JSON=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "block_creations": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF
)

    # Use --input to pass the JSON properly
    echo "$PROTECTION_JSON" | gh api repos/$REPO/branches/$BRANCH/protection \
        --method PUT \
        --input -

    echo ""
    echo "✓ Branch protection enabled for $BRANCH"
    echo ""
    echo "Configuration:"
    echo "  - Admins can bypass protection (suitable for solo developers)"
    echo "  - Direct pushes to $BRANCH are still blocked"
    echo "  - PRs require 0 approvals (solo developer - you can merge your own PRs)"
    echo "  - PRs still require passing status checks"
    echo "  - You can update your own PR branches freely"
    echo ""
    echo "Protection rules applied:"
    for rule in "${SETUP_RULES[@]}"; do
        echo "  ✓ $rule"
    done
        echo ""
        if [ -n "$ALL_COLLABORATORS" ] || [ -n "$TEAMS" ]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Repository Access:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            if [ -n "$ALL_COLLABORATORS" ]; then
                echo "Collaborators and Roles:"
                echo "$ALL_COLLABORATORS" | while IFS='|' read -r username role; do
                    case "$role" in
                        admin)
                            echo "  [ADMIN] $username - Full repository access, can modify settings"
                            ;;
                        maintain)
                            echo "  [MAINTAIN] $username - Can manage issues/PRs, cannot modify settings"
                            ;;
                        write)
                            echo "  [WRITE] $username - Can push code, create branches"
                            ;;
                        triage)
                            echo "  [TRIAGE] $username - Can manage issues/PRs, read-only code"
                            ;;
                        read)
                            echo "  [READ] $username - Read-only access"
                            ;;
                        *)
                            echo "  [$role] $username"
                            ;;
                    esac
                done
                echo ""

                if [ -n "$ADMINS" ]; then
                    echo "⚠️  IMPORTANT: With 'Enforce admins' enabled, these administrators must:"
                    echo "   - Use pull requests (no direct pushes)"
                    echo "   - Get PR approvals before merging"
                    echo "   - Follow all protection rules"
                    echo ""
                    echo "   Affected admins: $(echo "$ADMINS" | tr ',' ', ')"
                    echo ""
                    echo "To allow admins to bypass protection, disable 'Enforce admins' in:"
                    echo "  https://github.com/$REPO/settings/branches"
                    echo ""
                fi
            fi

            if [ -n "$TEAMS" ]; then
                echo "Teams and Permissions:"
                echo "$TEAMS" | while IFS='|' read -r team_name permission; do
                    case "$permission" in
                        admin)
                            echo "  [ADMIN] $team_name - Full repository access"
                            ;;
                        push)
                            echo "  [WRITE] $team_name - Can push code"
                            ;;
                        pull)
                            echo "  [READ] $team_name - Read-only access"
                            ;;
                        maintain)
                            echo "  [MAINTAIN] $team_name - Can manage issues/PRs"
                            ;;
                        triage)
                            echo "  [TRIAGE] $team_name - Can manage issues/PRs"
                            ;;
                        *)
                            echo "  [$permission] $team_name"
                            ;;
                    esac
                done
                echo ""
            fi
        fi
    echo "Note: You can customize these rules in GitHub UI:"
    echo "  https://github.com/$REPO/settings/branches"
else
    echo "✓ Branch protection is enabled for $BRANCH"
    echo ""
    echo "Current protection rules:"

    # Parse and display protection details
    if command -v jq > /dev/null; then
        # Extract current settings
        CURRENT_PR_REVIEWS=$(echo "$PROTECTION_STATUS" | jq -r 'if .required_pull_request_reviews then (.required_pull_request_reviews.required_approving_review_count | tostring) else "0" end' 2>/dev/null || echo "0")
        CURRENT_DISMISS_STALE=$(echo "$PROTECTION_STATUS" | jq -r 'if .required_pull_request_reviews and .required_pull_request_reviews.dismiss_stale_reviews then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_CODE_OWNER=$(echo "$PROTECTION_STATUS" | jq -r 'if .required_pull_request_reviews and .required_pull_request_reviews.require_code_owner_reviews then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_STATUS_CHECKS=$(echo "$PROTECTION_STATUS" | jq -r 'if .required_status_checks then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_STRICT=$(echo "$PROTECTION_STATUS" | jq -r 'if .required_status_checks and .required_status_checks.strict then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_CONV_RESOLUTION=$(echo "$PROTECTION_STATUS" | jq -r 'if .required_conversation_resolution then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_ENFORCE_ADMINS=$(echo "$PROTECTION_STATUS" | jq -r 'if .enforce_admins.enabled then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_FORCE_PUSH=$(echo "$PROTECTION_STATUS" | jq -r 'if .allow_force_pushes then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_DELETIONS=$(echo "$PROTECTION_STATUS" | jq -r 'if .allow_deletions then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_LOCK=$(echo "$PROTECTION_STATUS" | jq -r 'if .lock_branch.enabled then "Yes" else "No" end' 2>/dev/null || echo "No")
        CURRENT_BLOCK_CREATE=$(echo "$PROTECTION_STATUS" | jq -r 'if .block_creations.enabled then "Yes" else "No" end' 2>/dev/null || echo "No")

        echo "  Repository: $REPO"
        echo "  Branch: $BRANCH"
        echo ""

        # Display all collaborators and teams
        if [ -n "$ALL_COLLABORATORS" ] || [ -n "$TEAMS" ]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Repository Access:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            if [ -n "$ALL_COLLABORATORS" ]; then
                echo "Collaborators and Roles:"
                echo "$ALL_COLLABORATORS" | while IFS='|' read -r username role; do
                    case "$role" in
                        admin)
                            echo "  [ADMIN] $username - Full repository access, can modify settings"
                            ;;
                        maintain)
                            echo "  [MAINTAIN] $username - Can manage issues/PRs, cannot modify settings"
                            ;;
                        write)
                            echo "  [WRITE] $username - Can push code, create branches"
                            ;;
                        triage)
                            echo "  [TRIAGE] $username - Can manage issues/PRs, read-only code"
                            ;;
                        read)
                            echo "  [READ] $username - Read-only access"
                            ;;
                        *)
                            echo "  [$role] $username"
                            ;;
                    esac
                done
                echo ""

                if [ -n "$ADMINS" ]; then
                    echo "Repository Administrators (can modify protection rules):"
                    echo "$ADMINS" | tr ',' '\n' | sed 's/^/  - /'
                    echo ""
                fi

                # Warning about enforce_admins
                if [ "$CURRENT_ENFORCE_ADMINS" = "Yes" ]; then
                    echo "⚠️  WARNING: 'Enforce admins' is enabled!"
                    echo "   This means even administrators must follow branch protection rules."
                    echo "   Admins cannot bypass protection (no direct pushes, PRs required)."
                    echo ""
                    if [ -n "$ADMINS" ]; then
                        echo "   Affected admins: $(echo "$ADMINS" | tr ',' ', ')"
                    fi
                    echo ""
                else
                    echo "ℹ️  Note: 'Enforce admins' is disabled."
                    echo "   Administrators can bypass branch protection rules."
                    echo ""
                fi
            elif [ -n "$COLLABORATOR_FETCH_ERROR" ]; then
                echo "Collaborators: $COLLABORATOR_FETCH_ERROR"
                echo ""
            else
                echo "Collaborators: (None found or unable to fetch)"
                echo ""
            fi

            if [ -n "$TEAMS" ]; then
                echo "Teams and Permissions:"
                echo "$TEAMS" | while IFS='|' read -r team_name permission; do
                    case "$permission" in
                        admin)
                            echo "  [ADMIN] $team_name - Full repository access"
                            ;;
                        push)
                            echo "  [WRITE] $team_name - Can push code"
                            ;;
                        pull)
                            echo "  [READ] $team_name - Read-only access"
                            ;;
                        maintain)
                            echo "  [MAINTAIN] $team_name - Can manage issues/PRs"
                            ;;
                        triage)
                            echo "  [TRIAGE] $team_name - Can manage issues/PRs"
                            ;;
                        *)
                            echo "  [$permission] $team_name"
                            ;;
                    esac
                done
                echo ""
            elif [ -n "$TEAM_FETCH_ERROR" ]; then
                echo "Teams: $TEAM_FETCH_ERROR"
                echo ""
            else
                echo "Teams: (None found or unable to fetch)"
                echo ""
            fi
        fi

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Protection Settings:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Required PR reviews: $([ "$CURRENT_PR_REVIEWS" != "0" ] && echo "Yes (approvals: $CURRENT_PR_REVIEWS)" || echo "No")"
        echo "  Dismiss stale reviews: $CURRENT_DISMISS_STALE"
        echo "  Require code owner reviews: $CURRENT_CODE_OWNER"
        echo "  Required status checks: $CURRENT_STATUS_CHECKS $([ "$CURRENT_STATUS_CHECKS" = "Yes" ] && echo "(strict: $CURRENT_STRICT)")"
        echo "  Require conversation resolution: $CURRENT_CONV_RESOLUTION"
        echo "  Enforce admins: $CURRENT_ENFORCE_ADMINS"
        echo "  Allow force pushes: $CURRENT_FORCE_PUSH"
        echo "  Allow deletions: $CURRENT_DELETIONS"
        echo "  Lock branch: $CURRENT_LOCK"
        echo "  Block creations: $CURRENT_BLOCK_CREATE"

        # Compare with setup rules and show what's missing
        if [ "$MODE" = "show" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Comparison with --setup defaults:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            MISSING_COUNT=0

            # Check each rule
            if [ "$CURRENT_PR_REVIEWS" = "0" ]; then
                echo "  ❌ Missing: Required PR reviews (setup would set: 1 approval)"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            elif [ "$CURRENT_PR_REVIEWS" != "1" ]; then
                echo "  ⚠️  Different: PR reviews required: $CURRENT_PR_REVIEWS (setup would set: 1)"
            else
                echo "  ✓ Required PR reviews: OK (1 approval)"
            fi

            if [ "$CURRENT_DISMISS_STALE" != "Yes" ]; then
                echo "  ❌ Missing: Dismiss stale reviews (setup would enable)"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            else
                echo "  ✓ Dismiss stale reviews: OK"
            fi

            if [ "$CURRENT_STATUS_CHECKS" != "Yes" ]; then
                echo "  ❌ Missing: Required status checks (setup would enable)"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            elif [ "$CURRENT_STRICT" != "Yes" ]; then
                echo "  ⚠️  Different: Status checks strict mode (setup would enable)"
            else
                echo "  ✓ Required status checks: OK (strict mode)"
            fi

            if [ "$CURRENT_CONV_RESOLUTION" != "Yes" ]; then
                echo "  ❌ Missing: Require conversation resolution (setup would enable)"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            else
                echo "  ✓ Require conversation resolution: OK"
            fi

            if [ "$CURRENT_ENFORCE_ADMINS" != "Yes" ]; then
                echo "  ⚠️  Different: Enforce admins (setup would enable)"
                echo "     WARNING: This will require admins to follow protection rules too!"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            else
                echo "  ✓ Enforce admins: OK (admins must follow protection rules)"
            fi

            if [ "$CURRENT_FORCE_PUSH" != "No" ]; then
                echo "  ⚠️  Warning: Force pushes allowed (setup would disable)"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            else
                echo "  ✓ Force pushes blocked: OK"
            fi

            if [ "$CURRENT_DELETIONS" != "No" ]; then
                echo "  ⚠️  Warning: Deletions allowed (setup would disable)"
                MISSING_COUNT=$((MISSING_COUNT + 1))
            else
                echo "  ✓ Deletions blocked: OK"
            fi

            echo ""
            if [ $MISSING_COUNT -eq 0 ]; then
                echo "✓ All recommended protection rules are already in place!"
            else
                echo "Found $MISSING_COUNT difference(s) from --setup defaults"
                echo ""
                echo "To apply --setup defaults, run:"
                echo "  $0 --setup $REPO --branch $BRANCH"
                echo ""
                echo "Note: --setup will overwrite current settings with defaults."
            fi
        fi
    else
        echo "  (jq not installed - showing raw response)"
        echo "$PROTECTION_STATUS" | head -30
    fi

    echo ""
    echo "To view or modify protection rules:"
    echo "  https://github.com/$REPO/settings/branches"

    if [ "$MODE" = "show" ]; then
        echo ""
        echo "✓ Check complete (read-only mode)"
    fi
fi

if [ "$MODE" = "setup" ]; then
    echo ""
    echo "To verify protection is working, try:"
    echo "  git push origin $BRANCH"
    echo ""
    echo "You should see an error requiring a pull request."
fi
