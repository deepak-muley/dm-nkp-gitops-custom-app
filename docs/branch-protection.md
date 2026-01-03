# Branch Protection Setup

This document describes how to set up branch protection for the master/main branch to prevent direct pushes and enforce code review.

## Overview

Branch protection rules ensure that:

- **No direct pushes** to the master branch
- **Pull requests required** for all changes
- **Code review required** before merging
- **Status checks must pass** before merging
- **Force pushes blocked** to prevent history rewriting
- **Branch deletion blocked** to prevent accidental removal

## Quick Setup

### Check Protection Status (Read-Only)

To check branch protection on any repository without making changes:

```bash
# Check current repository
make check-branch-protection

# Or directly
./scripts/branch-protect.sh --show

# Check another repository (repo as argument)
./scripts/branch-protect.sh --show kubernetes/kubernetes
./scripts/branch-protect.sh --show kubernetes/kubernetes --branch main

# Or using Makefile
make check-branch-protection-repo REPO=kubernetes/kubernetes BRANCH=main
```

### Using the Setup Script

```bash
# Setup protection (default repo/branch)
./scripts/branch-protect.sh --setup

# Setup protection for specific repo
./scripts/branch-protect.sh --setup owner/repo --branch main
```

This script will:

1. Check if branch protection is enabled
2. If not, enable it with recommended settings
3. Show current protection status

**Options:**

- `--show` - Show protection status (default, read-only, works on any repo)
- `--setup` - Set up branch protection (requires write access)
- `--branch BRANCH` - Specify branch (default: master)
- `REPO_PATH` - Repository path as argument (e.g., `kubernetes/kubernetes`)
- `--help` - Show usage information

**Examples:**

```bash
# Show protection (read-only) - shows what --setup would do
./scripts/branch-protect.sh --show
./scripts/branch-protect.sh --show facebook/react
./scripts/branch-protect.sh --show microsoft/vscode --branch main

# Setup protection (requires write access)
./scripts/branch-protect.sh --setup
./scripts/branch-protect.sh --setup owner/repo --branch main
```

**What `--setup` applies:**

- Require pull request reviews (1 approval)
- Dismiss stale reviews
- Require status checks to pass (strict mode)
- Require conversation resolution
- Enforce admins
- Block force pushes
- Block branch deletion

**What `--show` displays:**

- Current protection status
- **All repository collaborators with their roles** (Read, Triage, Write, Maintain, Admin)
- **Repository administrators** (who can modify protection rules)
- **Teams and their permissions** (what access teams have)
- All protection settings
- **Admin lockout warnings** (if enforce_admins is enabled)
- Comparison with `--setup` defaults
- What's missing or different from recommended settings
- Command to apply `--setup` if needed

**Important:** The script shows all collaborators and teams to help you understand who will be affected by branch protection, especially when `enforce_admins` is enabled. This helps prevent accidentally locking yourself out.

**GitHub Roles:** See [GitHub Roles Documentation](github-roles.md) for details on all permission levels (Read, Triage, Write, Maintain, Admin).

**Prerequisites:**

- GitHub CLI (`gh`) installed
- Authenticated with GitHub (`gh auth login`) - only needed for setting up protection, not for checking

### Check Protection on Any Repository

The script can check branch protection on **any repository** (even ones you don't own) in read-only mode:

```bash
# Check current repository
make check-branch-protection

# Check another repository
./scripts/branch-protect.sh --show kubernetes/kubernetes --branch main

# Check using Makefile
make check-branch-protection-repo REPO=kubernetes/kubernetes BRANCH=main
make check-branch-protection-repo REPO=microsoft/vscode BRANCH=main
```

**Note:** Read-only mode (`--check-only`) works on any public repository and doesn't require write permissions. You only need authentication for setting up protection.

### Manual Setup via GitHub Web UI

1. Go to your repository: `https://github.com/deepak-muley/dm-nkp-gitops-custom-app`
2. Click on **Settings** → **Branches**
3. Click **Add rule** or edit the existing rule for `master`
4. Configure the following:
   - ✅ **Require a pull request before merging**
     - Require approvals: 0 (for solo developers) or 1+ (for teams)
     - Dismiss stale pull request approvals when new commits are pushed
   - ✅ **Require status checks to pass before merging**
     - Require branches to be up to date before merging
   - ✅ **Require conversation resolution before merging**
   - ⚠️ **Do not allow bypassing the above settings** (disabled by default for solo developers)
   - ❌ **Restrict who can push to matching branches** (optional)
   - ❌ **Allow force pushes** (should be disabled)
   - ❌ **Allow deletions** (should be disabled)

5. Click **Create** or **Save changes**

### Manual Setup via GitHub CLI

```bash
# Set up branch protection (default: 0 approvals, enforce_admins=false for solo developers)
gh api repos/deepak-muley/dm-nkp-gitops-custom-app/branches/master/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":[]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews='{"required_approving_review_count":0,"dismiss_stale_reviews":true}' \
  --field restrictions=null \
  --field allow_force_pushes=false \
  --field allow_deletions=false \
  --field required_conversation_resolution=true
```

**Note:** The default configuration sets:

- `required_approving_review_count=0` - No approvals needed (solo developers can merge their own PRs)
- `enforce_admins=false` - Admins can bypass protection and update their own PR branches

For teams, increase `required_approving_review_count` to 1 or more and optionally set `enforce_admins=true`.

## Verify Branch Protection

### Check Protection Status

```bash
# Using GitHub CLI
gh api repos/deepak-muley/dm-nkp-gitops-custom-app/branches/master/protection | jq

# Or view in browser
open https://github.com/deepak-muley/dm-nkp-gitops-custom-app/settings/branches
```

### Test Protection

Try to push directly to master:

```bash
git checkout master
git commit --allow-empty -m "test: verify branch protection"
git push origin master
```

You should see an error like:

```
! [remote rejected] master -> master (protected branch hook declined)
error: failed to push some refs to 'origin'
```

This confirms branch protection is working.

## Recommended Protection Rules

### Minimum Protection (Recommended)

- ✅ Require pull request reviews (0 approvals for solo developers, 1+ for teams)
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Block force pushes
- ✅ Block deletions

**Note:** The default configuration uses 0 approvals, which is suitable for solo developers. For teams, increase this to 1 or more.

### Enhanced Protection (Optional)

- ✅ Require conversation resolution
- ✅ Require code owner reviews (if CODEOWNERS file exists)
- ✅ Require linear history (no merge commits)
- ✅ Restrict pushes to specific users/teams
- ✅ Require signed commits

## Workflow with Branch Protection

### Making Changes

1. **Create a feature branch:**

   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make your changes and commit:**

   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

3. **Push to your branch:**

   ```bash
   git push origin feature/my-feature
   ```

4. **Create a Pull Request:**
   - Go to GitHub and create a PR from your branch to `master`
   - Wait for CI checks to pass
   - Merge the PR (no approval needed for solo developers)

### Updating Your Own PRs (Admin)

With the default configuration (`enforce_admins=false`), admins can:

- **Update their own PR branches** by pushing to the feature branch
- **Bypass protection rules** when needed (for emergency fixes)
- Still use pull requests (recommended workflow)

**Example workflow:**

```bash
# Create a PR branch
git checkout -b feature/my-feature
git commit -m "feat: add feature"
git push origin feature/my-feature

# Create PR on GitHub, then later update it:
git commit --amend -m "feat: add feature (updated)"
git push origin feature/my-feature --force-with-lease  # Works for your own PR branches
```

**Note:**

- Direct pushes to the protected branch (e.g., `master`) are still blocked for everyone, including admins
- With 0 required approvals, you can merge your own PRs without needing someone else to approve
- Status checks must still pass before merging

### Emergency Bypass (Admin Only)

If you have admin access and need to bypass protection (emergency only):

1. Go to repository Settings → Branches
2. Temporarily disable protection
3. Make the emergency change
4. Re-enable protection immediately

**⚠️ Warning:** Only use bypass in true emergencies. Always re-enable protection.

## CI/CD Integration

The branch protection works with your CI/CD workflows:

- **CI Workflow** (`.github/workflows/ci.yml`): Runs on PRs and must pass
- **CD Workflow** (`.github/workflows/cd.yml`): Runs on tags and master branch (after PR merge)

### Required Status Checks

You can configure specific status checks that must pass:

```bash
gh api repos/deepak-muley/dm-nkp-gitops-custom-app/branches/master/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["test","lint","build"]}'
```

This requires the `test`, `lint`, and `build` jobs to pass before merging.

## Troubleshooting

### "Protected branch hook declined"

**Issue:** Cannot push directly to master
**Solution:** This is expected! Create a branch and open a PR instead.

### "Required status check is missing"

**Issue:** PR shows status checks as pending
**Solution:**

- Ensure CI workflow is running
- Check that workflow file is correct
- Verify the status check name matches what's configured

### "Changes requested" blocking merge

**Issue:** PR has requested changes that block merging
**Solution:**

- Address the review comments
- Request a new review
- Or dismiss the review if it's no longer relevant

### Cannot merge PR even with approval

**Issue:** PR has approval but still can't merge
**Solution:**

- Check if all required status checks have passed
- Ensure branch is up to date with master
- Verify conversation resolution is enabled and all conversations are resolved

## Admin Access and Lockout Prevention

### Understanding "Enforce Admins"

**Default Configuration (`enforce_admins=false`):**

- **Admins can bypass protection rules** (suitable for solo developers)
- Admins can update their own PR branches freely
- Admins can push to feature branches (but not directly to protected branch)
- Direct pushes to protected branch (e.g., `master`) are still blocked for everyone
- Useful for solo developers who need to update their own PRs

**Strict Configuration (`enforce_admins=true`):**

- **Admins must follow all protection rules** (no bypass)
- Admins cannot push directly to protected branches
- Admins must use pull requests like everyone else
- Admins can still modify protection rules (if they have repo admin access)
- Recommended for teams with multiple developers

### Viewing Admins and Teams

The `--show` command displays:

- **Administrators**: Users with admin access to the repository
- **Teams and Permissions**: Teams and their access levels (admin, push, pull, etc.)

This helps you:

- Understand who will be affected by protection
- Prevent accidentally locking yourself out
- Plan for emergency access if needed

### Preventing Admin Lockout

**Before enabling `enforce_admins`:**

1. Check who the admins are: `./scripts/branch-protect.sh --show`
2. Ensure at least one admin has access to modify protection rules
3. Consider keeping `enforce_admins` disabled if you need emergency access
4. Or create a separate "emergency" branch that's not protected

**If you get locked out:**

1. If you're a repository owner, you can always modify protection via GitHub UI
2. Repository owners can bypass protection even with `enforce_admins` enabled
3. Organization owners can modify protection for any repo in the org

## Best Practices

1. **Always use feature branches** for changes
2. **Keep PRs small and focused** for easier review
3. **Write clear PR descriptions** explaining what and why
4. **Respond to review comments** promptly
5. **Don't bypass protection** unless it's a true emergency
6. **Keep master branch stable** - only merge tested, reviewed code
7. **Review admin list** before enabling `enforce_admins` to prevent lockout
8. **Keep at least one admin** who can modify protection rules

## References

- [GitHub Branch Protection Documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub CLI API Documentation](https://cli.github.com/manual/gh_api)
- [GitHub Branch Protection API](https://docs.github.com/en/rest/branches/branch-protection)
- [GitHub Roles and Permissions](github-roles.md) - Detailed explanation of all GitHub repository roles
