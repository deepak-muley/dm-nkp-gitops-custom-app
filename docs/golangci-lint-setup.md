# golangci-lint Setup

## Overview

`golangci-lint` is a fast Go linter that runs multiple linters in parallel. It's used by the pre-commit hooks to ensure code quality.

## Installation

### Option 1: Official Install Script (Recommended)

```bash
# Install to $GOPATH/bin (default: ~/go/bin)
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin latest

# Verify installation
golangci-lint --version
```

### Option 2: Using Homebrew (macOS)

```bash
brew install golangci-lint

# Verify installation
golangci-lint --version
```

### Option 3: Using Go Install

```bash
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# Verify it's in your PATH
which golangci-lint
```

## Verify Installation

After installation, verify it works:

```bash
# Check version
golangci-lint --version

# Check if it's in PATH
which golangci-lint

# Test with a Go file
golangci-lint run ./cmd/app/main.go
```

## PATH Configuration

If `golangci-lint` is not found after installation, ensure `$GOPATH/bin` is in your PATH:

```bash
# Check GOPATH
go env GOPATH

# Add to ~/.zshrc (or ~/.bashrc)
export PATH="$(go env GOPATH)/bin:$PATH"

# Reload shell
source ~/.zshrc
```

## Pre-commit Integration

The pre-commit hook is already configured in `.pre-commit-config.yaml`:

```yaml
- id: golangci-lint
  args: ['--timeout=5m']
  files: \.go$
```

### Test Pre-commit Hook

```bash
source .venv/bin/activate
pre-commit run golangci-lint --all-files
```

## Configuration

The repository includes a `.golangci.yml` configuration file that customizes which linters run and their settings.

### View Current Configuration

```bash
cat .golangci.yml
```

### Run with Custom Config

```bash
golangci-lint run --config .golangci.yml ./...
```

## Common Issues

### Issue: "golangci-lint not found"

**Solution:**

1. Verify installation: `which golangci-lint`
2. Check PATH: `echo $PATH | grep -q "$(go env GOPATH)/bin"`
3. Add to PATH if missing (see above)

### Issue: "golangci-lint not installed or available in the PATH"

**Solution:**

1. Install golangci-lint (see Installation above)
2. Ensure it's in your PATH
3. Restart your terminal
4. Test: `golangci-lint --version`

### Issue: Pre-commit still can't find golangci-lint

**Solution:**

1. Clean pre-commit cache:

   ```bash
   source .venv/bin/activate
   pre-commit clean
   pre-commit install
   ```

2. Verify PATH in pre-commit environment:

   ```bash
   pre-commit run golangci-lint --verbose
   ```

## Usage

### Run on All Files

```bash
golangci-lint run ./...
```

### Run on Specific Package

```bash
golangci-lint run ./cmd/app
```

### Run with Auto-fix

```bash
golangci-lint run --fix ./...
```

### Run with Timeout

```bash
golangci-lint run --timeout=5m ./...
```

## Related Documentation

- [Pre-commit Setup](./pre-commit-setup.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [golangci-lint Official Docs](https://golangci-lint.run/)
