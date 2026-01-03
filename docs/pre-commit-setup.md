# Pre-Commit Hooks Setup

This guide explains how to set up and use pre-commit hooks with a Python virtual environment to avoid polluting your system Python installation.

## Requirements

- **Python 3.8 or higher** (pre-commit-hooks requires Python >= 3.8)
- `python3` command available in PATH

Check your Python version:
```bash
python3 --version
```

If you have Python 3.7 or lower, you need to upgrade:
- **macOS**: `brew install python@3.11` or `brew install python@3.12`
- **Linux**: `sudo apt-get install python3.8` (or higher)
- **Windows**: Download from [python.org](https://www.python.org/downloads/)

## Quick Start

### 1. Initial Setup

Run the setup script to create a virtual environment and install pre-commit:

```bash
./scripts/setup-pre-commit.sh
```

This script will:
- Check Python version (requires >= 3.8)
- Create a Python virtual environment at `.venv/`
- Install pre-commit in the virtual environment
- Install the pre-commit hooks
- Provide usage instructions

**Note**: If you previously created a `.venv/` with an older Python version, remove it first:
```bash
rm -rf .venv
./scripts/setup-pre-commit.sh
```

### 2. Activate Virtual Environment

Before using pre-commit, activate the virtual environment:

```bash
# Option 1: Use the helper script
source scripts/activate-pre-commit.sh

# Option 2: Direct activation
source .venv/bin/activate
```

### 3. Use Pre-Commit

Once the virtual environment is activated, you can use pre-commit:

```bash
# Run on staged files (automatic on git commit)
pre-commit run

# Run on all files
pre-commit run --all-files

# Update hooks (when .pre-commit-config.yaml changes)
pre-commit autoupdate
```

### 4. Deactivate

When done, deactivate the virtual environment:

```bash
deactivate
```

## Using Makefile Targets

The Makefile includes convenient targets (requires venv activation first):

```bash
# Activate venv first
source .venv/bin/activate

# Then use make targets
make pre-commit          # Run on staged files
make pre-commit-all      # Run on all files
make pre-commit-update   # Update hooks
```

## How It Works

### Virtual Environment

- **Location**: `.venv/` in the repository root
- **Purpose**: Isolated Python environment for pre-commit
- **Git**: Already added to `.gitignore` (won't be committed)

### Pre-Commit Hooks

The hooks run automatically on `git commit` when:
1. Virtual environment is activated
2. Hooks are installed (done by setup script)
3. Files are staged for commit

### Manual Execution

You can also run hooks manually:
- `pre-commit run` - On staged files
- `pre-commit run --all-files` - On all files
- `pre-commit run <hook-id>` - Specific hook

## Troubleshooting

### Virtual Environment Not Found

**Error**: `Virtual environment not found`

**Solution**:
```bash
./scripts/setup-pre-commit.sh
```

### Pre-Commit Not Found

**Error**: `pre-commit: command not found`

**Solution**: Activate the virtual environment first:
```bash
source .venv/bin/activate
```

### Hooks Not Running on Commit

**Issue**: Hooks don't run automatically

**Solution**: Verify hooks are installed:
```bash
source .venv/bin/activate
pre-commit install
```

### Python 3 Not Found

**Error**: `python3 is not installed`

**Solution**: Install Python 3:
- **macOS**: `brew install python@3.11` or `brew install python@3.12`
- **Linux**: `sudo apt-get install python3.8` (or higher)
- **Windows**: Download from [python.org](https://www.python.org/)

### Python Version Too Old

**Error**: `Package 'pre-commit-hooks' requires a different Python: 3.7.x not in '>=3.8'`

**Solution**: 
1. Upgrade Python to 3.8 or higher (see above)
2. Remove the existing virtual environment:
   ```bash
   rm -rf .venv
   ```
3. Re-run the setup script:
   ```bash
   ./scripts/setup-pre-commit.sh
   ```

The setup script now checks Python version and will fail early with a helpful error message if Python < 3.8 is detected.

## Configuration

The pre-commit configuration is in `.pre-commit-config.yaml`. It includes:

- **General hooks**: Trailing whitespace, end-of-file, YAML/JSON validation
- **Go hooks**: Formatting, linting, vet
- **Secret detection**: Prevents committing secrets
- **Markdown linting**: Ensures markdown quality
- **Shell linting**: Validates shell scripts
- **YAML linting**: Validates YAML files
- **Helm linting**: Validates Helm charts

## Updating Hooks

When `.pre-commit-config.yaml` changes or to get latest hook versions:

```bash
source .venv/bin/activate
pre-commit autoupdate
```

## Reinstalling Hooks

To reinstall hooks (e.g., after updating config):

```bash
source .venv/bin/activate
pre-commit uninstall
pre-commit install
```

## Skipping Hooks

In rare cases, you may need to skip hooks:

```bash
# Skip all hooks for one commit
git commit --no-verify

# Skip specific hook
SKIP=<hook-id> git commit
```

**Note**: Only skip hooks when absolutely necessary. Hooks help maintain code quality.

## Integration with CI/CD

Pre-commit hooks are also run in CI/CD:

- **CI Workflow**: Runs `pre-commit run --all-files` in GitHub Actions
- **Local Development**: Hooks run automatically on commit

## Best Practices

1. **Always activate venv** before using pre-commit
2. **Run hooks before committing** to catch issues early
3. **Update hooks regularly** with `pre-commit autoupdate`
4. **Don't skip hooks** unless absolutely necessary
5. **Fix hook failures** rather than skipping them

## Files Created

- `.venv/` - Python virtual environment (gitignored)
- `.pre-commit-config.yaml` - Hook configuration
- `scripts/setup-pre-commit.sh` - Setup script
- `scripts/activate-pre-commit.sh` - Activation helper

## Additional Resources

- [Pre-commit Documentation](https://pre-commit.com/)
- [Pre-commit Hooks](https://pre-commit.com/hooks.html)
- [Python Virtual Environments](https://docs.python.org/3/tutorial/venv.html)

---

**Last Updated**: 2024  
**Setup Script**: `scripts/setup-pre-commit.sh`

