//
//  IceProfileImport.swift
//  Barline
//

import Foundation

public enum IceInstallation: String, Codable, CaseIterable, Sendable {
    case upstream = "com.jordanbaird.Ice"
    case community = "com.lxy1992.Ice"

    public var importedProfileID: UUID {
        switch self {
        case .upstream:
            UUID(uuid: (0xCC, 0xEB, 0x6B, 0xB0, 0x73, 0x50, 0x4E, 0x53, 0x9A, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11))
        case .community:
            UUID(uuid: (0xCC, 0xEB, 0x6B, 0xB0, 0x73, 0x50, 0x4E, 0x53, 0x9A, 0x11, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22))
        }
    }

    public var displayName: String {
        switch self {
        case .upstream: "Ice"
        case .community: "Ice Community"
        }
    }
}

public struct IcePreferenceSnapshot: Sendable {
    public let source: IceInstallation
    public let shelfEnabled: Bool?
    public let revealOnClick: Bool?
    public let revealOnHover: Bool?
    public let revealOnScroll: Bool?
    public let autoRehideEnabled: Bool?
    public let rehideInterval: Double?
    public let itemSpacingOffset: Double?
    public let hideApplicationMenus: Bool?
    public let containsAppearanceConfiguration: Bool
    public let containsHotkeys: Bool
    public let ignoredKnownKeysWithInvalidTypes: Set<String>

    public init(
        source: IceInstallation,
        shelfEnabled: Bool? = nil,
        revealOnClick: Bool? = nil,
        revealOnHover: Bool? = nil,
        revealOnScroll: Bool? = nil,
        autoRehideEnabled: Bool? = nil,
        rehideInterval: Double? = nil,
        itemSpacingOffset: Double? = nil,
        hideApplicationMenus: Bool? = nil,
        containsAppearanceConfiguration: Bool = false,
        containsHotkeys: Bool = false,
        ignoredKnownKeysWithInvalidTypes: Set<String> = []
    ) {
        self.source = source
        self.shelfEnabled = shelfEnabled
        self.revealOnClick = revealOnClick
        self.revealOnHover = revealOnHover
        self.revealOnScroll = revealOnScroll
        self.autoRehideEnabled = autoRehideEnabled
        self.rehideInterval = rehideInterval
        self.itemSpacingOffset = itemSpacingOffset
        self.hideApplicationMenus = hideApplicationMenus
        self.containsAppearanceConfiguration = containsAppearanceConfiguration
        self.containsHotkeys = containsHotkeys
        self.ignoredKnownKeysWithInvalidTypes = ignoredKnownKeysWithInvalidTypes
    }

    public init(source: IceInstallation, persistentDomain: [String: Any]) {
        var invalid = Set<String>()

        func bool(_ key: String) -> Bool? {
            guard let value = persistentDomain[key] else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                invalid.insert(key)
                return nil
            }
            return number.boolValue
        }

        func double(_ key: String) -> Double? {
            guard let value = persistentDomain[key] else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                invalid.insert(key)
                return nil
            }
            return number.doubleValue
        }

        self.init(
            source: source,
            shelfEnabled: bool("UseIceBar"),
            revealOnClick: bool("ShowOnClick"),
            revealOnHover: bool("ShowOnHover"),
            revealOnScroll: bool("ShowOnScroll"),
            autoRehideEnabled: bool("AutoRehide"),
            rehideInterval: double("RehideInterval"),
            itemSpacingOffset: double("ItemSpacingOffset"),
            hideApplicationMenus: bool("HideApplicationMenus"),
            containsAppearanceConfiguration: persistentDomain["MenuBarAppearanceConfigurationV2"] != nil,
            containsHotkeys: persistentDomain["Hotkeys"] != nil,
            ignoredKnownKeysWithInvalidTypes: invalid
        )
    }
}

/// Reads only the two approved Ice persistent domains and never mutates them.
public actor IceDefaultsDomainReader {
    public init() {}

    public func discover() -> [IcePreferenceSnapshot] {
        IceInstallation.allCases.compactMap { installation in
            guard let domain = UserDefaults.standard.persistentDomain(forName: installation.rawValue),
                  !domain.isEmpty
            else {
                return nil
            }
            return IcePreferenceSnapshot(source: installation, persistentDomain: domain)
        }
    }
}

public enum IceImportedComponent: String, Codable, CaseIterable, Sendable {
    case currentLayout
    case shelfBehavior
    case revealTriggers
    case autoRehide
    case itemSpacing
    case applicationMenuOverlap
}

public enum IceImportWarning: Codable, Equatable, Sendable {
    case layoutDerivedFromCurrentSnapshot
    case appearanceRequiresManualReview
    case hotkeysRequireManualReview
    case invalidPreferenceIgnored(String)
}

public struct IceImportPreview: Sendable {
    public let source: IceInstallation
    public let profile: BarlineProfile
    public let importedComponents: Set<IceImportedComponent>
    public let warnings: [IceImportWarning]
    public let requiresConfirmation: Bool

    public init(
        source: IceInstallation,
        profile: BarlineProfile,
        importedComponents: Set<IceImportedComponent>,
        warnings: [IceImportWarning],
        requiresConfirmation: Bool
    ) {
        self.source = source
        self.profile = profile
        self.importedComponents = importedComponents
        self.warnings = warnings
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct IceProfileImporter: Sendable {
    public init() {}

    public func preview(
        preferences: IcePreferenceSnapshot,
        currentSnapshot: MenuBarSnapshot,
        now: Date = Date()
    ) throws -> IceImportPreview {
        let descriptors = currentSnapshot.items
            .filter { !$0.isBarlineControlItem }
            .sorted { lhs, rhs in
                if lhs.section != rhs.section {
                    return sectionRank(lhs.section) < sectionRank(rhs.section)
                }
                return lhs.order < rhs.order
            }
        let layout = ProfileLayout(
            visible: descriptors.filter { $0.section == .visible }.map(\.id),
            hidden: descriptors.filter { $0.section == .hidden }.map(\.id),
            alwaysHidden: descriptors.filter { $0.section == .alwaysHidden }.map(\.id)
        )

        var imported: Set<IceImportedComponent> = [.currentLayout]
        if preferences.shelfEnabled != nil {
            imported.insert(.shelfBehavior)
        }
        if preferences.revealOnClick != nil || preferences.revealOnHover != nil ||
            preferences.revealOnScroll != nil
        {
            imported.insert(.revealTriggers)
        }
        if preferences.autoRehideEnabled != nil || preferences.rehideInterval != nil {
            imported.insert(.autoRehide)
        }
        if preferences.itemSpacingOffset != nil {
            imported.insert(.itemSpacing)
        }
        if preferences.hideApplicationMenus != nil {
            imported.insert(.applicationMenuOverlap)
        }

        var warnings: [IceImportWarning] = [.layoutDerivedFromCurrentSnapshot]
        if preferences.containsAppearanceConfiguration {
            warnings.append(.appearanceRequiresManualReview)
        }
        if preferences.containsHotkeys {
            warnings.append(.hotkeysRequireManualReview)
        }
        warnings.append(contentsOf: preferences.ignoredKnownKeysWithInvalidTypes.sorted().map {
            .invalidPreferenceIgnored($0)
        })

        let profile = BarlineProfile(
            id: preferences.source.importedProfileID,
            name: "Imported from \(preferences.source.displayName)",
            symbol: "snowflake",
            layout: layout,
            appearance: ProfileAppearance(
                itemSpacing: preferences.itemSpacingOffset.flatMap {
                    ProfileAppearance.itemSpacingRange.contains($0) ? $0 : nil
                } ?? 0
            ),
            shelfBehavior: ProfileShelfBehavior(isEnabled: preferences.shelfEnabled ?? false),
            revealTriggers: ProfileRevealTriggers(
                click: preferences.revealOnClick ?? true,
                hover: preferences.revealOnHover ?? false,
                scroll: preferences.revealOnScroll ?? false
            ),
            autoRehide: ProfileAutoRehide(
                isEnabled: preferences.autoRehideEnabled ?? true,
                delaySeconds: max(0, preferences.rehideInterval ?? 5)
            ),
            applicationMenuOverlapBehavior:
            preferences.hideApplicationMenus == false ? .leaveVisible : .hideWhenNeeded,
            createdAt: now,
            updatedAt: now
        )
        try ProfileValidator().validate(profile)
        return IceImportPreview(
            source: preferences.source,
            profile: profile,
            importedComponents: imported,
            warnings: warnings,
            requiresConfirmation: true
        )
    }

    private func sectionRank(_ section: MenuBarSection) -> Int {
        switch section {
        case .visible: 0
        case .hidden: 1
        case .alwaysHidden: 2
        }
    }
}
