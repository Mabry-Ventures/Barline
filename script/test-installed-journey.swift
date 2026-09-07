#!/usr/bin/env swift

// Production journey: no notification bridges and no AXPress shortcuts.
// Run only against the one already-running signed app and a controlled fixture.
import AppKit
import CoreGraphics
import Foundation

struct Receipt: Decodable {
    let session: String
    let processIdentifier: Int32
    let sequence: Int
    let button: String
    let activations: Int
    let opens: Int
    let closes: Int
    let actions: Int
    let visible: Bool
}

enum JourneyError: Error { case failed(String) }
let environment = ProcessInfo.processInfo.environment

func required(_ name: String) throws -> String {
    guard let value = environment[name], !value.isEmpty else { throw JourneyError.failed("missing_\(name)") }
    return value
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
    else { return nil }
    return CGRect(origin: point, size: extent)
}

func matches(_ element: AXUIElement, _ name: String) -> Bool {
    [kAXTitleAttribute, kAXDescriptionAttribute, "AXIdentifier"].contains {
        (attribute(element, $0) as? String) == name
    }
}

/// Depth and count caps ensure an unexpected AX tree cannot become an unbounded
/// process-inventory crawl. Only these two explicitly selected apps are queried.
func find(_ root: AXUIElement, named name: String, depth: Int = 0) -> AXUIElement? {
    guard depth < 12 else { return nil }
    if matches(root, name) {
        return root
    }
    let children = attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
    for child in children.prefix(100) {
        if let found = find(child, named: name, depth: depth + 1) {
            return found
        }
    }
    return nil
}

func extras(_ app: AXUIElement) -> AXUIElement? {
    guard let value = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func windows() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}

func bounds(_ row: [String: Any]) -> CGRect? {
    guard let value = row[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: value as CFDictionary)
}

func click(_ rect: CGRect, right: Bool = false) throws {
    let point = CGPoint(x: rect.midX, y: rect.midY)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: right ? .rightMouseDown : .leftMouseDown,
                             mouseCursorPosition: point, mouseButton: right ? .right : .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: right ? .rightMouseUp : .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: right ? .right : .left)
    else { throw JourneyError.failed("event_creation") }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    up.post(tap: .cghidEventTap)
}

func wait(_ reason: String, seconds: TimeInterval = 6, condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if condition() {
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    throw JourneyError.failed(reason)
}

func sameFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.midX - rhs.midX) <= 2 && abs(lhs.midY - rhs.midY) <= 2 && abs(lhs.width - rhs.width) <= 2
}

do {
    guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
        throw JourneyError.failed("harness_accessibility_and_screen_recording_required_no_prompt")
    }
    let appPID = try Int32(required("BARLINE_EXPECTED_PID")) ?? 0
    let fixturePID = try Int32(required("BARLINE_FIXTURE_PID")) ?? 0
    let bundleID = try required("BARLINE_APP_BUNDLE_IDENTIFIER")
    let expectedPath = try required("BARLINE_CANDIDATE_APP")
    let session = try required("BARLINE_FIXTURE_SESSION")
    let receiptURL = try URL(fileURLWithPath: required("BARLINE_FIXTURE_RECEIPT"))
    let target = environment["BARLINE_JOURNEY_TARGET"] ?? "BF Native"
    guard ["BF Native", "BF Popover", "BF Delayed"].contains(target) else {
        throw JourneyError.failed("unsupported_fixture_target")
    }
    let right = environment["BARLINE_JOURNEY_BUTTON"] == "right"
    guard let runningApp = NSRunningApplication(processIdentifier: appPID),
          runningApp.bundleIdentifier == bundleID,
          runningApp.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: expectedPath).standardizedFileURL.path,
          NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count == 1,
          let fixtureApp = NSRunningApplication(processIdentifier: fixturePID),
          fixtureApp.bundleURL?.lastPathComponent == "BarlineFixture.app"
    else { throw JourneyError.failed("exact_single_candidate_or_fixture_mismatch") }
    let app = AXUIElementCreateApplication(appPID)
    let fixture = AXUIElementCreateApplication(fixturePID)
    AXUIElementSetMessagingTimeout(app, 0.2)
    AXUIElementSetMessagingTimeout(fixture, 0.2)
    func receipt() -> Receipt? {
        guard let data = try? Data(contentsOf: receiptURL), data.count < 4096,
              let value = try? JSONDecoder().decode(Receipt.self, from: data),
              value.session == session, value.processIdentifier == fixturePID
        else { return nil }
        return value
    }
    func targetFrame() -> CGRect? {
        guard let bar = extras(fixture), let element = find(bar, named: target) else { return nil }
        return frame(element)
    }
    func shelfVisible() -> Bool {
        windows().contains { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == appPID &&
            $0[kCGWindowName as String] as? String == "Barline Bar"
        }
    }
    guard let baseline = receipt(), !baseline.visible, let original = targetFrame(), !shelfVisible() else {
        throw JourneyError.failed("fixture_ready_and_closed_shelf_baseline_required")
    }
    // The chosen fixture must actually be hidden; a visible-item click is not
    // evidence that reveal/activation/restore works. Do not move user items here.
    let displays = NSScreen.screens.compactMap { screen -> CGRect? in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDisplayBounds(number.uint32Value)
    }
    guard !windows().contains(where: { row in
        guard let rect = bounds(row) else { return false }
        return sameFrame(rect, original) && displays.contains { $0.intersects(rect) }
    }) else { throw JourneyError.failed("fixture_target_must_be_placed_in_hidden_section_first") }
    guard let sourceBar = extras(app) else { throw JourneyError.failed("barline_source_extras_unavailable") }
    let sourceFrames = (attribute(sourceBar, kAXChildrenAttribute) as? [AXUIElement] ?? []).compactMap(frame)
    let controls = windows().filter { $0[kCGWindowName as String] as? String == "Barline.ControlItem.Visible" }
    let verifiedControls = controls.filter { row in
        guard let rect = bounds(row), let owner = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return false }
        let validHost = owner == appPID || NSRunningApplication(processIdentifier: owner)?.bundleIdentifier == "com.apple.controlcenter"
        return validHost && sourceFrames.contains { sameFrame($0, rect) }
    }
    guard verifiedControls.count == 1, let control = verifiedControls.first.flatMap(bounds) else {
        throw JourneyError.failed("status_control_source_host_relationship_unverified")
    }
    try click(control)
    try wait("shelf_did_not_open") { shelfVisible() }
    guard let shelfItem = find(app, named: target), let shelfFrame = frame(shelfItem), shelfFrame.width > 0 else {
        throw JourneyError.failed("synthetic_fixture_not_accessible_in_shelf")
    }
    try click(shelfFrame, right: right)
    try wait("target_did_not_receive_click_and_open_interface") {
        guard let current = receipt(), current.activations > baseline.activations,
              current.opens > baseline.opens, current.visible,
              current.button == (right ? "right" : "left") else { return false }
        // The witness reports its delegate transition; independently require the
        // target's real actionable menu/popover control to be exposed by AppKit.
        return find(fixture, named: "Fixture Receipt Action") != nil
    }
    guard let action = find(fixture, named: "Fixture Receipt Action"), let actionFrame = frame(action) else {
        throw JourneyError.failed("target_interface_action_unavailable")
    }
    try click(actionFrame)
    try wait("target_action_or_close_not_observed") {
        guard let current = receipt() else { return false }
        return current.actions > baseline.actions && current.closes > baseline.closes && !current.visible
    }
    try wait("item_position_not_restored", seconds: 25) {
        guard let restored = targetFrame() else { return false }
        return sameFrame(restored, original)
    }
    guard !runningApp.isTerminated, !fixtureApp.isTerminated else { throw JourneyError.failed("process_changed") }
    let result: [String: Any] = try [
        "schema": 1, "verdict": "PASS", "target": target, "button": right ? "right" : "left",
        "physicalEventPath": true, "shelfObserved": true, "targetReceiptObserved": true,
        "targetInterfaceObserved": true, "targetActionObserved": true, "restorationObserved": true,
        "sourceSHA": required("BARLINE_SOURCE_SHA"),
        "executableSHA256": required("BARLINE_EXECUTABLE_SHA256"),
        "version": Bundle(url: runningApp.bundleURL!)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        "hostOS": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
} catch {
    // Failure reasons are controlled tokens, never AX tree contents or app titles.
    let reason: String = if case let JourneyError.failed(code) = error {
        code
    } else {
        "harness_error"
    }
    let result = ["verdict": "FAIL", "reason": reason]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
    exit(1)
}
