//
//  MenuBarClickArbitrationPolicy.swift
//  Barline
//

public enum MenuBarClickArbitrationPolicy {
    /// Returns whether a global click should be treated as occurring in empty
    /// menu-bar space rather than on an application menu, control item, cached
    /// status item, or notch.
    public static func isEmptyMenuBarSpace(
        isInsideMenuBar: Bool,
        isInsideApplicationMenu: Bool,
        isInsidePrimaryControlItem: Bool,
        isInsideCachedMenuBarItem: Bool,
        isInsideNotch: Bool,
        eventTargetsPrimaryControlItem: Bool = false
    ) -> Bool {
        isInsideMenuBar &&
            !eventTargetsPrimaryControlItem &&
            !isInsideApplicationMenu &&
            !isInsidePrimaryControlItem &&
            !isInsideCachedMenuBarItem &&
            !isInsideNotch
    }
}
