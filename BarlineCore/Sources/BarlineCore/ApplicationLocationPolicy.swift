//
//  ApplicationLocationPolicy.swift
//  Barline
//

/// Decides whether Barline should offer to move itself into an Applications
/// folder before first use. macOS ties Accessibility and Screen Recording
/// grants to where an app runs, so a grant made while Barline runs from
/// Downloads, a disk image, or an App Translocation path can be lost once the
/// app is moved.
public enum ApplicationLocationPolicy {
    public enum Location: Equatable, Sendable {
        /// `/Applications` or the user's `~/Applications`, at any depth.
        case applicationsFolder
        /// A read-only App Translocation path. Its original location is not
        /// available through public API, so the user has to move the app.
        case translocated
        /// A volume mounted under `/Volumes`, such as the release disk image.
        case mountedVolume
        /// Any other location the app can be copied out of.
        case elsewhere
    }

    public enum Offer: Equatable, Sendable {
        case none
        /// Copy the app into `/Applications`, relaunch it there, and move the
        /// old copy to the Trash.
        case moveAutomatically
        /// Explain how to drag the app into Applications.
        case moveManually
    }

    public static func location(bundlePath: String, homeDirectory: String) -> Location {
        let path = standardized(bundlePath)
        if path.split(separator: "/").contains("AppTranslocation") {
            return .translocated
        }
        if isWithin(path, folder: "/Volumes") {
            return .mountedVolume
        }
        if isWithin(path, folder: "/Applications")
            || isWithin(path, folder: standardized(homeDirectory) + "/Applications")
        {
            return .applicationsFolder
        }
        return .elsewhere
    }

    /// - Parameters:
    ///   - isEligible: `false` for development and test builds, which run from
    ///     build products and must never be interrupted by this offer.
    ///   - userDeclined: The user chose not to be asked again.
    public static func offer(for location: Location, isEligible: Bool, userDeclined: Bool) -> Offer {
        guard isEligible, !userDeclined else {
            return .none
        }
        switch location {
        case .applicationsFolder:
            return .none
        case .translocated, .mountedVolume:
            return .moveManually
        case .elsewhere:
            return .moveAutomatically
        }
    }

    /// Resolves `.` and `..` components and duplicate or trailing slashes so a
    /// path cannot pass a folder check by traversal.
    static func standardized(_ path: String) -> String {
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    /// Requires a separator after the folder, so `/ApplicationsBackup` is not
    /// treated as being inside `/Applications`. Compares without regard to case:
    /// macOS volumes are case-insensitive by default, so `/applications` names
    /// the same folder, and misclassifying it would offer to move an installed
    /// copy onto itself.
    private static func isWithin(_ path: String, folder: String) -> Bool {
        path.lowercased().hasPrefix(folder.lowercased() + "/")
    }
}
