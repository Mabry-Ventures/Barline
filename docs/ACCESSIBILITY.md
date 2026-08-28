# Accessibility

## Current implementation

Barline uses native SwiftUI/AppKit controls in settings and permissions. The
shelf exposes item names plus named left-click and right-click accessibility
actions. Forms and sections expose container/header semantics, the hotkey
recorder has an accessibility label, lists support arrow-key selection and
Return activation, and the gradient editor supports Delete and Escape.

Accessibility permission is also a functional macOS privacy grant used to
inspect and move other applications' menu bar items; that grant is distinct
from Barline's own VoiceOver usability.

## Validation status

The imported app's Permissions window was readable through Accessibility during
the baseline launch. A local accessibility script now checks source-level
labels, launches the exact local app build, walks visible windows through the
AX API, and rejects enabled interactive controls with no title, description,
help, or value. It requires Accessibility permission for the invoking
terminal/Codex host and returns an explicit unavailable result otherwise. No
candidate-bound pass has been recorded, and this is not a full VoiceOver,
keyboard, contrast, reduced-motion, or text-scaling audit.

## Required release pass

Before release, validate every scene and control with keyboard-only navigation
and VoiceOver, including menu bar controls, shelf items, search results, layout
editing, permissions, profiles, diagnostics, import/export, confirmation, and
recovery. Verify focus order, labels/hints/values, named actions, non-color
cues, high contrast, light/dark appearances, Reduce Motion, and text expansion.
Record the macOS build, hardware/display configuration, failures, and fixes in
the candidate's local evidence bundle.
