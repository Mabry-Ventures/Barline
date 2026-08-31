//
//  MenuBarSectionAvailabilityPolicy.swift
//  Barline
//

public enum MenuBarSectionAvailabilityPolicy {
    /// The primary section remains actionable while AppKit reconnects its
    /// visibly present scene-backed status item. Divider-backed sections still
    /// require their control items to be installed.
    public static func isEnabled(
        isPrimarySection: Bool,
        controlItemIsAdded: Bool
    ) -> Bool {
        isPrimarySection || controlItemIsAdded
    }
}
