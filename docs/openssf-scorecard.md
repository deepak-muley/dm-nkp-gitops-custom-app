# OpenSSF Scorecard Integration

This repository uses [OpenSSF Scorecard](https://github.com/ossf/scorecard) to assess and improve its security posture. Scorecard evaluates repositories against security best practices and provides actionable recommendations.

## What is OpenSSF Scorecard?

OpenSSF Scorecard is an automated security tool that checks a repository against a set of security best practices. It evaluates various aspects of your repository's security posture, including:

- Security policy presence
- Branch protection rules
- Code review requirements
- Dependency update tools
- Automated security updates
- Signed releases
- Binary artifacts
- Dangerous workflow patterns
- Token permissions
- And 20+ more checks

## Integration

### Workflow Configuration

**File:** `.github/workflows/security.yml`

The Scorecard analysis runs as part of the Security Scanning workflow:

```yaml
scorecard:
  name: OpenSSF Scorecard Analysis
  runs-on: ubuntu-latest
  permissions:
    contents: read
    id-token: write
    security-events: write
    actions: read
  steps:
    - name: Checkout repository
      uses: actions/checkout@v4
      with:
        persist-credentials: false

    - name: Run OpenSSF Scorecard
      uses: ossf/scorecard-action@v2
      with:
        results_file: results.sarif
        results_format: sarif
        publish_results: true
        repo: ${{ github.repository }}

    - name: Upload Scorecard results to GitHub Security
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: results.sarif
        category: scorecard
```

### When It Runs

- **On Pull Requests:** Every PR is analyzed
- **On Pushes:** Every push to main/master/dev branches
- **Scheduled:** Daily at 2 AM UTC (along with other security scans)

### Results

**GitHub Security Tab:**

- Results are uploaded as SARIF format
- Viewable in the Security tab under "Code scanning alerts"
- Category: `scorecard`

**OpenSSF API:**

- Results are published to the OpenSSF API (for public repositories)
- Viewable at: <https://api.securityscorecards.dev/projects/github.com/deepak-muley/dm-nkp-gitops-custom-app>
- Provides historical tracking and comparison

## Scorecard Checks

Scorecard evaluates your repository against these checks:

### Security Policy

- **Security-Policy:** Presence of SECURITY.md
- **Signed-Releases:** Releases are signed
- **Binary-Artifacts:** No binary artifacts in source

### Code Review

- **Code-Review:** PRs require code review
- **Contributors:** Multiple contributors
- **Maintained:** Repository is actively maintained

### Branch Protection

- **Branch-Protection:** Branch protection rules enabled
- **Dangerous-Workflow:** No dangerous workflow patterns
- **Token-Permissions:** Minimal token permissions

### Dependencies

- **Dependency-Update-Tool:** Automated dependency updates
- **Fuzzing:** Fuzzing tests present
- **Packaging:** Proper packaging configuration

### CI/CD

- **CI-Tests:** CI tests run on PRs
- **SAST:** Static analysis in CI
- **License:** License file present

### Vulnerabilities

- **Vulnerabilities:** Known vulnerabilities addressed
- **Pinned-Dependencies:** Dependencies are pinned

## Viewing Results

### In GitHub

1. Go to **Security** tab in your repository
2. Click on **Code scanning alerts**
3. Filter by **Category: scorecard**
4. Review individual checks and their scores

### In OpenSSF API

For public repositories, view results at:

```
https://api.securityscorecards.dev/projects/github.com/{owner}/{repo}
```

### Scorecard Badge

Add a Scorecard badge to your README:

```markdown
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/deepak-muley/dm-nkp-gitops-custom-app/badge)](https://api.securityscorecards.dev/projects/github.com/deepak-muley/dm-nkp-gitops-custom-app)
```

## Improving Your Score

### Quick Wins

1. **Add SECURITY.md**
   - Create a security policy file
   - Document vulnerability reporting process

2. **Enable Branch Protection**
   - Require PR reviews
   - Require status checks
   - Prevent force pushes

3. **Add License File**
   - Include LICENSE file
   - Specify license type

4. **Enable Dependency Updates**
   - Use Dependabot
   - Configure automated updates

5. **Sign Releases**
   - Sign Git tags
   - Sign container images (cosign)

6. **Review Workflow Permissions**
   - Use minimal token permissions
   - Avoid dangerous workflow patterns

### Advanced Improvements

1. **Add Fuzzing Tests**
   - Integrate fuzzing tools
   - Run fuzzing in CI

2. **Pin Dependencies**
   - Pin all dependencies
   - Use specific versions

3. **Add SAST Tools**
   - CodeQL
   - Static analysis tools

4. **Security Testing**
   - Security-focused tests
   - Vulnerability scanning

## Configuration

### Customizing Checks

You can customize which checks to run by modifying the workflow:

```yaml
- name: Run OpenSSF Scorecard
  uses: ossf/scorecard-action@v2
  with:
    results_file: results.sarif
    results_format: sarif
    publish_results: true
    repo: ${{ github.repository }}
    # Optional: specify checks to run
    checks: Security-Policy,Code-Review,Branch-Protection
```

### Publishing Results

For public repositories, results are automatically published to OpenSSF API. For private repositories, you can:

1. Make the repository public (if appropriate)
2. Or disable publishing by setting `publish_results: false`

## Troubleshooting

### Scorecard Not Running

**Check:**

1. Workflow file exists: `.github/workflows/security.yml`
2. Workflow is enabled in Actions tab
3. Permissions are correctly set

### Results Not Appearing

**Check:**

1. SARIF upload succeeded
2. Security tab is enabled
3. Code scanning is enabled in repository settings

### Low Scores

**Action:**

1. Review Scorecard checks
2. Address failing checks
3. Re-run workflow to see improvements

## Resources

- **Official Documentation:** <https://github.com/ossf/scorecard>
- **Scorecard Checks:** <https://github.com/ossf/scorecard/blob/main/docs/checks.md>
- **OpenSSF API:** <https://api.securityscorecards.dev>
- **Best Practices Guide:** <https://github.com/ossf/scorecard/blob/main/docs/checks.md>

## Related Documentation

- [Security Scanning Workflow](./github-actions-reference.md#security-scanning)
- [Production Ready Checklist](./production-ready-checklist.md)
- [Security Policy](../SECURITY.md)
