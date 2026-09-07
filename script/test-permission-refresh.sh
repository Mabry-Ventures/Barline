#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /private/tmp/barline-permission-tests.XXXXXX)"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    "$ROOT/Barline/Permissions/Permission.swift" \
    "$ROOT/script/test-permission-refresh.swift" \
    -o "$TEST_DIR/permission-refresh"
"$TEST_DIR/permission-refresh"

# Keep the epoch check at the UI publication boundary, not only inside the
# background worker before its final actor hop.
# Swift dollar-prefixed identifiers below are literal source assertions.
# shellcheck disable=SC2016
ruby -e '
  overlay = File.read(ARGV.fetch(0))
  publication = overlay.split("private func performUpdates(", 2).last&.split("/// Shows the panel.", 2)&.first
  abort "missing final background capture permission-epoch guard" unless publication &&
    publication.index("ScreenCapture.canPublishCapture(from: capture.permissionGeneration)") &&
    publication.index("ScreenCapture.canPublishCapture(from: capture.permissionGeneration)") < publication.index("updateDesktopWallpaper(with: capture)")
  cache = File.read(ARGV.fetch(1))
  abort "invalid capture replies must remain excluded" unless cache.include?("result.excluded = items.filter { result.images[$0.stableID] == nil }")
  publication = cache.split("var updatedImages =", 2).last
  abort "missing final item capture permission-epoch guard" unless publication &&
    publication.index("ScreenCapture.canPublishCapture(from: screenCaptureGeneration)") < publication.index("images = updatedImages")
  puts "PASS: final capture publication checks permission epochs; invalid decoded replies remain retryable"
' "$ROOT/Barline/MenuBar/Appearance/MenuBarOverlayPanel.swift" \
  "$ROOT/Barline/MenuBar/MenuBarItems/MenuBarItemImageCache.swift"

# shellcheck disable=SC2016
ruby -e '
  manager = File.read(ARGV.fetch(0))
  setup = manager.split("func performSetup(with appState: AppState)", 2).last&.split("/// Configuration discovery", 2)&.first
  abort "auto-hide configuration must initialize before window setup" unless setup &&
    setup.index("refreshSystemMenuBarConfiguration()") < setup.index("configureCancellables()")
  abort "auto-hide must observe late window attachment" unless manager.include?("hiddenSection.controlItem.$window") &&
    manager.include?(".switchToLatest()") && !manager.include?("let window = hiddenSection.controlItem.window")
  ["UserDefaults.didChangeNotification", "NSApplication.didBecomeActiveNotification", "NSWorkspace.didWakeNotification"].each do |notification|
    abort "auto-hide lifecycle refresh missing" unless manager.include?(notification)
  end
  puts "PASS: auto-hide initializes before windows attach and observes later window/lifecycle changes"
' "$ROOT/Barline/MenuBar/MenuBarManager.swift"
