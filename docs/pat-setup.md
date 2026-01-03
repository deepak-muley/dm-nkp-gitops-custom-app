# Personal Access Token (PAT) Setup for CD Workflow

## Problem

If you encounter `DENIED: permission_denied: write_package` errors when the CD workflow tries to push Docker images or Helm charts to GitHub Container Registry (GHCR), you need to set up a Personal Access Token (PAT).

## Solution

The CD workflow (`cd.yml`) is already configured to use a PAT if available. It will:

1. First try to use `GITHUB_PAT` (if set)
2. Fall back to `GITHUB_TOKEN` (default GitHub Actions token)

## Steps to Create and Configure PAT

### 1. Create Personal Access Token

1. **Go to GitHub Settings:**
   - Click your profile picture → **Settings**
   - Navigate to **Developer settings** → **Personal access tokens** → **Tokens (classic)**

2. **Generate New Token:**
   - Click **Generate new token** → **Generate new token (classic)**
   - Give it a descriptive name: `GHCR Write Access`
   - Set expiration (recommended: 90 days or custom)
   - Select scopes:
     - ✅ `write:packages` - Upload packages to GitHub Container Registry
     - ✅ `read:packages` - Download packages from GitHub Container Registry
     - ✅ `delete:packages` - Delete packages from GitHub Container Registry (optional)

3. **Generate and Copy Token:**
   - Click **Generate token**
   - **IMPORTANT:** Copy the token immediately (you won't see it again)
   - Store it securely

### 2. Add to Repository Secrets

1. **Go to Repository Settings:**
   - Navigate to your repository
   - Go to **Settings** → **Secrets and variables** → **Actions**

2. **Add Secret:**
   - Click **New repository secret**
   - Name: `GITHUB_PAT`
   - Value: Paste your token
   - Click **Add secret**

### 3. Verify

1. **Check Workflow:**
   - The CD workflow will automatically use `GITHUB_PAT` if available
   - If `GITHUB_PAT` is not set, it will fall back to `GITHUB_TOKEN` (may fail if permissions are insufficient)

2. **Test:**
   - Push to `master` branch to trigger CD workflow
   - Check the workflow logs to verify successful push to GHCR

## Why Use PAT?

- **Default `GITHUB_TOKEN`** has limited permissions and may not have `write:packages` scope
- **PAT with explicit scopes** ensures reliable package uploads to GHCR
- **Workflow fallback:** If `GITHUB_PAT` is not set, the workflow will use `GITHUB_TOKEN` (may fail if permissions are insufficient)

## Security Best Practices

1. **Token Expiration:**
   - Set a reasonable expiration (90 days recommended)
   - Rotate tokens regularly

2. **Minimal Scopes:**
   - Only grant the minimum required permissions
   - For GHCR: `write:packages` and `read:packages` are sufficient

3. **Repository Secrets:**
   - Never commit tokens to code
   - Use GitHub Secrets for all sensitive values

4. **Monitor Usage:**
   - Regularly review token usage in GitHub Settings
   - Revoke unused or compromised tokens immediately

## Troubleshooting

### Still Getting Permission Denied?

1. **Verify Secret Name:**
   - Ensure the secret is named exactly `GITHUB_PAT` (case-sensitive)

2. **Check Token Scopes:**
   - Verify the token has `write:packages` permission
   - Regenerate token if scopes are incorrect

3. **Check Workflow Permissions:**
   - Ensure the workflow has `packages: write` permission (already configured in `cd.yml`)

4. **Verify Registry Path:**
   - Check that the registry path matches your repository
   - Format: `ghcr.io/OWNER/REPO/IMAGE_NAME`

## Related Documentation

- [GitHub Actions Setup](./github-actions-setup.md)
- [GHCR Artifacts](./ghcr-artifacts.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
