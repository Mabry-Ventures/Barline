import ApplicationServices
import Foundation

enum AuditFailure: Error, CustomStringConvertible {
    case invalidPID
    case permissionUnavailable
    case attribute(String)
    case noWindows
    case noInteractiveElements([String])
    case unlabeledElements([String])

    var description: String {
        switch self {
        case .invalidPID: "invalid Barline PID"
        case .permissionUnavailable: "Accessibility access is not granted to the invoking terminal/Codex host"
        case let .attribute(name): "unable to read accessibility attribute \(name)"
        case .noWindows: "Barline has no accessibility-visible window"
        case let .noInteractiveElements(roles):
            "Barline window has no accessibility-visible interactive controls; observed roles: \(roles.joined(separator: ", "))"
        case let .unlabeledElements(roles): "unlabeled enabled controls: \(roles.joined(separator: ", "))"
        }
    }
}

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result
}

func text(_ element: AXUIElement, _ attribute: String) -> String {
    value(element, attribute) as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func walk(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 12 else { return [root] }
    return [root] + children(root).flatMap { walk($0, depth: depth + 1) }
}

do {
    guard CommandLine.arguments.count == 2, let pid = pid_t(CommandLine.arguments[1]), pid > 0 else {
        throw AuditFailure.invalidPID
    }
    guard AXIsProcessTrusted() else { throw AuditFailure.permissionUnavailable }

    let application = AXUIElementCreateApplication(pid)
    let deadline = ContinuousClock.now + .seconds(5)
    var windows = [AXUIElement]()
    while ContinuousClock.now < deadline {
        windows = value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if !windows.isEmpty {
            break
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    guard !windows.isEmpty else {
        throw AuditFailure.noWindows
    }
    let windowRoles = windows.map { text($0, kAXRoleAttribute) }
    guard windowRoles.contains(kAXWindowRole as String) else {
        throw AuditFailure.permissionUnavailable
    }

    let interactiveRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXPopUpButtonRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String,
        kAXTextFieldRole as String,
    ]
    let standardWindowButtonSubroles: Set = [
        "AXCloseButton",
        "AXMinimizeButton",
        "AXZoomButton",
        "AXFullScreenButton",
    ]
    let elements = windows.flatMap { walk($0) }
    let controls = elements.filter {
        interactiveRoles.contains(text($0, kAXRoleAttribute)) &&
            !standardWindowButtonSubroles.contains(text($0, kAXSubroleAttribute))
    }
    guard !controls.isEmpty else {
        throw AuditFailure.noInteractiveElements(Array(Set(elements.map { text($0, kAXRoleAttribute) })).sorted())
    }

    let unlabeled = controls.compactMap { control -> String? in
        let enabled = (value(control, kAXEnabledAttribute) as? Bool) ?? true
        guard enabled else { return nil }
        let labels = [
            text(control, kAXTitleAttribute),
            text(control, kAXDescriptionAttribute),
            text(control, kAXHelpAttribute),
            text(control, kAXValueAttribute),
        ]
        return labels.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ? nil
            : text(control, kAXRoleAttribute)
    }
    guard unlabeled.isEmpty else { throw AuditFailure.unlabeledElements(unlabeled) }

    print("PASS: audited \(controls.count) enabled interactive accessibility elements across \(windows.count) window(s)")
} catch AuditFailure.permissionUnavailable {
    fputs("UNAVAILABLE: \(AuditFailure.permissionUnavailable)\n", stderr)
    exit(2)
} catch {
    fputs("error: accessibility audit failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
