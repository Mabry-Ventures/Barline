//
//  SpaceInfo.swift
//  Barline
//

/// Information for a desktop space.
struct SpaceInfo: Hashable {
    /// The space's identifier.
    let spaceID: Int

    /// A Boolean value that indicates whether the space is fullscreen.
    let isFullscreen: Bool

    /// Returns the active space.
    static func activeSpace() -> SpaceInfo {
        SpaceInfo(spaceID: 0, isFullscreen: false)
    }
}
