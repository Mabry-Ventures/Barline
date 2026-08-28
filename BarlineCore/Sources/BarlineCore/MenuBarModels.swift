import Foundation

public struct MenuBarItemID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let bundleIdentifier: String
    public let accessibilityIdentifier: String?
    public let title: String?
    public let alias: String?
    public let fallbackFingerprint: String?

    public init(
        bundleIdentifier: String,
        accessibilityIdentifier: String? = nil,
        title: String? = nil,
        alias: String? = nil,
        fallbackFingerprint: String? = nil
    ) {
        self.bundleIdentifier = Self.normalize(bundleIdentifier)
        self.accessibilityIdentifier = Self.normalizeOptional(accessibilityIdentifier)
        self.title = Self.normalizeOptional(title)
        self.alias = Self.normalizeOptional(alias)
        self.fallbackFingerprint = Self.normalizeOptional(fallbackFingerprint)
    }

    public var description: String {
        [bundleIdentifier, accessibilityIdentifier, title, alias, fallbackFingerprint]
            .compactMap(\.self)
            .joined(separator: "|")
    }

    public var isPlausiblyStable: Bool {
        !bundleIdentifier.isEmpty && (
            accessibilityIdentifier != nil || title != nil || alias != nil || fallbackFingerprint != nil
        )
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalize(value)
        return normalized.isEmpty ? nil : normalized
    }
}

public struct MenuBarDisplayID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var description: String {
        value
    }
}

public enum MenuBarSection: String, Codable, CaseIterable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

public struct MenuBarItemDescriptor: Codable, Hashable, Sendable {
    public let id: MenuBarItemID
    public let section: MenuBarSection
    public let order: Int
    public let displayID: MenuBarDisplayID?
    public let isSystemItem: Bool
    public let isBarlineControlItem: Bool

    public init(
        id: MenuBarItemID,
        section: MenuBarSection,
        order: Int,
        displayID: MenuBarDisplayID? = nil,
        isSystemItem: Bool = false,
        isBarlineControlItem: Bool = false
    ) {
        self.id = id
        self.section = section
        self.order = order
        self.displayID = displayID
        self.isSystemItem = isSystemItem
        self.isBarlineControlItem = isBarlineControlItem
    }
}

public struct MenuBarSnapshot: Codable, Hashable, Sendable {
    public let generation: UInt64
    public let capturedAt: Date
    public let items: [MenuBarItemDescriptor]
    public let displayIDs: Set<MenuBarDisplayID>
    public let activeSpaceIsValid: Bool
    public let menuTrackingIsActive: Bool

    public init(
        generation: UInt64,
        capturedAt: Date,
        items: [MenuBarItemDescriptor],
        displayIDs: Set<MenuBarDisplayID>,
        activeSpaceIsValid: Bool,
        menuTrackingIsActive: Bool = false
    ) {
        self.generation = generation
        self.capturedAt = capturedAt
        self.items = items
        self.displayIDs = displayIDs
        self.activeSpaceIsValid = activeSpaceIsValid
        self.menuTrackingIsActive = menuTrackingIsActive
    }
}
