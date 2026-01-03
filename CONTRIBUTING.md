# Contributing Guide

Thank you for your interest in contributing to dm-nkp-gitops-custom-app!

## Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/dm-nkp-gitops-custom-app.git
   cd dm-nkp-gitops-custom-app
   ```

3. Set up development environment:
   ```bash
   make deps
   ```

4. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Making Changes

1. Make your changes
2. Run tests:
   ```bash
   make test
   ```

3. Run linters:
   ```bash
   make lint
   ```

4. Ensure all tests pass before committing

## Commit Messages

Follow conventional commit format:
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `test:` for test changes
- `refactor:` for code refactoring
- `chore:` for maintenance tasks

Example:
```
feat: add new metric for request latency
```

## Pull Request Process

1. Update documentation if needed
2. Add tests for new functionality
3. Ensure all tests pass
4. Update CHANGELOG.md (if applicable)
5. Create a pull request with a clear description

## Code Style

- Follow Go standard formatting (`go fmt`)
- Use `golangci-lint` for linting
- Write tests for all new functionality
- Keep functions small and focused
- Add comments for exported functions

## Testing

- Write unit tests for new code
- Add integration tests for new endpoints
- Update e2e tests if deployment changes

## Questions?

Open an issue for questions or discussions.

