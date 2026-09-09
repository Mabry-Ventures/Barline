# Troubleshooting Barline

Start with the app version/build and macOS version. Check
[known limitations](docs/KNOWN_LIMITATIONS.md) and
[supported configurations](docs/SUPPORTED_CONFIGURATIONS.md) before changing
permissions or resetting saved data.

## An item disappeared

A missing item may be in the hidden or always-hidden section, or its owning app
may have stopped providing it. Barline arranges items; it does not uninstall
their apps. Option-click Barline's menu bar control to reveal always-hidden
items. The layout settings also offer **Show Hidden Items in Menu Bar** as a
native recovery route.

Check that the owning app is running and has its own menu bar icon enabled.
macOS or an app can recreate an item with a new identity. Avoid repeatedly
applying layouts while an item is disappearing and reappearing.

## Changes do not stick, or an operation reports an error

Do not assume the requested arrangement succeeded because an icon moved briefly.
Check permissions and that only the intended Barline copy is running. If
**Retry Item Restoration** is available in **Layouts & Focus**, use it after
the owning app and display are available again. **Keep Current Item Positions**
accepts the current positions instead of retrying the previous restoration;
use it only if that is what you want.

Save a reviewed support bundle and report a reproducible example. Do not delete
layout or recovery files as a first troubleshooting step.

## Permissions look enabled, but Barline still asks for them

In System Settings, check the Accessibility and Screen & System Audio Recording
entries for the installed Barline app. Development and signed release builds
can have different code-signing identities even when their names match.

Quit duplicate or older copies and reopen the intended installed copy once.
If the mismatch persists, report the app version and how it was installed.
Do not reset all macOS privacy permissions or grant access to unrelated apps.
Screen recording is optional; lack of preview images is different from an
Accessibility failure.

## The shelf will not open or an item will not activate

Right-click Barline's control to reach Settings, then use **Show Hidden Items in
Menu Bar** from the layout pane to try the native route. Note whether the issue
happened after an update, display change, sleep, or a permission change.

Opening Settings should not be required before normal clicks work. If it is,
that is a bug to report, not an expected setup step. Include whether a left-click,
right-click, or an app-specific popover failed; do not attach private app content.

## My system menu bar automatically hides

The secondary shelf and graphical layout editor require an always-visible
menu bar. With system auto-hide enabled, Barline uses native reveal instead;
move the pointer to the top edge and use the system menu bar items there.

Use **Open Menu Bar System Settings** from Barline's layout pane if you want to
change that system preference. Barline does not change it for you. Full-screen
Spaces and auto-hide are distinct test configurations; see
[supported configurations](docs/SUPPORTED_CONFIGURATIONS.md).

## Where are my Focus modes?

macOS owns Focus modes. Barline saves menu bar **layouts**, not a second set of
Focus modes. Add Barline as a Focus Filter in System Settings, then choose a
saved layout there. See [Focus integration](docs/FOCUS_AND_APP_INTENTS.md).
System Focus execution still requires candidate-bound qualification.

## Sharing a useful bug report

Use [GitHub Issues](https://github.com/Mabry-Ventures/mv-barline/issues). Include
the app version/build, macOS version, display setup, auto-hide setting,
reproduction steps, expected behavior, and what happened instead.

In **Advanced → Diagnostics**, create a support bundle, review its preview,
and choose where to save it. Nothing is automatically sent. Redact screenshots
and review every attachment; never post credentials, private screen content,
raw process lists, or unrelated logs. See [support bundles](docs/SUPPORT_BUNDLE.md)
and the [security policy](SECURITY.md).
