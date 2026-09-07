# Barline 1.0.9

## Refinements

- Restore temporarily revealed menu bar items to their original section and
  display, even when a neighboring icon disappears or moves.
- Preserve interrupted item restoration across app restarts. Review it using
  **Layouts & Focus → Recovery → Retry Item Restoration**.
- Alternatively, confirm **Keep Current Item Positions** to cancel recovery
  without moving icons; prior recovery records are archived locally.
- Pause restoration after three unsuccessful attempts instead of retrying
  indefinitely. Layout changes wait for pending restoration to finish.
- Require source- and binary-bound interaction, performance and helper recovery
  evidence before installed-candidate qualification can pass.

## Distribution checklist

This file is release-note content, not a qualification certificate. Before public
publication, require the new source's local full gate and installed receipts,
signed/notarized archive, working public appcast and package, and a real signed
upgrade with retained preferences and one running app. No macOS 27 runtime or
release-duration soak claim is made; those lanes remain user-deferred.
