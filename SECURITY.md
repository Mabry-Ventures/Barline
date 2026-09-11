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

The latest published release, currently
[Barline 1.0.11](https://github.com/Mabry-Ventures/mv-barline/releases/tag/v1.0.11),
is the supported version. Report issues against that release or the current
`main` branch. Development builds and unqualified macOS versions are not
supported releases.
