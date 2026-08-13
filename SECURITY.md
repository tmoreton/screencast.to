# Security Policy

## Reporting a Vulnerability

Please do not open a public issue for a vulnerability.

Use GitHub's private vulnerability reporting for this repository when it is
available. If private reporting is not available yet, contact the maintainer
through their GitHub profile and include enough detail to reproduce the issue.

Useful details:

- Affected version or commit
- macOS version
- Whether the issue affects local recording, upload signing, shared playback, or release artifacts
- Minimal reproduction steps
- Any logs, with secrets and private recording links removed

## Scope

In scope:

- Recording permission handling
- Local recording privacy
- Upload signing and R2 object access
- Share-link behavior and expiry
- Release signing/notarization scripts

Out of scope:

- Social engineering
- Denial-of-service testing against production infrastructure
- Reports requiring access to someone else's recordings or credentials
