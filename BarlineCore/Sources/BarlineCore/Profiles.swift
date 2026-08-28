//
//  Profiles.swift
//  Barline
//

import Foundation

public enum ProfileSchema {
    public static let currentVersion = 4
    public static let archiveFormatVersion = 1
}

public struct ProfileLayout: Codable, Hashable, Sendable {
    public var visible: [MenuBarItemID]
    public var hidden: [MenuBarItemID]
    public var alwaysHidden: [MenuBarItemID]

    public init(
        visible: [MenuBarItemID] = [],
        hidden: [MenuBarItemID] = [],
        alwaysHidden: [MenuBarItemID] = []
    ) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }

    public var allItemIDs: [MenuBarItemID] {
        visible + hidden + alwaysHidden
    }
}

public struct ProfileGroup: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var symbol: String?
    public var itemIDs: [MenuBarItemID]

    public init(id: UUID = UUID(), name: String, symbol: String? = nil, itemIDs: [MenuBarItemID]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.itemIDs = itemIDs
    }
}

public struct ProfileSpacer: Codable, Hashable, Sendable, Identifiable {
    public enum Placement: Codable, Hashable, Sendable {
        case beginning(MenuBarSection)
        case after(MenuBarItemID)
        case end(MenuBarSection)
    }

    public let id: UUID
    public var placement: Placement
    public var width: Double

    public init(id: UUID = UUID(), placement: Placement, width: Double = 12) {
        self.id = id
        self.placement = placement
        self.width = width
    }
}

public struct DisplayProfileOverride: Codable, Hashable, Sendable {
    public let displayID: MenuBarDisplayID
    public var layout: ProfileLayout
    public var groups: [ProfileGroup]
    public var spacers: [ProfileSpacer]

    public init(
        displayID: MenuBarDisplayID,
        layout: ProfileLayout,
        groups: [ProfileGroup] = [],
        spacers: [ProfileSpacer] = []
    ) {
        self.displayID = displayID
        self.layout = layout
        self.groups = groups
        self.spacers = spacers
    }
}

public struct ProfileAppearance: Codable, Hashable, Sendable {
    public enum Shape: String, Codable, Sendable { case standard, rounded, split }

    public static let itemSpacingRange: ClosedRange<Double> = -16 ... 16

    public var tintHex: String?
    public var gradientHex: [String]
    public var showsBorder: Bool
    public var showsShadow: Bool
    public var shape: Shape
    public var itemSpacing: Double

    public init(
        tintHex: String? = nil,
        gradientHex: [String] = [],
        showsBorder: Bool = false,
        showsShadow: Bool = false,
        shape: Shape = .standard,
        itemSpacing: Double = 0
    ) {
        self.tintHex = tintHex
        self.gradientHex = gradientHex
        self.showsBorder = showsBorder
        self.showsShadow = showsShadow
        self.shape = shape
        self.itemSpacing = itemSpacing
    }
}

public struct ProfileShelfBehavior: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var followsActiveDisplay: Bool

    public init(isEnabled: Bool = false, followsActiveDisplay: Bool = true) {
        self.isEnabled = isEnabled
        self.followsActiveDisplay = followsActiveDisplay
    }
}

public struct ProfileRevealTriggers: Codable, Hashable, Sendable {
    public var click: Bool
    public var hover: Bool
    public var scroll: Bool

    public init(click: Bool = true, hover: Bool = false, scroll: Bool = false) {
        self.click = click
        self.hover = hover
        self.scroll = scroll
    }
}

public struct ProfileAutoRehide: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var strategy: ProfileAutoRehideStrategy
    public var delaySeconds: Double

    public init(
        isEnabled: Bool = true,
        strategy: ProfileAutoRehideStrategy = .timed,
        delaySeconds: Double = 5
    ) {
        self.isEnabled = isEnabled
        self.strategy = strategy
        self.delaySeconds = delaySeconds
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case strategy
        case delaySeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        strategy = try container.decodeIfPresent(ProfileAutoRehideStrategy.self, forKey: .strategy) ?? .timed
        delaySeconds = try container.decode(Double.self, forKey: .delaySeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(strategy, forKey: .strategy)
        try container.encode(delaySeconds, forKey: .delaySeconds)
    }
}

public enum ProfileAutoRehideStrategy: String, Codable, CaseIterable, Sendable {
    case smart
    case timed
    case focusedApp
}

/// The non-layout settings that must commit and roll back with a profile's
/// menu-bar layout. Keeping this value in Core lets history and Focus recovery
/// preserve an exact custom workspace without importing AppKit state.
public struct ProfileWorkspaceState: Codable, Hashable, Sendable {
    public var appearance: ProfileAppearance
    public var shelfBehavior: ProfileShelfBehavior
    public var revealTriggers: ProfileRevealTriggers
    public var autoRehide: ProfileAutoRehide
    public var applicationMenuOverlapBehavior: ApplicationMenuOverlapBehavior

    public init(
        appearance: ProfileAppearance,
        shelfBehavior: ProfileShelfBehavior,
        revealTriggers: ProfileRevealTriggers,
        autoRehide: ProfileAutoRehide,
        applicationMenuOverlapBehavior: ApplicationMenuOverlapBehavior
    ) {
        self.appearance = appearance
        self.shelfBehavior = shelfBehavior
        self.revealTriggers = revealTriggers
        self.autoRehide = autoRehide
        self.applicationMenuOverlapBehavior = applicationMenuOverlapBehavior
    }

    public init(profile: BarlineProfile) {
        self.init(
            appearance: profile.appearance,
            shelfBehavior: profile.shelfBehavior,
            revealTriggers: profile.revealTriggers,
            autoRehide: profile.autoRehide,
            applicationMenuOverlapBehavior: profile.applicationMenuOverlapBehavior
        )
    }
}

public enum ProfileAuthorityMatcher {
    public static func matches(
        profile: BarlineProfile,
        checkpoint: MenuBarWorkspaceCheckpoint
    ) -> Bool {
        guard ProfileWorkspaceState(profile: profile) == checkpoint.workspace else {
            return false
        }
        let scopedItems = checkpoint.activeDisplayID.map { activeDisplayID in
            checkpoint.snapshot.items.filter { $0.displayID == activeDisplayID }
        } ?? checkpoint.snapshot.items
        let visible = scopedItems.filter { $0.section == .visible }.map(\.id)
        let hidden = scopedItems.filter { $0.section == .hidden }.map(\.id)
        let alwaysHidden = scopedItems.filter { $0.section == .alwaysHidden }.map(\.id)
        let layout = profile.layout(for: checkpoint.activeDisplayID)
        return visible.starts(with: layout.visible)
            && hidden.starts(with: layout.hidden)
            && alwaysHidden.starts(with: layout.alwaysHidden)
    }
}

public enum ApplicationMenuOverlapBehavior: String, Codable, Sendable {
    case leaveVisible
    case hideWhenNeeded
}

public struct ProfileHotkey: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: Set<Modifier>

    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case command, option, control, shift
    }

    public init(key: String, modifiers: Set<Modifier>) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct BarlineProfile: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var symbol: String?
    public var layout: ProfileLayout
    public var groups: [ProfileGroup]
    public var spacers: [ProfileSpacer]
    public var displayOverrides: [DisplayProfileOverride]
    public var appearance: ProfileAppearance
    public var shelfBehavior: ProfileShelfBehavior
    public var revealTriggers: ProfileRevealTriggers
    public var autoRehide: ProfileAutoRehide
    public var applicationMenuOverlapBehavior: ApplicationMenuOverlapBehavior
    public var hotkey: ProfileHotkey?
    public let createdAt: Date
    public var updatedAt: Date
    public let schemaVersion: Int

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String? = nil,
        layout: ProfileLayout = ProfileLayout(),
        groups: [ProfileGroup] = [],
        spacers: [ProfileSpacer] = [],
        displayOverrides: [DisplayProfileOverride] = [],
        appearance: ProfileAppearance = ProfileAppearance(),
        shelfBehavior: ProfileShelfBehavior = ProfileShelfBehavior(),
        revealTriggers: ProfileRevealTriggers = ProfileRevealTriggers(),
        autoRehide: ProfileAutoRehide = ProfileAutoRehide(),
        applicationMenuOverlapBehavior: ApplicationMenuOverlapBehavior = .hideWhenNeeded,
        hotkey: ProfileHotkey? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        schemaVersion: Int = ProfileSchema.currentVersion
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.layout = layout
        self.groups = groups
        self.spacers = spacers
        self.displayOverrides = displayOverrides
        self.appearance = appearance
        self.shelfBehavior = shelfBehavior
        self.revealTriggers = revealTriggers
        self.autoRehide = autoRehide
        self.applicationMenuOverlapBehavior = applicationMenuOverlapBehavior
        self.hotkey = hotkey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    public func layout(for displayID: MenuBarDisplayID?) -> ProfileLayout {
        guard let displayID else { return layout }
        return displayOverrides.first { $0.displayID == displayID }?.layout ?? layout
    }

    /// All item identities referenced by the profile, including display-specific
    /// layouts, in stable archive order with duplicates removed.
    public var searchableItemIDs: [MenuBarItemID] {
        stableUnique(
            layout.allItemIDs + displayOverrides.flatMap(\.layout.allItemIDs)
        )
    }

    /// All groups referenced by the profile, including display-specific groups,
    /// in stable archive order with duplicate group values removed.
    public var searchableGroups: [ProfileGroup] {
        stableUnique(groups + displayOverrides.flatMap(\.groups))
    }

    public var searchableGroupNames: [String] {
        stableUnique(searchableGroups.map(\.name))
    }

    public func searchableGroupNames(containing itemID: MenuBarItemID) -> [String] {
        stableUnique(
            searchableGroups
                .filter { $0.itemIDs.contains(itemID) }
                .map(\.name)
        )
    }

    private func stableUnique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }
}

public enum ProfileActivationSource: String, Codable, CaseIterable, Sendable {
    case configuredDefault
    case focus
    case shortcut
    case appIntent
    case manual
    case recovery

    public var retainsArbitrationRequestWhileActive: Bool {
        switch self {
        case .configuredDefault, .focus: true
        case .shortcut, .appIntent, .manual, .recovery: false
        }
    }

    public var precedence: Int {
        switch self {
        case .configuredDefault: 0
        case .focus: 100
        case .shortcut: 200
        case .appIntent: 300
        case .manual: 400
        case .recovery: 500
        }
    }
}

public struct ProfileActivationRequest: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let profileID: UUID
    public let source: ProfileActivationSource
    public let requestedAt: Date

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        source: ProfileActivationSource,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.source = source
        self.requestedAt = requestedAt
    }
}

public struct ProfileActivationResolver: Sendable {
    public init() {}

    public func resolve(_ requests: some Sequence<ProfileActivationRequest>) -> ProfileActivationRequest? {
        requests.max { lhs, rhs in
            if lhs.source.precedence != rhs.source.precedence {
                return lhs.source.precedence < rhs.source.precedence
            }
            if lhs.requestedAt != rhs.requestedAt {
                return lhs.requestedAt < rhs.requestedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

public struct PresentationProfileTemplate: Codable, Hashable, Sendable {
    public let profile: BarlineProfile
    public let sourceGeneration: UInt64
    public let requiresConfirmation: Bool
    public let restoresPreviousLayoutOnDeactivation: Bool
}

public struct PresentationProfileTemplateBuilder: Sendable {
    public static let profileID = UUID(uuid: (
        0xBA, 0x71, 0x1E, 0x00, 0x00, 0x00, 0x40, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    ))

    public init() {}

    public func makeTemplate(
        from snapshot: MenuBarSnapshot,
        now: Date = Date(),
        id: UUID = Self.profileID
    ) -> PresentationProfileTemplate {
        let ordered = snapshot.items.sorted { lhs, rhs in
            if lhs.section != rhs.section {
                return lhs.section.rawValue < rhs.section.rawValue
            }
            return lhs.order < rhs.order
        }
        let essential = ordered.filter { $0.isSystemItem || $0.isBarlineControlItem }.map(\.id)
        let utilities = ordered.filter { !$0.isSystemItem && !$0.isBarlineControlItem }.map(\.id)
        let profile = BarlineProfile(
            id: id,
            name: "Presentation",
            symbol: "rectangle.on.rectangle",
            layout: ProfileLayout(visible: essential, hidden: utilities),
            revealTriggers: ProfileRevealTriggers(click: true, hover: false, scroll: false),
            autoRehide: ProfileAutoRehide(isEnabled: true, delaySeconds: 5),
            applicationMenuOverlapBehavior: .hideWhenNeeded,
            createdAt: now,
            updatedAt: now
        )
        return PresentationProfileTemplate(
            profile: profile,
            sourceGeneration: snapshot.generation,
            requiresConfirmation: true,
            restoresPreviousLayoutOnDeactivation: true
        )
    }
}
