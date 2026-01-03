# Security Policy

## Supported Versions

We actively support security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < 1.0.0 | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security vulnerability, please follow these steps:

### 1. **Do NOT** create a public GitHub issue

Security vulnerabilities should be reported privately to prevent exploitation.

### 2. Report the vulnerability

Please email security concerns to: <deepak.muley@gmail.com>

Or use GitHub Security Advisories:

- Go to the repository's **Security** tab
- Click **Report a vulnerability**
- Fill out the security advisory form

### 3. Include the following information

- Type of vulnerability (e.g., XSS, SQL injection, authentication bypass)
- Full paths of source file(s) related to the vulnerability
- Location of the affected code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the vulnerability

### 4. Response timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity and complexity

### 5. Disclosure policy

- We will acknowledge receipt of your vulnerability report
- We will keep you informed of our progress
- We will notify you when the vulnerability is fixed
- We will credit you in the security advisory (if you wish)

### Security Best Practices

When reporting vulnerabilities, please:

- Act in good faith
- Do not access or modify data that does not belong to you
- Do not disrupt our services
- Do not violate any laws
- Do not disclose the vulnerability publicly until we've had a chance to address it

## Security Scanning

This repository uses automated security scanning:

- **CodeQL**: Static code analysis
- **Trivy**: Container vulnerability scanning
- **Dependabot**: Dependency vulnerability alerts
- **Secret Scanning**: Detects accidentally committed secrets

See `.github/workflows/security.yml` for details.

## Security Updates

Security updates are released as:

- **Patch versions** for critical vulnerabilities
- **Minor versions** for important security improvements
- **Security advisories** published in the repository

## Security Checklist

Before deploying to production:

- [ ] All dependencies are up to date
- [ ] Security scans pass
- [ ] No known vulnerabilities in dependencies
- [ ] Container images are signed
- [ ] Secrets are not hardcoded
- [ ] Security contexts are configured
- [ ] Network policies are in place (if applicable)
- [ ] RBAC is properly configured
- [ ] Monitoring and alerting are enabled

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [Container Security Best Practices](https://docs.docker.com/engine/security/)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security)

## Contact

For security-related questions or concerns:

- **Email**: <deepak.muley@gmail.com>
- **GitHub Security Advisories**: Use the Security tab in this repository

---

**Note**: For security concerns, contact <deepak.muley@gmail.com> or use GitHub Security Advisories
