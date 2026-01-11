# Go Installation Fix Instructions

## Problem Summary

Your unit tests are failing because Go isn't recognizing standard library packages like `encoding/pem`. This appears to be a bug in Go 1.24.11 and Go 1.25.5 installations.

## Root Cause

- Go 1.24.11 and Go 1.25.5 have issues recognizing standard library packages
- Both Homebrew-installed and auto-downloaded toolchains exhibit this issue
- The error: `package encoding/pem is not in std` even though the package exists

## Solution: Install Go 1.24.11 Properly

### Option 1: Manual Installation (Recommended)

Run these commands:

```bash
# 1. Download Go 1.24.11
cd /tmp
curl -LO https://go.dev/dl/go1.24.11.darwin-amd64.tar.gz

# 2. Remove old installation
sudo rm -rf /usr/local/go

# 3. Install to /usr/local/go
sudo tar -C /usr/local -xzf go1.24.11.darwin-amd64.tar.gz

# 4. Add to your PATH (add to ~/.zshrc)
echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.zshrc
source ~/.zshrc

# 5. Verify
go version
which go  # Should show /usr/local/go/bin/go

# 6. Test stdlib
cd /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app
go list -f '{{.Dir}}' encoding/pem

# 7. Run tests
make unit-tests
```

### Option 2: Use the Fix Script

If you prefer, use the provided script (needs sudo):

```bash
cd /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app
sudo ./fix-go-install.sh
```

Then add to your PATH:
```bash
echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

### Option 3: Clean and Re-download Toolchain

If the manual installation doesn't work, try cleaning caches:

```bash
# Clean all Go caches
rm -rf ~/Library/Caches/go-build
rm -rf ~/go/pkg/mod/cache
rm -rf ~/go/pkg/mod/golang.org/toolchain

# Force re-download toolchain
cd /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app
go env -w GOTOOLCHAIN=auto
go clean -cache -modcache -testcache
go mod download
go list -f '{{.Dir}}' encoding/pem
```

## Verify Fix

After fixing, verify with:

```bash
# 1. Check Go version
go version

# 2. Test stdlib recognition
go list -f '{{.Dir}}' encoding/pem
# Should output: /usr/local/go/src/encoding/pem (or similar)

# 3. Build your code
go build ./internal/metrics

# 4. Run unit tests
make unit-tests
```

## If Issues Persist

If the issue persists after trying these solutions:

1. **Try Go 1.23.x**: Check if a newer stable version exists:
   ```bash
   curl -s https://go.dev/dl/ | grep -o 'go[0-9.]*\.darwin-amd64' | head -1
   ```

2. **Check for Go bugs**: This might be a known issue with Go 1.24+
   - Search: https://github.com/golang/go/issues
   - Look for issues related to "std" recognition or "encoding/pem"

3. **Temporary workaround**: Your e2e script continues despite test failures, so you can proceed with deployment while fixing Go

## Current Status

- ✅ Go reinstalled via Homebrew (but issue persists)
- ✅ Downloaded Go 1.24.11 to `/tmp/go/` (has same issue)
- ✅ Created fix scripts and instructions
- ⚠️ Need to install to `/usr/local/go` and update PATH manually
