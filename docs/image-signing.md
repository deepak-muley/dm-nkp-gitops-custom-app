# Container Image Signing

This document describes how container images are signed using [cosign](https://github.com/sigstore/cosign) to ensure authenticity and integrity.

## Overview

All container images built and pushed to GHCR are automatically signed using cosign's keyless signing feature, which uses GitHub's OIDC (OpenID Connect) for authentication. This provides:

- **Authenticity**: Verifies the image was built by the expected source
- **Integrity**: Ensures the image hasn't been tampered with
- **Non-repudiation**: Provides cryptographic proof of origin
- **Supply Chain Security**: Enables policy enforcement and verification

## Container Image Reference

The Helm chart uses the following container image:

```
ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>
```

Where `<version>` follows immutable versioning:
- With immutable versioning: `0.1.0-sha-abc1234` (note: Docker tags use `-` not `+`)
- Without immutable versioning: `0.1.0`

**Note:** Docker image tags cannot contain `+`, so we use `-` for images. Helm charts use `+` as per SemVer build metadata.

## Signing Methods

### 1. Keyless Signing (Default in CI/CD)

Keyless signing uses GitHub OIDC and doesn't require managing private keys. This is the default method used in GitHub Actions.

**In CI/CD:**
- Automatically signs images after pushing
- Uses GitHub's OIDC token for authentication
- No additional configuration required

**Local signing (keyless):**
```bash
export COSIGN_EXPERIMENTAL=1
export GITHUB_TOKEN=your_token
make docker-push SIGN=true
```

### 2. Key-Based Signing

For local development or when you need more control, you can use key-based signing.

**Generate a key pair:**

The `cosign.key` file is created using the `cosign generate-key-pair` command:

```bash
cosign generate-key-pair
```

**What happens:**
1. You'll be prompted to enter a password to encrypt the private key
2. Two files are created in the current directory:
   - `cosign.key` - **Private key** (encrypted with your password, keep secret!)
   - `cosign.pub` - **Public key** (can be shared, safe to commit)

**Example output:**
```bash
$ cosign generate-key-pair

Enter password for private key:
Enter password for private key again:
Private key written to cosign.key
Public key written to cosign.pub
```

**Key details:**
- The private key (`cosign.key`) is encrypted using the password you provide
- The password is required every time you use the private key to sign
- The public key (`cosign.pub`) is not encrypted and can be freely shared
- Both keys are in PEM format

**⚠️ SECURITY WARNING:** 
- **NEVER commit `cosign.key` or any private keys to the repository**
- The `.gitignore` file already excludes `*.key` files
- Store private keys in secure secret management (e.g., GitHub Secrets, HashiCorp Vault, AWS Secrets Manager)
- Only commit the public key (`cosign.pub`) if needed for verification documentation
- Choose a strong password and store it securely (e.g., password manager)

**Sign with key:**

After generating the key pair, you can sign images using the private key:

```bash
# Set the password (the one you used when generating the key pair)
export COSIGN_PASSWORD=your_key_password

# Set the path to your private key
export COSIGN_KEY_PATH=./cosign.key

# Sign the image
make docker-sign IMAGE=ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234
```

**Note:** You'll need to provide the same password you used when generating the key pair. The password is required to decrypt the private key for signing.

## Usage

### Build and Push with Signing

**Local (with signing):**
```bash
# Build, push, and sign
make docker-push SIGN=true
```

**Local (without signing):**
```bash
# Build and push only
make docker-push
```

### Sign Existing Image

If you need to sign an already-pushed image:

```bash
# Keyless signing
export COSIGN_EXPERIMENTAL=1
export GITHUB_TOKEN=your_token
make docker-sign IMAGE=ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234

# Key-based signing
export COSIGN_PASSWORD=your_key_password
export COSIGN_KEY_PATH=./cosign.key
make docker-sign IMAGE=ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234
```

### Verify Image Signature

**Verify keyless signature:**
```bash
cosign verify ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234
```

**Verify key-based signature:**
```bash
cosign verify --key cosign.pub ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234
```

**Using Makefile:**
```bash
make docker-verify IMAGE=ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234
```

## CI/CD Integration

The CD workflow (`.github/workflows/cd.yml`) automatically:

1. Builds the Docker image with immutable versioning
2. Pushes the image to GHCR
3. Signs the image using keyless signing with cosign
4. Pushes the Helm chart

**Workflow steps:**
```yaml
- name: Build and push Docker image
  # ... builds and pushes image

- name: Install cosign
  uses: sigstore/cosign-installer@v3

- name: Sign Docker image
  env:
    COSIGN_EXPERIMENTAL: 1
  run: cosign sign $IMAGE
```

## Verification in Kubernetes

### Using Policy Controller

You can enforce signature verification in Kubernetes using [policy-controller](https://docs.sigstore.dev/policy-controller/overview/):

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: dm-nkp-gitops-custom-app-policy
spec:
  images:
    - glob: "ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:**"
  authorities:
    - keyless:
        url: https://fulcio.sigstore.dev
        identities:
          - issuer: https://token.actions.githubusercontent.com
            subject: "https://github.com/deepak-muley/dm-nkp-gitops-custom-app/.github/workflows/cd.yml@refs/heads/main"
```

### Manual Verification in CI/CD

Add verification step to your deployment pipeline:

```yaml
- name: Verify image signature
  run: |
    cosign verify \
      ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:$IMAGE_VERSION
```

## Best Practices

### 1. Always Sign Production Images

Ensure all production images are signed:
- CI/CD automatically signs images
- For manual builds, use `SIGN=true`

### 2. Verify Before Deployment

Always verify image signatures before deploying:
- Use policy-controller in Kubernetes
- Add verification steps in CI/CD pipelines
- Verify manually when pulling images locally

### 3. Store Public Keys Securely

If using key-based signing:
- Store public keys in version control
- Keep private keys in secure secret management
- Rotate keys periodically

### 4. Use Immutable Versioning

Combine signing with immutable versioning:
- Each image gets a unique version (with Git SHA)
- Signatures are tied to specific versions
- Prevents version conflicts and overwrites

## Troubleshooting

### Signing Fails in CI/CD

**Issue:** `COSIGN_EXPERIMENTAL` not set
**Solution:** Ensure the workflow has `id-token: write` permission

**Issue:** Authentication fails
**Solution:** Verify `GITHUB_TOKEN` has `write:packages` permission

### Verification Fails

**Issue:** "no matching signatures"
**Solution:** 
- Ensure the image was signed
- Check the image tag/version is correct
- Verify you're using the correct public key (if key-based)

**Issue:** "certificate verification failed"
**Solution:**
- For keyless signing, ensure you're connected to the internet
- Check that Fulcio/Rekor services are accessible

### Local Signing Issues

**Issue:** cosign not found
**Solution:**
```bash
# Install cosign
brew install cosign
# or download from: https://github.com/sigstore/cosign/releases
```

**Issue:** Key-based signing fails
**Solution:**
- Verify `COSIGN_PASSWORD` is set correctly (must match the password used when generating the key)
- Check `COSIGN_KEY_PATH` points to the correct private key file
- Ensure the key file has correct permissions (600): `chmod 600 cosign.key`
- Verify the key file exists and is not corrupted
- Make sure you're using the correct key pair (private key matches the public key used for verification)

**Issue:** How to generate cosign keys
**Solution:**
```bash
# Install cosign first (if not already installed)
brew install cosign  # macOS
# or download from: https://github.com/sigstore/cosign/releases

# Generate key pair
cosign generate-key-pair

# You'll be prompted to:
# 1. Enter a password (to encrypt the private key)
# 2. Confirm the password
# 
# This creates:
# - cosign.key (private key, encrypted - NEVER commit this!)
# - cosign.pub (public key, unencrypted - safe to share)
```

## References

- [cosign Documentation](https://github.com/sigstore/cosign)
- [Sigstore Project](https://www.sigstore.dev/)
- [Keyless Signing Guide](https://github.com/sigstore/cosign/blob/main/KEYLESS.md)
- [Policy Controller](https://docs.sigstore.dev/policy-controller/overview/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

