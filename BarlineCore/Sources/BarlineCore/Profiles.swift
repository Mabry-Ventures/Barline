//
//  Profiles.swift
//  Barline
//

import Foundation

public enum ProfileSchema {
    public static let currentVersion = 3
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
    public var delaySeconds: Double

    public init(isEnabled: Bool = true, delaySeconds: Double = 5) {
        self.isEnabled = isEnabled
        self.delaySeconds = delaySeconds
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
}

public enum ProfileActivationSource: String, Codable, CaseIterable, Sendable {
    case configuredDefault
    case focus
    case shortcut
    case appIntent
    case manual
    case recovery

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
