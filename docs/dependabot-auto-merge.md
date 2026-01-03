# Enabling Dependabot Auto-Merge

This guide explains how to enable automatic merging of Dependabot PRs when all checks pass.

## Current Setup

You already have an auto-merge workflow configured (`.github/workflows/auto-merge.yml`) that will automatically merge Dependabot PRs when:

1. ✅ PR is created by `dependabot[bot]`
2. ✅ PR has the `dependencies` label (automatically added by Dependabot)
3. ✅ PR is mergeable (no conflicts)
4. ✅ All status checks pass

## Required GitHub Settings

### 1. Enable Auto-Merge in Repository Settings

1. Go to your repository on GitHub
2. Navigate to **Settings** → **General**
3. Scroll down to **Pull Requests**
4. Enable **"Allow auto-merge"**
5. Optionally enable **"Automatically delete head branches"** after merge

### 2. Configure Branch Protection (for master/main)

If you have branch protection enabled, you need to allow auto-merge:

1. Go to **Settings** → **Branches**
2. Select your protected branch (e.g., `master` or `main`)
3. Under **"Require pull request reviews before merging"**, ensure:
   - **"Allow auto-merge"** is enabled
   - If you require approvals, you may need to adjust this for Dependabot PRs

**Note:** If branch protection requires approvals, you have two options:

**Option A: Disable approval requirement for Dependabot**

- Use CODEOWNERS to exempt Dependabot from review requirements
- Or configure branch protection to allow auto-merge without approvals

**Option B: Auto-approve Dependabot PRs**

- Add a workflow that auto-approves Dependabot PRs
- Then auto-merge can proceed

### 3. Verify Workflow Permissions

The auto-merge workflow requires:

- `contents: write` - To merge PRs
- `pull-requests: write` - To enable auto-merge

These are already configured in `.github/workflows/auto-merge.yml`.

## How It Works

### Workflow Flow

1. **Dependabot creates PR** → PR gets `dependencies` label automatically
2. **Label workflow runs** → Ensures `dependencies` label is present
3. **CI/CD workflows run** → All tests and checks execute
4. **Auto-merge workflow runs** → When all checks pass:
   - Checks if PR is mergeable
   - Checks if PR has `dependencies` label
   - Enables auto-merge with squash merge
5. **GitHub auto-merges** → Once all required checks pass

### Current Conditions

The auto-merge workflow will enable auto-merge if:

```yaml
github.event.pull_request.user.login == 'dependabot[bot]' &&
contains(github.event.pull_request.labels.*.name, 'dependencies') &&
github.event.pull_request.mergeable == true
```

## Testing Auto-Merge

### Manual Test

1. Create a test Dependabot PR (or wait for a real one)
2. Verify the PR has the `dependencies` label
3. Wait for all CI checks to pass
4. Check the Actions tab → "Auto-merge Dependencies" workflow
5. The workflow should enable auto-merge
6. GitHub will merge automatically once all required checks pass

### Verify It's Working

Check the workflow run logs:

- Go to **Actions** → **Auto-merge Dependencies**
- Look for successful runs
- Check the logs for: "gh pr merge ... --auto --squash"

## Troubleshooting

### Auto-merge Not Working

**Issue:** PRs not auto-merging even when checks pass

**Solutions:**

1. **Check branch protection:**
   - Ensure "Allow auto-merge" is enabled in branch protection
   - Verify approval requirements aren't blocking

2. **Check PR labels:**
   - Ensure PR has `dependencies` label
   - Dependabot should add this automatically

3. **Check workflow permissions:**
   - Verify workflow has `contents: write` and `pull-requests: write`
   - Check if workflow is running (Actions tab)

4. **Check merge conflicts:**
   - PR must be mergeable (no conflicts)
   - Rebase if needed: `@dependabot rebase`

5. **Check required status checks:**
   - All required checks must pass
   - Go to Settings → Branches → Protected branch → Required status checks

### Auto-merge Enabled But Not Merging

**Issue:** Auto-merge is enabled but PR isn't merging

**Solutions:**

1. **Check required checks:**
   - Some checks might still be pending
   - Go to PR → Checks tab to see status

2. **Check branch protection:**
   - Approval requirements might be blocking
   - Review requirements might need to be satisfied

3. **Check for conflicts:**
   - PR might have merge conflicts
   - Use `@dependabot rebase` to resolve

## Advanced Configuration

### Auto-Approve Dependabot PRs

If branch protection requires approvals, you can auto-approve Dependabot PRs:

```yaml
# .github/workflows/auto-approve.yml
name: Auto-approve Dependabot

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  auto-approve:
    runs-on: ubuntu-latest
    if: github.actor == 'dependabot[bot]'
    permissions:
      pull-requests: write
    steps:
      - name: Auto-approve Dependabot PR
        run: |
          gh pr review ${{ github.event.pull_request.number }} --approve
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Custom Merge Strategy

The current workflow uses `--squash`. To change:

```yaml
# In .github/workflows/auto-merge.yml
gh pr merge ${{ github.event.pull_request.number }} --auto --squash  # Current
# Or use:
gh pr merge ${{ github.event.pull_request.number }} --auto --merge  # Merge commit
gh pr merge ${{ github.event.pull_request.number }} --auto --rebase  # Rebase
```

### Exclude Certain Dependencies

To prevent auto-merge for specific dependencies, modify the workflow condition:

```yaml
if: |
  github.event.pull_request.user.login == 'dependabot[bot]' &&
  contains(github.event.pull_request.labels.*.name, 'dependencies') &&
  github.event.pull_request.mergeable == true &&
  !contains(github.event.pull_request.title, 'major')  # Exclude major updates
```

## Verification Checklist

- [ ] "Allow auto-merge" enabled in repository settings
- [ ] Branch protection allows auto-merge (if enabled)
- [ ] Auto-merge workflow has correct permissions
- [ ] Dependabot PRs have `dependencies` label
- [ ] All required status checks are passing
- [ ] No merge conflicts in PRs
- [ ] Workflow is enabled and running

## Related Documentation

- [Dependabot Configuration](../.github/dependabot.yml)
- [Auto-merge Workflow](../.github/workflows/auto-merge.yml)
- [GitHub Actions Reference](./github-actions-reference.md#auto-merge)
