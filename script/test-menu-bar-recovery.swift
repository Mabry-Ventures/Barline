import CoreGraphics
import Foundation

@main
private enum MenuBarRecoveryPolicyTests {
    static func main() {
        assertEqual(
            MenuBarRecoveryPolicy.snapshotIsComplete(
                reportedWindowIDs: [10, 20, 30],
                resolvedWindowIDs: [30, 20, 10]
            ),
            true,
            "accepts a fully resolved snapshot regardless of ordering"
        )

        assertEqual(
            MenuBarRecoveryPolicy.snapshotIsComplete(
                reportedWindowIDs: [10, 20, 30],
                resolvedWindowIDs: [20, 10]
            ),
            false,
            "rejects a post-wake snapshot with an unresolved window"
        )

        assertEqual(
            MenuBarRecoveryPolicy.hasRequiredControlItems(
                hasVisibleControlItem: false,
                hasAlwaysHiddenControlItem: true,
                requiresVisibleControlItem: true,
                requiresAlwaysHiddenControlItem: true
            ),
            false,
            "rejects a snapshot missing a required visible control item"
        )

        assertEqual(
            MenuBarRecoveryPolicy.hasRequiredControlItems(
                hasVisibleControlItem: true,
                hasAlwaysHiddenControlItem: false,
                requiresVisibleControlItem: true,
                requiresAlwaysHiddenControlItem: false
            ),
            true,
            "allows the optional always-hidden control item to be absent"
        )

        assertEqual(
            MenuBarRecoveryPolicy.resolvedDisplayID(nil, fallback: 42),
            42,
            "falls back when the private active-display lookup is unavailable"
        )

        assertEqual(
            MenuBarRecoveryPolicy.shouldHidePanel(
                controlItemFrame: nil,
                screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
            ),
            false,
            "does not treat missing post-wake geometry as proof that the menu bar is hidden"
        )

        assertEqual(
            MenuBarRecoveryPolicy.shouldHidePanel(
                controlItemFrame: CGRect(x: 1_400, y: 983, width: 20, height: 32),
                screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
            ),
            true,
            "hides the panel when the control item is vertically offscreen"
        )

        print("PASS: menu bar recovery policy")
    }

    private static func assertEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ description: String
    ) {
        guard actual == expected else {
            fputs("FAIL: \(description) — expected \(expected), got \(actual)\n", stderr)
            exit(1)
        }
    }
}
