# Security policy

## Reporting a vulnerability

Do not post exploit details, credentials, private screenshots, process lists,
or other personal data in a public issue.

Use [GitHub private vulnerability reporting](https://github.com/Mabry-Ventures/mv-barline/security/advisories/new).
Private reporting is enabled for this repository. Reports go to the repository
maintainers, not the public issue tracker. Include the affected build, expected
and observed behavior, and the smallest safe reproduction. No response-time
commitment is currently made.

## Scope and supported versions

Barline has no cloud account system. Vulnerabilities involving local macOS
permission handling, the XPC boundary, update verification, signing, imported
layouts, or diagnostic data are in scope. General feature requests and ordinary
UI bugs belong in [GitHub Issues](https://github.com/Mabry-Ventures/mv-barline/issues)
without sensitive attachments.

No public binary release is available yet. The first qualified release and its
security-support policy will be listed here when published. Development builds
and unqualified macOS versions should not be mistaken for supported releases.
