# Security Policy

## Supported Versions

We actively support the following versions of rack_jwt_aegis with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| 0.0.x   | :x:                |

## Reporting a Vulnerability

The rack_jwt_aegis team takes security bugs seriously. We appreciate your efforts to responsibly disclose your findings, and will make every effort to acknowledge your contributions.

### How to Report Security Issues

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by emailing **security@example.com** or by using [GitHub Security Advisories](https://github.com/kanutocd/rack_jwt_aegis/security/advisories/new).

Please include the following information in your report:

- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

This information will help us triage your report more quickly.

### What to Expect

- **Acknowledgment**: We will acknowledge receipt of your vulnerability report within 48 hours.
- **Initial Response**: We will send you a more detailed response within 96 hours indicating the next steps in handling your report.
- **Progress Updates**: We will keep you informed about our progress throughout the process.
- **Resolution Timeline**: We aim to resolve critical security issues within 7 days, and other issues within 30 days.

### Disclosure Policy

- **Coordinated Disclosure**: We ask that you give us a reasonable amount of time to investigate and mitigate an issue before any disclosure to the public or a third-party.
- **Credit**: We will credit you for your discovery in our security advisory and/or release notes (unless you prefer to remain anonymous).

### Security Features

rack_jwt_aegis includes several security features by design:

- **JWT Signature Verification**: All JWT tokens are cryptographically verified
- **Token Expiration Validation**: Expired tokens are automatically rejected
- **Multi-tenant Isolation**: Subdomain and company slug validation prevents cross-tenant access
- **Input Validation**: All configuration and request inputs are validated
- **Secure Defaults**: Conservative defaults that prioritize security over convenience
- **Audit Logging**: Configurable debug logging for security monitoring

### Security Best Practices

When using rack_jwt_aegis:

1. **Use Strong Secrets**: Always use cryptographically strong, randomly generated JWT secrets
2. **Environment Variables**: Store secrets in environment variables, never in code
3. **HTTPS Only**: Always use HTTPS in production environments
4. **Token Expiration**: Set appropriate token expiration times
5. **Regular Updates**: Keep the gem updated to the latest version
6. **Monitor Logs**: Enable debug logging in development and monitor authentication failures

### Security Contact

For security-related questions or concerns, please contact:

- **Email**: security@example.com
- **GPG Key**: Available upon request

Thank you for helping keep rack_jwt_aegis and our users safe!