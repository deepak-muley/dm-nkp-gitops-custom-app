# ADR-0003: Immutable Versioning with Git SHA

## Status

Accepted

## Context

We need a versioning strategy that:
- Prevents overwrites of existing artifacts
- Enables traceability from artifact to source code
- Works with both Docker images and Helm charts
- Supports semantic versioning for releases

## Decision

We will use immutable versioning that combines semantic versioning with Git SHA:
- **Docker Images**: `{VERSION}-sha-{GIT_SHA}` (e.g., `0.1.0-sha-abc1234`)
- **Helm Charts**: `{VERSION}+sha-{GIT_SHA}` (e.g., `0.1.0+sha-abc1234`)

Note: Docker tags cannot contain `+`, so we use `-` for images. Helm charts (OCI) support `+` as per SemVer build metadata.

## Consequences

### Positive
- **Immutability**: Each build produces a unique, non-overwritable artifact
- **Traceability**: Can trace any artifact back to exact source code commit
- **Reproducibility**: Can reproduce any build from Git SHA
- **Semantic Versioning**: Still supports semantic versioning for releases
- **CI/CD Integration**: Works seamlessly with GitHub Actions

### Negative
- **Longer Tags**: Version strings are longer
- **Manual Tagging**: Requires manual semantic version tags for releases
- **Version Parsing**: Slightly more complex version parsing logic

### Implementation
- CI workflow uses Git SHA from `github.sha`
- CD workflow uses Git SHA from `github.sha`
- Makefile auto-detects Git SHA from current branch
- Release workflow can use semantic version tags

