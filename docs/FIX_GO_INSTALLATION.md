# Fix Go Installation Issue

## Problem
Unit tests are failing with the error:
```
package encoding/pem is not in std (/usr/local/Cellar/go/1.25.5/libexec/src/encoding/pem)
```

This indicates a corrupted or incomplete Go installation.

## Solution

### Option 1: Reinstall Go via Homebrew (Recommended)

```bash
# Uninstall current Go installation
brew uninstall go

# Clean Homebrew cache
brew cleanup

# Reinstall Go (latest stable version)
brew install go

# Verify installation
go version
go env GOROOT

# Re-download dependencies
cd /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app
go mod download
go mod tidy
```

### Option 2: Install Go from Official Source

```bash
# Download and install latest stable Go from https://golang.org/dl/
# Then update your PATH:
export PATH=/usr/local/go/bin:$PATH

# Or for a specific version:
export PATH=/usr/local/go1.21.6/bin:$PATH  # Replace with your version
```

### Option 3: Fix Current Installation

If you want to try fixing the current installation:

```bash
# Clear Go build cache
go clean -cache -modcache

# Rebuild standard library
cd /usr/local/Cellar/go/1.25.5/libexec/src
./make.bash --no-clean 2>&1 | tee /tmp/go-rebuild.log

# Or try reinstalling via Homebrew
brew reinstall go
```

### Verify Fix

After reinstalling, verify the fix:

```bash
cd /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app
go test ./internal/metrics
go test ./internal/server
go test ./internal/telemetry

# Or run all unit tests
make unit-tests
```

## Temporary Workaround

If you need to proceed immediately without fixing Go, the e2e script will continue despite test failures. However, it's recommended to fix the Go installation as soon as possible.

## Note on Go 1.25.5

Go 1.25.5 may not be a stable release. The latest stable Go releases are typically in the 1.21.x or 1.22.x series. Consider upgrading to a stable release.
