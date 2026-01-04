# Commit Signing Guide

This guide explains how to set up GPG commit signing to ensure all commits in PRs show as "Verified" in GitHub.

## Overview

GitHub shows commits as "Verified" when they are signed with a GPG key that is associated with your GitHub account. This provides:

- **Authenticity**: Verifies the commit was made by the expected author
- **Integrity**: Ensures the commit hasn't been tampered with
- **Trust**: Builds confidence in the codebase

## Prerequisites

- Git installed
- GPG installed (see [Step 1: Install GPG](#step-1-install-gpg) for installation instructions)
- GitHub account
- Terminal/command line access

## Step 1: Install GPG

### Check if GPG is Already Installed

First, check if GPG is already installed on your system:

```bash
gpg --version
```

If you see version information, GPG is already installed and you can skip to [Step 2: Generate a GPG Key](#step-2-generate-a-gpg-key).

### Install GPG on macOS

**Using Homebrew (Recommended):**

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install GPG
brew install gnupg

# Verify installation
gpg --version
```

**Using MacPorts:**

```bash
sudo port install gnupg
```

**Note:** macOS may have an older version of GPG pre-installed. It's recommended to install a newer version via Homebrew.

### Install GPG on Linux

**Ubuntu/Debian:**

```bash
# Update package list
sudo apt-get update

# Install GPG
sudo apt-get install gnupg

# Verify installation
gpg --version
```

**RHEL/CentOS/Fedora:**

```bash
# RHEL/CentOS 7 and earlier
sudo yum install gnupg2

# RHEL/CentOS 8+ and Fedora
sudo dnf install gnupg2

# Verify installation
gpg --version
```

**Arch Linux:**

```bash
sudo pacman -S gnupg
```

**openSUSE:**

```bash
sudo zypper install gpg2
```

### Install GPG on Windows

**Using Git for Windows (Recommended):**

Git for Windows includes GPG. If you have Git installed, GPG should be available:

```bash
# Open Git Bash and verify
gpg --version
```

**Using Chocolatey:**

```bash
# Install Chocolatey if needed: https://chocolatey.org/install
choco install gnupg

# Verify installation
gpg --version
```

**Using Scoop:**

```bash
# Install Scoop if needed: https://scoop.sh/
scoop install gnupg

# Verify installation
gpg --version
```

**Manual Installation:**

1. Download GPG from: https://www.gpg4win.org/
2. Run the installer
3. Add GPG to your PATH (usually done automatically)
4. Open a new terminal and verify: `gpg --version`

### Install GPG on WSL (Windows Subsystem for Linux)

If you're using WSL, follow the Linux installation instructions for your WSL distribution:

```bash
# For Ubuntu on WSL
sudo apt-get update
sudo apt-get install gnupg

# Verify installation
gpg --version
```

### Verify Installation

After installation, verify GPG is working correctly:

```bash
# Check version
gpg --version

# You should see output like:
# gpg (GnuPG) 2.4.x
# libgcrypt 1.10.x
# ...
```

If you encounter any issues, ensure GPG is in your PATH:

```bash
# Check if GPG is in PATH
which gpg  # Linux/macOS
where gpg  # Windows

# If not found, you may need to add it to your PATH
```

## Step 2: Generate a GPG Key

### Option A: Generate a New GPG Key

```bash
gpg --full-generate-key
```

Follow the prompts:

1. **Key type**: Press `Enter` to accept default (RSA and RSA)
2. **Key size**: Enter `4096` (recommended)
3. **Expiration**: Enter `0` for no expiration, or specify a date (e.g., `2y` for 2 years)
4. **Name**: Enter your full name
5. **Email**: Enter the email address associated with your GitHub account
6. **Comment**: Optional, press `Enter` to skip
7. **Confirm**: Type `O` for "Okay"
8. **Passphrase**: Enter a strong passphrase (you'll need this when signing commits)

### Option B: Use Existing GPG Key

If you already have a GPG key:

```bash
# List your GPG keys
gpg --list-secret-keys --keyid-format=long
```

## Step 3: Get Your GPG Key ID

```bash
gpg --list-secret-keys --keyid-format=long
```

Look for a line like:

```
sec   rsa4096/3AA5C34371567BD2 2024-01-15 [SC]
```

The key ID is the part after the `/` (e.g., `3AA5C34371567BD2`).

## Step 4: Configure Git to Use Your GPG Key

```bash
# Set your GPG key ID (replace with your actual key ID)
git config --global user.signingkey 3AA5C34371567BD2

# Enable automatic commit signing
git config --global commit.gpgsign true
```

**Note**: If you want to sign commits only for this repository:

```bash
# Remove --global flag
git config user.signingkey 3AA5C34371567BD2
git config commit.gpgsign true
```

## Step 5: Export Your Public Key

```bash
# Export your public key (replace with your key ID)
gpg --armor --export 3AA5C34371567BD2
```

This will output your public key in ASCII format. Copy the entire output, including:
- `-----BEGIN PGP PUBLIC KEY BLOCK-----`
- All the key content
- `-----END PGP PUBLIC KEY BLOCK-----`

## Step 6: Add GPG Key to GitHub

1. Go to GitHub Settings: https://github.com/settings/keys
2. Click **"New GPG key"**
3. Paste your public key
4. Click **"Add GPG key"**
5. Confirm your password if prompted

## Step 7: Verify Your Setup

### Test Commit Signing

```bash
# Create a test commit
git commit --allow-empty -m "test: verify GPG signing"

# Check if the commit is signed
git log --show-signature -1
```

You should see:

```
gpg: Signature made ...
gpg: Good signature from "Your Name <your.email@example.com>"
```

### Verify on GitHub

1. Push a commit to a branch
2. Create a PR or view the commit on GitHub
3. You should see a "Verified" badge next to the commit

## Step 8: Sign Existing Unsigned Commits (Optional)

If you want to sign commits that were already pushed:

```bash
# Re-sign the last commit
git commit --amend --no-edit -S

# Force push (only if you haven't shared the branch yet, or coordinate with your team)
git push --force-with-lease
```

**Warning**: Only do this if:
- The branch hasn't been merged
- You coordinate with your team
- You're the only one working on the branch

## Troubleshooting

### "gpg: signing failed: Inappropriate ioctl for device"

This happens when GPG can't prompt for your passphrase. Fix it by:

```bash
export GPG_TTY=$(tty)
```

Add this to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
echo 'export GPG_TTY=$(tty)' >> ~/.zshrc
source ~/.zshrc
```

### "error: gpg failed to sign the data"

**Solution 1**: Check if GPG agent is running:

```bash
gpg-agent --daemon
```

**Solution 2**: Verify your key ID is correct:

```bash
git config --get user.signingkey
gpg --list-secret-keys --keyid-format=long
```

**Solution 3**: Test GPG signing directly:

```bash
echo "test" | gpg --clearsign
```

### "No secret key" Error

This means Git can't find your GPG key. Verify:

```bash
# Check if key exists
gpg --list-secret-keys

# Verify Git is using the correct key
git config --get user.signingkey
```

### Commit Shows as "Unverified" on GitHub

1. **Verify email matches**: The email in your GPG key must match the email in your GitHub account
2. **Check key is added**: Go to https://github.com/settings/keys and verify your key is listed
3. **Verify key is not expired**: Check with `gpg --list-secret-keys`
4. **Check commit email**: Ensure the commit email matches your GPG key email:

```bash
git config user.email
```

If it doesn't match, update it:

```bash
git config --global user.email "your.email@example.com"
```

### Multiple GPG Keys

If you have multiple GPG keys (e.g., work and personal):

```bash
# List all keys
gpg --list-secret-keys --keyid-format=long

# Set the specific key for this repository
git config user.signingkey <key-id>

# Or set globally
git config --global user.signingkey <key-id>
```

## Best Practices

### 1. Use a Strong Passphrase

- Use a unique, strong passphrase for your GPG key
- Store it in a password manager
- Never share your private key

### 2. Set Key Expiration

Consider setting an expiration date (e.g., 2 years) and rotate keys periodically:

```bash
# Edit key expiration
gpg --edit-key <key-id>
# Then type: expire
# Follow prompts to set new expiration
```

### 3. Backup Your Private Key

```bash
# Export your private key (keep it secure!)
gpg --export-secret-keys --armor <key-id> > my-private-key.asc

# Store it securely (encrypted, password manager, etc.)
```

### 4. Use Different Keys for Different Contexts

- Personal projects: Personal GPG key
- Work projects: Work GPG key
- Use `git config user.signingkey` per repository

### 5. Enable Automatic Signing

Always enable automatic commit signing:

```bash
git config --global commit.gpgsign true
```

This ensures you never forget to sign commits.

## GitHub Actions Commit Signing

For commits made by GitHub Actions (e.g., automated releases, version bumps), see the workflow configuration in `.github/workflows/` which can be configured to sign commits using a bot GPG key.

## References

- [GitHub: About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [GitHub: Generating a new GPG key](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key)
- [GitHub: Adding a new GPG key to your GitHub account](https://docs.github.com/en/authentication/managing-commit-signature-verification/adding-a-new-gpg-key-to-your-github-account)
- [GitHub: Telling Git about your signing key](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key)

