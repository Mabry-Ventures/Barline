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

/// A Foundation-only rectangle used at the compatibility boundary.
///
/// Raw WindowServer identifiers never leave the helper. Geometry is safe to
/// project into the app because every mutation re-resolves the stable item ID
/// against a fresh helper-side enumeration before acting.
public struct MenuBarRect: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = MenuBarRect(x: 0, y: 0, width: 0, height: 0)

    public var isFiniteAndNonnegative: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite &&
            width >= 0 && height >= 0
    }
}

public struct MenuBarItemDescriptor: Codable, Hashable, Sendable {
    public let id: MenuBarItemID
    public let section: MenuBarSection
    public let order: Int
    public let displayID: MenuBarDisplayID?
    public let isSystemItem: Bool
    public let isBarlineControlItem: Bool
    public let tagNamespace: String?
    public let title: String?
    public let displayName: String
    public let ownerProcessIdentifier: Int32?
    public let sourceProcessIdentifier: Int32?
    public let bounds: MenuBarRect
    public let isOnScreen: Bool
    public let isMovable: Bool
    public let canBeHidden: Bool
    public let isBentoBox: Bool
    public let isSystemClone: Bool
    public let isResponsive: Bool

    public init(
        id: MenuBarItemID,
        section: MenuBarSection,
        order: Int,
        displayID: MenuBarDisplayID? = nil,
        isSystemItem: Bool = false,
        isBarlineControlItem: Bool = false,
        tagNamespace: String? = nil,
        title: String? = nil,
        displayName: String = "Menu Bar Item",
        ownerProcessIdentifier: Int32? = nil,
        sourceProcessIdentifier: Int32? = nil,
        bounds: MenuBarRect = .zero,
        isOnScreen: Bool = false,
        isMovable: Bool = true,
        canBeHidden: Bool = true,
        isBentoBox: Bool = false,
        isSystemClone: Bool = false,
        isResponsive: Bool = true
    ) {
        self.id = id
        self.section = section
        self.order = order
        self.displayID = displayID
        self.isSystemItem = isSystemItem
        self.isBarlineControlItem = isBarlineControlItem
        self.tagNamespace = tagNamespace
        self.title = title
        self.displayName = displayName
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.bounds = bounds
        self.isOnScreen = isOnScreen
        self.isMovable = isMovable
        self.canBeHidden = canBeHidden
        self.isBentoBox = isBentoBox
        self.isSystemClone = isSystemClone
        self.isResponsive = isResponsive
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
