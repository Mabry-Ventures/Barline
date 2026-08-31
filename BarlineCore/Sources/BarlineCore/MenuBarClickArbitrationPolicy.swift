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
        isInsideNotch: Bool
    ) -> Bool {
        isInsideMenuBar &&
            !isInsideApplicationMenu &&
            !isInsidePrimaryControlItem &&
            !isInsideCachedMenuBarItem &&
            !isInsideNotch
    }
}
