//
//  MenuBarRecoveryPolicy.swift
//  Shared
//

import CoreGraphics

/// Pure recovery decisions used while WindowServer and AppKit rebuild menu bar
/// state after sleep or a display configuration change.
enum MenuBarRecoveryPolicy {
    /// Returns whether every reported menu bar window was resolved into a
    /// usable window description.
    static func snapshotIsComplete<ID: Hashable>(
        reportedIDs: [ID],
        resolvedIDs: [ID]
    ) -> Bool {
        reportedIDs.count == resolvedIDs.count &&
            Set(reportedIDs) == Set(resolvedIDs)
    }

    /// Returns whether all control items required by the current settings are
    /// present in a menu bar snapshot.
    static func hasRequiredControlItems(
        hasVisibleControlItem: Bool,
        hasAlwaysHiddenControlItem: Bool,
        requiresVisibleControlItem: Bool,
        requiresAlwaysHiddenControlItem: Bool
    ) -> Bool {
        (!requiresVisibleControlItem || hasVisibleControlItem) &&
            (!requiresAlwaysHiddenControlItem || hasAlwaysHiddenControlItem)
    }

    /// Resolves an optional private-API result to a usable display identifier.
    static func resolvedDisplayID(
        _ displayID: CGDirectDisplayID?,
        fallback: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        displayID ?? fallback
    }

    /// Returns whether control-item geometry proves that the system menu bar is
    /// hidden. Missing geometry is transient after wake and is not proof.
    static func shouldHidePanel(
        controlItemFrame: CGRect?,
        screenFrame: CGRect?
    ) -> Bool {
        guard let controlItemFrame, let screenFrame else {
            return false
        }
        return controlItemFrame.maxY > screenFrame.maxY
    }
}
