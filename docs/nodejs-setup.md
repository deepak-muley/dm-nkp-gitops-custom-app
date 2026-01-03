# Node.js Setup for Pre-commit Hooks

## Problem

The `markdownlint` pre-commit hook requires Node.js 14.18.0+ or 16.0.0+ (preferably 18+ LTS). If you see this error:

```
Error: Cannot find module 'node:fs'
```

It means your Node.js version is too old.

## Solution: Upgrade Node.js

### Option 1: Using Homebrew (Recommended for macOS)

1. **Check current version:**

   ```bash
   node --version
   ```

2. **Upgrade Node.js:**

   ```bash
   brew upgrade node
   ```

   Or install the latest LTS version:

   ```bash
   brew install node@18
   # or
   brew install node@20
   ```

3. **Verify installation:**

   ```bash
   node --version
   # Should show v18.x.x or v20.x.x
   ```

4. **Update pre-commit cache:**

   ```bash
   source .venv/bin/activate
   pre-commit clean
   pre-commit install
   ```

### Option 2: Using nvm (Node Version Manager)

If you prefer to manage multiple Node.js versions:

1. **Install nvm:**

   ```bash
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
   ```

2. **Install and use Node.js 18 LTS:**

   ```bash
   nvm install 18
   nvm use 18
   nvm alias default 18
   ```

3. **Verify:**

   ```bash
   node --version
   ```

4. **Update pre-commit cache:**

   ```bash
   source .venv/bin/activate
   pre-commit clean
   pre-commit install
   ```

### Option 3: Download from nodejs.org

1. Visit [nodejs.org](https://nodejs.org/)
2. Download the LTS version (18.x or 20.x)
3. Install the package
4. Restart your terminal
5. Verify: `node --version`

## Verify Fix

After upgrading, test the markdownlint hook:

```bash
source .venv/bin/activate
pre-commit run markdownlint --all-files
```

## Alternative: Skip markdownlint

If you can't upgrade Node.js right now, you can skip the markdownlint hook:

```bash
SKIP=markdownlint git commit -m "your message"
```

Or disable it in `.pre-commit-config.yaml` by commenting out the markdownlint hook.

## Troubleshooting

### Issue: Multiple Node.js versions

If you have multiple Node.js installations:

1. **Check which node is being used:**

   ```bash
   which node
   ```

2. **Check PATH:**

   ```bash
   echo $PATH
   ```

3. **Ensure Homebrew's node is first in PATH:**

   ```bash
   # Add to ~/.zshrc or ~/.bashrc
   export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
   ```

### Issue: Pre-commit still uses old Node.js

1. **Clear pre-commit cache:**

   ```bash
   pre-commit clean
   ```

2. **Reinstall hooks:**

   ```bash
   pre-commit install
   ```

3. **Test again:**

   ```bash
   pre-commit run markdownlint --all-files
   ```

## Recommended Node.js Version

- **Minimum:** Node.js 16.0.0+
- **Recommended:** Node.js 18.x LTS or 20.x LTS
- **Current LTS:** Node.js 20.x (as of 2024)

## Related Documentation

- [Pre-commit Setup](./pre-commit-setup.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
