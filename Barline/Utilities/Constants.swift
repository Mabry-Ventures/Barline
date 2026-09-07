//
//  Constants.swift
//  Barline
//

import BarlineCore
import Foundation

enum Constants {
    /// An explicit user-opened website, never a payment or entitlement service.
    static var supportURL: URL? {
        SupportDestination.url(from: Bundle.main.object(forInfoDictionaryKey: "BarlineSupportURL") as? String)
    }

    // swiftlint:disable force_unwrapping

    /// The version string in the app's bundle.
    static let versionString = Bundle.main.versionString!

    /// The build string in the app's bundle.
    static let buildString = Bundle.main.buildString!

    /// The user-readable copyright string in the app's bundle.
    static let copyrightString = Bundle.main.copyrightString!

    /// The app's bundle identifier.
    static let bundleIdentifier = Bundle.main.bundleIdentifier!

    /// The app's display name.
    static let displayName = Bundle.main.displayName!

    // swiftlint:enable force_unwrapping
}
