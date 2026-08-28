# Upstream source

Barline is a modified successor to [Ice](https://github.com/jordanbaird/Ice),
originally created by Jordan Baird and developed by its contributors. The
initial Barline source was imported from Xinyan Lu's actively maintained
[macOS compatibility fork](https://github.com/lxy1992/Ice).

## Imported baseline

- Original upstream remote: `https://github.com/jordanbaird/Ice.git`
- Community compatibility remote: `https://github.com/lxy1992/Ice.git`
- Community tag: `0.11.13-macos26.4`
- Imported commit: `79654cd8c249e2a1465a262cfda7175346fe7772`
- Upstream macOS 26 base: `6d74d25c33a9ab04307c1f222fbe68ad71847234`
- Barline vendor tag: `vendor/ice-0.11.13-macos26.4`
- Import date: 2026-08-28

The upstream base was verified as an ancestor of the selected community commit.
Both source remotes are retained as `ice-upstream` and `ice-community`. The
target repository did not have an `origin` at import time; an `origin` must be
added only when the Barline remote is provisioned.

## Refreshing upstream references

Upstream changes are reviewed and imported deliberately. Never merge either
remote's default branch into Barline without a provenance review, private-API
compatibility analysis, and the complete local macOS gate.
