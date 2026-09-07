# Barline 1.0.9

Candidate build 17 also excludes windowless primary-control and shelf clicks
from smart rehide using captured event positions. Build 16 opened the shelf but
failed its target journey when the panel closed before its controls were ready.
It is not a qualified release. Build 17 requires all fresh candidate gates.

Candidate build 16 additionally gives the primary control window exclusive
ownership of its click and uses captured event coordinates in empty-space
arbitration. Build 15's first installed shelf-open still failed, so it is not
eligible for distribution. Build 16 requires fresh qualification.

Candidate build 15 added ownership checks for delayed rehide work, so an older
click or timer cannot dismiss a later shelf presentation. Build 14's required
receipts passed but its follow-up burst had one timeout; the full gate did not
pass. Build 15 requires fresh qualification before distribution.

Candidate build 14 superseded build 12, which failed installed qualification:
physical screen intersection did not establish a hidden item's display owner.
The failed candidate and its evidence remain retained, not distribution-ready.
Build 13's four installed click/restoration lanes passed; build 14 additionally
corrects the performance harness's hosted-window matching. Full XCUITest still
requires macOS UI Automation authentication; do not describe that gate as passed.

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
