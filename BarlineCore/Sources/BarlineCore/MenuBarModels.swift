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

    /// A collision-free opaque search identity. Field labels, explicit nil
    /// markers, and byte counts preserve which stable-ID component supplied a
    /// value without exposing this representation as a user-facing label.
    public var searchDocumentID: SearchDocumentID {
        let fields: [(String, String?)] = [
            ("bundle", bundleIdentifier),
            ("accessibility", accessibilityIdentifier),
            ("title", title),
            ("alias", alias),
            ("fingerprint", fallbackFingerprint),
        ]
        let encoded = fields.map { label, value in
            guard let value else { return "\(label):nil" }
            return "\(label):\(value.utf8.count):\(value)"
        }.joined(separator: "|")
        return SearchDocumentID("menu-item|\(encoded)")
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

/// An opaque alias used to recognize a physical display when macOS assigns it
/// a different runtime identifier after reconnecting.
public struct MenuBarDisplayHardwareFingerprint: Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let value: String

    public init(_ value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var isWellFormed: Bool {
        guard value.hasPrefix("v1:") else { return false }
        let digest = value.dropFirst(3)
        return digest.count == 64 && digest.allSatisfy(\.isHexDigit)
    }

    public var description: String {
        "<redacted-display-fingerprint>"
    }
}

public struct MenuBarDisplayIdentity: Codable, Hashable, Sendable {
    public let runtimeID: MenuBarDisplayID
    public let hardwareFingerprint: MenuBarDisplayHardwareFingerprint?

    public init(
        runtimeID: MenuBarDisplayID,
        hardwareFingerprint: MenuBarDisplayHardwareFingerprint? = nil
    ) {
        self.runtimeID = runtimeID
        self.hardwareFingerprint = hardwareFingerprint
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
    public let displayIdentities: [MenuBarDisplayIdentity]?
    public let activeSpaceIsValid: Bool
    public let menuTrackingIsActive: Bool

    public init(
        generation: UInt64,
        capturedAt: Date,
        items: [MenuBarItemDescriptor],
        displayIDs: Set<MenuBarDisplayID>,
        displayIdentities: [MenuBarDisplayIdentity]? = nil,
        activeSpaceIsValid: Bool,
        menuTrackingIsActive: Bool = false
    ) {
        self.generation = generation
        self.capturedAt = capturedAt
        self.items = items
        self.displayIDs = displayIDs
        self.displayIdentities = displayIdentities
        self.activeSpaceIsValid = activeSpaceIsValid
        self.menuTrackingIsActive = menuTrackingIsActive
    }

    public func displayIdentity(for runtimeID: MenuBarDisplayID) -> MenuBarDisplayIdentity? {
        displayIdentities?.first { $0.runtimeID == runtimeID }
    }
}

public struct MenuBarMovePlanner: Sendable {
    public init() {}

    /// Returns the helper's global, section-relative candidate index. Prefer
    /// the last candidate on the item's display without mistaking a
    /// display-local count for the helper's global index space.
    public func destinationIndex(
        in snapshot: MenuBarSnapshot,
        section: MenuBarSection,
        preferredDisplayID: MenuBarDisplayID?
    ) -> Int {
        let candidates = snapshot.items.filter { $0.section == section }
        guard !candidates.isEmpty else { return 0 }
        if let preferredDisplayID,
           let index = candidates.lastIndex(where: { $0.displayID == preferredDisplayID })
        {
            return index
        }
        return candidates.count - 1
    }

    public func resultMatches(
        _ operation: MenuBarMoveOperation,
        in snapshot: MenuBarSnapshot
    ) -> Bool {
        let candidates = snapshot.items.filter { $0.section == operation.section }
        guard !candidates.isEmpty else { return false }
        let expectedIndex = min(max(operation.index, 0), candidates.count - 1)
        return candidates.indices.contains(expectedIndex)
            && candidates[expectedIndex].id == operation.itemID
            && operation.destinationDisplayID.map {
                candidates[expectedIndex].displayID == $0
            } != false
    }

    public func restoreOperations(for snapshot: MenuBarSnapshot) -> [MenuBarMoveOperation] {
        MenuBarSection.allCases.flatMap { section in
            snapshot.items
                .filter { $0.section == section }
                .enumerated()
                .map { index, descriptor in
                    MenuBarMoveOperation(
                        itemID: descriptor.id,
                        section: section,
                        index: index,
                        destinationDisplayID: descriptor.displayID
                    )
                }
        }
    }
}
