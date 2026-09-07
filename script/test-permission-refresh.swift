import Cocoa
import Combine

/// Link the production Permission implementation against nonprompting test
/// adapters. This harness never changes TCC, opens Settings, or launches Barline.
enum AXHelpers {
    @discardableResult static func isProcessTrusted(prompt _: Bool = false) -> Bool {
        false
    }
}

enum ScreenCapture {
    static let permissionDidChangeNotification = Notification.Name("BarlineScreenCapturePermissionDidChange")
    static func checkPermissions() -> Bool {
        false
    }

    static func requestPermissions() {}
}

@main
struct PermissionRefreshTests {
    @MainActor
    static func main() async {
        var allowed = false
        var requests = 0
        var publications = [Bool]()
        let permission = Permission(
            title: "Test", details: [], isRequired: false, settingsURL: nil,
            check: { allowed }, request: { requests += 1 }
        )
        let observer = permission.$hasPermission.sink { publications.append($0) }
        precondition(!permission.refresh())
        allowed = true
        precondition(permission.refresh())
        allowed = false
        precondition(!permission.refresh())
        allowed = true
        // Background accessory interaction can signal a preflight decision
        // without NSApplication becoming active or opening a settings window.
        NotificationCenter.default.post(name: ScreenCapture.permissionDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(50))
        precondition(permission.hasPermission)
        precondition(publications == [false, true, false, true])
        precondition(requests == 0)
        allowed = false
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(50))
        precondition(!permission.hasPermission)
        permission.stopCheck()
        observer.cancel()
        print("PASS: deny/grant/revoke/grant, contextual/background/workspace refresh; zero permission prompts")
    }
}
