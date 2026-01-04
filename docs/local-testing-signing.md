# Testing Cosign Signing Locally

This guide explains how to test the cosign signing functionality locally before pushing changes to verify it works in CI/CD.

## Prerequisites

1. **Install cosign** (if not already installed):
   ```bash
   # macOS
   brew install cosign
   
   # Or download from: https://github.com/sigstore/cosign/releases
   # Make sure to install v2.2.1 to match CI/CD
   ```

2. **Verify cosign version** (should match CI/CD version v2.2.1):
   ```bash
   cosign version
   ```

3. **Have a Docker image to test with** (either build one locally or use an existing one from GHCR)

## Testing Options

### Option 1: Test with Key-Based Signing (Simplest)

This is the easiest way to test the signing functionality locally without GitHub OIDC:

1. **Generate a key pair** (one-time setup):
   ```bash
   cosign generate-key-pair
   # Enter a password when prompted (remember it!)
   ```

2. **Build and push an image** (or use an existing one):
   ```bash
   # Build and push (without signing)
   make docker-push
   
   # Or use an existing image
   export IMAGE="ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-test"
   ```

3. **Sign the image using the key**:
   ```bash
   export COSIGN_PASSWORD=your_key_password
   export COSIGN_KEY_PATH=./cosign.key
   make docker-sign IMAGE=$IMAGE
   ```

4. **Verify the signature**:
   ```bash
   make docker-verify IMAGE=$IMAGE
   # Or: cosign verify --key cosign.pub $IMAGE
   ```

### Option 2: Test Keyless Signing Locally (Closer to CI/CD)

To test keyless signing locally (similar to CI/CD), you'll need a GitHub Personal Access Token (PAT):

1. **Create a GitHub PAT** with `write:packages` permission:
   - Go to: https://github.com/settings/tokens
   - Generate new token (classic) with `write:packages` scope

2. **Set environment variables**:
   ```bash
   export GITHUB_TOKEN=your_github_token
   # Note: For cosign v2.x, COSIGN_EXPERIMENTAL is not needed, but 
   # locally it might still require it for keyless signing
   export COSIGN_EXPERIMENTAL=1  # May be needed for local keyless signing
   ```

3. **Build and push an image**:
   ```bash
   make docker-push
   ```

4. **Sign the image** (keyless):
   ```bash
   # Using the Makefile (which handles COSIGN_EXPERIMENTAL)
   make docker-sign IMAGE=$IMAGE
   
   # Or directly (to test the exact CI/CD command structure):
   cosign sign $IMAGE
   ```

5. **Verify the signature**:
   ```bash
   make docker-verify IMAGE=$IMAGE
   # Or: cosign verify $IMAGE
   ```

### Option 3: Test the Exact CI/CD Command (Dry Run)

To test the exact command that will run in CI/CD:

1. **Use an existing image from GHCR**:
   ```bash
   export IMAGE="ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234"
   ```

2. **Test the signing command** (without COSIGN_EXPERIMENTAL for cosign v2.x):
   ```bash
   # This is the exact command that will run in CI/CD
   cosign sign $IMAGE
   ```

3. **Verify**:
   ```bash
   cosign verify $IMAGE
   ```

## Important Notes

### About COSIGN_EXPERIMENTAL

- **In CI/CD (cosign v2.x)**: `COSIGN_EXPERIMENTAL=1` is **NOT needed** - keyless signing works automatically with GitHub OIDC when `id-token: write` permission is set
- **Locally (for testing)**: You may still need `COSIGN_EXPERIMENTAL=1` for keyless signing with a GitHub token, depending on your cosign version

### What Changed in CI/CD

The CI/CD workflow was updated to remove `COSIGN_EXPERIMENTAL: 1` because:
- Cosign v2.x supports keyless signing natively via GitHub OIDC
- The experimental flag is deprecated and no longer needed
- The workflow already has `id-token: write` permission which enables OIDC

### Testing the CI/CD Change

The best way to verify the CI/CD change will work:

1. **Option A**: Push the change and let CI/CD run (safest test)
2. **Option B**: Test locally with key-based signing to verify the command structure works
3. **Option C**: Test locally with keyless signing (requires GitHub PAT) to simulate CI/CD

## Troubleshooting

### "Error: no matching signatures"

This means the image isn't signed yet. Make sure you've run the signing step first.

### "Error: getting credentials"

- For keyless signing: Make sure `GITHUB_TOKEN` is set and has correct permissions
- For key-based signing: Make sure `COSIGN_PASSWORD` and `COSIGN_KEY_PATH` are set correctly

### "Error: COSIGN_EXPERIMENTAL not set"

- In CI/CD (cosign v2.x): This should not happen - the flag is not needed
- Locally: You may need to set `COSIGN_EXPERIMENTAL=1` for keyless signing

### "Error: certificate verification failed"

- Ensure you're connected to the internet
- Check that Fulcio/Rekor services are accessible

## Quick Test Script

Here's a quick script to test signing locally:

```bash
#!/bin/bash
set -e

# Set your image
IMAGE="ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-test"

# Option 1: Key-based (easiest)
if [ -f "./cosign.key" ]; then
  echo "Testing key-based signing..."
  export COSIGN_PASSWORD=your_password_here
  export COSIGN_KEY_PATH=./cosign.key
  cosign sign --key ./cosign.key $IMAGE
  cosign verify --key ./cosign.pub $IMAGE
  echo "✓ Key-based signing test passed!"
fi

# Option 2: Keyless (requires GITHUB_TOKEN)
if [ -n "$GITHUB_TOKEN" ]; then
  echo "Testing keyless signing..."
  export COSIGN_EXPERIMENTAL=1  # May be needed locally
  cosign sign $IMAGE
  cosign verify $IMAGE
  echo "✓ Keyless signing test passed!"
fi
```
