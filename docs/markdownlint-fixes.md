# Markdownlint Fixes

## Summary

markdownlint is now working with Node.js 18. The hook found several linting issues in markdown files that need to be fixed.

## How to Fix

### Option 1: Auto-fix (Recommended)

Run markdownlint with `--fix` flag to automatically fix issues:

```bash
export PATH="/usr/local/opt/node@18/bin:$PATH"
source .venv/bin/activate
pre-commit run markdownlint --all-files
```

This will automatically fix:

- Line length issues (where possible)
- Missing language tags in code blocks
- Other auto-fixable issues

### Option 2: Manual Fixes

The main issues found are:

1. **MD013/line-length**: Lines longer than 80 characters
   - Fix: Break long lines or adjust content

2. **MD040/fenced-code-language**: Code blocks without language specified
   - Fix: Add language tag, e.g., ` ```bash ` instead of ` ``` `

3. **MD036/no-emphasis-as-heading**: Using emphasis (`**text**`) instead of headings
   - Fix: Use proper heading syntax (`## text`)

4. **MD029/ol-prefix**: Ordered list numbering issues
   - Fix: Ensure ordered lists use consistent numbering

## Files with Issues

- `docs/buildpacks.md`
- `docs/dependabot-auto-merge.md`
- `docs/deployment.md`
- `docs/image-signing.md`
- `docs/manifests-vs-helm.md`
- `docs/pre-commit-setup.md`
- `docs/testing.md`

## Quick Fix Command

```bash
# Set Node.js 18 in PATH (already added to ~/.zshrc)
export PATH="/usr/local/opt/node@18/bin:$PATH"

# Activate pre-commit environment
source .venv/bin/activate

# Run markdownlint with auto-fix
pre-commit run markdownlint --all-files

# Review changes and commit
git add -A
git commit -m "fix: markdownlint issues"
```

## Note

After restarting your terminal, Node.js 18 will be in PATH automatically (added to `~/.zshrc`). Until then, use `export PATH="/usr/local/opt/node@18/bin:$PATH"` in your current session.
