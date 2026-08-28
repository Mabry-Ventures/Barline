# GitHub repository configuration

These settings require the canonical Barline GitHub repository and repository
administration access. They are not asserted as configured in the current local
repository.

## Main branch ruleset

After publishing `local/macos-arm64` once so GitHub recognizes the context,
configure a ruleset for `main` with:

- pull requests required, with zero required approvals for the solo owner;
- conversations resolved and linear history required;
- current-head status checks `repo-hygiene` and `local/macos-arm64` required;
- force pushes and branch deletion blocked;
- no merge queue and no signed-commit requirement;
- an owner/admin emergency bypass that remains visible in the audit log.

Do not add a macOS or self-hosted Actions runner as a substitute for the local
commit status.

## Repository-native security

Enable the dependency graph, Dependabot alerts, Dependabot security updates,
secret scanning, and push protection where the hosting plan supports them.
Dependabot is monthly and limited to two open PRs per ecosystem; there is no
auto-merge. Every dependency update still needs the exact-head local full gate.

## Workflow supply chain

The sole workflow uses a read-only token and checkout pinned to the reviewed
v7.0.1 commit. It downloads actionlint 1.7.12 for Linux only, pins its SHA-256 in
the workflow, and verifies the archive before extraction. The runner-provided
ShellCheck and Ruby runtimes supply shell and YAML/XML/JSON validation. No
workflow secret is required or referenced.
