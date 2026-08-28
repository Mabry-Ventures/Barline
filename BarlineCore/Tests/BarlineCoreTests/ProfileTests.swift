//
//  ProfileTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Profile domain")
struct ProfileTests {
    private let primaryDisplay = MenuBarDisplayID("primary")

    @Test("Current profiles round-trip without losing groups, spacers, or overrides")
    func currentRoundTrip() throws {
        let profile = completeProfile()
        let decoded = try ProfileCodec().decode(ProfileCodec().encode(profile))

        #expect(decoded == profile)
        #expect(decoded.groups.count == 1)
        #expect(decoded.spacers.count == 1)
        #expect(decoded.displayOverrides.count == 1)
    }

    @Test("Signed item spacing round-trips across the supported General settings range")
    func signedItemSpacingRoundTrip() throws {
        var profile = completeProfile()
        profile.appearance.itemSpacing = -16

        let decoded = try ProfileCodec().decode(ProfileCodec().encode(profile))

        #expect(decoded.appearance.itemSpacing == -16)
        #expect(ProfileAppearance.itemSpacingRange == -16 ... 16)
    }

    @Test("Legacy auto-rehide checkpoints decode with the timed strategy")
    func legacyAutoRehideDecode() throws {
        let data = Data(#"{"isEnabled":true,"delaySeconds":3}"#.utf8)
        let decoded = try JSONDecoder().decode(ProfileAutoRehide.self, from: data)

        #expect(decoded == ProfileAutoRehide(isEnabled: true, strategy: .timed, delaySeconds: 3))
    }

    @Test("Display override resolves exactly and unknown displays use the base layout")
    func displayResolution() {
        let profile = completeProfile()

        #expect(profile.layout(for: primaryDisplay) == profile.displayOverrides[0].layout)
        #expect(profile.layout(for: MenuBarDisplayID("unknown")) == profile.layout)
        #expect(profile.layout(for: nil) == profile.layout)
    }

    @Test("Search metadata includes every display override exactly once")
    func searchableOverrideMetadata() {
        let base = item(1)
        let overrideOnly = item(2)
        let sharedGroup = ProfileGroup(id: UUID(90), name: "Shared", itemIDs: [base])
        let overrideGroup = ProfileGroup(id: UUID(91), name: "External", itemIDs: [overrideOnly])
        let profile = BarlineProfile(
            name: "Displays",
            layout: ProfileLayout(visible: [base]),
            groups: [sharedGroup],
            displayOverrides: [
                DisplayProfileOverride(
                    displayID: primaryDisplay,
                    layout: ProfileLayout(visible: [base, overrideOnly]),
                    groups: [sharedGroup, overrideGroup]
                ),
            ]
        )

        #expect(profile.searchableItemIDs == [base, overrideOnly])
        #expect(profile.searchableGroups == [sharedGroup, overrideGroup])
        #expect(profile.searchableGroupNames == ["Shared", "External"])
        #expect(profile.searchableGroupNames(containing: overrideOnly) == ["External"])
    }

    @Test("Move planner uses global section candidates across displays")
    func plansGlobalCrossDisplayIndex() {
        let first = MenuBarDisplayID("first")
        let second = MenuBarDisplayID("second")
        let snapshot = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(),
            items: [
                MenuBarItemDescriptor(id: item(1), section: .hidden, order: 0, displayID: first),
                MenuBarItemDescriptor(id: item(2), section: .hidden, order: 1, displayID: first),
                MenuBarItemDescriptor(id: item(3), section: .hidden, order: 2, displayID: second),
            ],
            displayIDs: [first, second],
            activeSpaceIsValid: true
        )

        #expect(MenuBarMovePlanner().destinationIndex(
            in: snapshot,
            section: .hidden,
            preferredDisplayID: first
        ) == 1)

        #expect(MenuBarMovePlanner().restoreOperations(for: snapshot) == [
            MenuBarMoveOperation(
                itemID: item(1),
                section: .hidden,
                index: 0,
                destinationDisplayID: first
            ),
            MenuBarMoveOperation(
                itemID: item(2),
                section: .hidden,
                index: 1,
                destinationDisplayID: first
            ),
            MenuBarMoveOperation(
                itemID: item(3),
                section: .hidden,
                index: 2,
                destinationDisplayID: second
            ),
        ])

        let swapped = MenuBarSnapshot(
            generation: 2,
            capturedAt: Date(),
            items: [
                MenuBarItemDescriptor(id: item(1), section: .hidden, order: 0, displayID: second),
                MenuBarItemDescriptor(id: item(2), section: .hidden, order: 1, displayID: first),
                MenuBarItemDescriptor(id: item(3), section: .hidden, order: 2, displayID: first),
            ],
            displayIDs: [first, second],
            activeSpaceIsValid: true
        )
        let firstRestore = MenuBarMovePlanner().restoreOperations(for: snapshot)[0]
        #expect(MenuBarMovePlanner().resultMatches(firstRestore, in: swapped) == false)
    }

    @Test("Activation precedence is deterministic before request recency")
    func activationPrecedence() {
        let low = ProfileActivationRequest(
            id: UUID(0),
            profileID: UUID(10),
            source: .focus,
            requestedAt: Date(timeIntervalSince1970: 200)
        )
        let high = ProfileActivationRequest(
            id: UUID(1),
            profileID: UUID(11),
            source: .manual,
            requestedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(ProfileActivationResolver().resolve([low, high]) == high)
        #expect(ProfileActivationSource.recovery.precedence > ProfileActivationSource.manual.precedence)
        #expect(ProfileActivationSource.focus.precedence > ProfileActivationSource.configuredDefault.precedence)
    }

    @Test("Only active automation contexts retain arbitration requests")
    func activationRequestLifetime() {
        #expect(ProfileActivationSource.configuredDefault.retainsArbitrationRequestWhileActive)
        #expect(ProfileActivationSource.focus.retainsArbitrationRequestWhileActive)
        #expect(!ProfileActivationSource.manual.retainsArbitrationRequestWhileActive)
        #expect(!ProfileActivationSource.shortcut.retainsArbitrationRequestWhileActive)
        #expect(!ProfileActivationSource.appIntent.retainsArbitrationRequestWhileActive)
        #expect(!ProfileActivationSource.recovery.retainsArbitrationRequestWhileActive)
    }

    @Test("Equal activation sources choose the newest request")
    func activationRecency() {
        let profileID = UUID(20)
        let old = ProfileActivationRequest(
            id: UUID(2),
            profileID: profileID,
            source: .appIntent,
            requestedAt: Date(timeIntervalSince1970: 100)
        )
        let new = ProfileActivationRequest(
            id: UUID(3),
            profileID: profileID,
            source: .appIntent,
            requestedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(ProfileActivationResolver().resolve([new, old]) == new)
        #expect(ProfileActivationResolver().resolve([]) == nil)
    }

    @Test("Presentation template keeps system and Barline controls visible")
    func presentationTemplate() {
        let system = item(1)
        let control = item(2)
        let utility = item(3)
        let snapshot = MenuBarSnapshot(
            generation: 42,
            capturedAt: Date(timeIntervalSince1970: 100),
            items: [
                descriptor(utility, order: 2),
                descriptor(system, order: 0, isSystem: true),
                descriptor(control, order: 1, isControl: true),
            ],
            displayIDs: [primaryDisplay],
            activeSpaceIsValid: true
        )

        let template = PresentationProfileTemplateBuilder().makeTemplate(
            from: snapshot,
            now: Date(timeIntervalSince1970: 200),
            id: PresentationProfileTemplateBuilder.profileID
        )

        #expect(template.profile.layout.visible == [system, control])
        #expect(template.profile.layout.hidden == [utility])
        #expect(template.profile.revealTriggers.hover == false)
        #expect(template.requiresConfirmation)
        #expect(template.restoresPreviousLayoutOnDeactivation)
        #expect(template.sourceGeneration == 42)
        #expect(template.profile.id == PresentationProfileTemplateBuilder.profileID)
    }

    @Test("Version 1 migrates flat layout fields through every schema step")
    func migratesV1() throws {
        let id = item(1)
        let document: [String: Any] = [
            "id": UUID(40).uuidString,
            "name": "Legacy",
            "visibleItemOrder": [encodedItem(id)],
            "hiddenItemOrder": [],
            "alwaysHiddenItemOrder": [],
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-02T00:00:00Z",
            "schemaVersion": 1,
        ]
        let migrated = try ProfileCodec().decode(JSONSerialization.data(withJSONObject: document))

        #expect(migrated.schemaVersion == ProfileSchema.currentVersion)
        #expect(migrated.layout.visible == [id])
        #expect(migrated.appearance == ProfileAppearance())
        #expect(migrated.revealTriggers == ProfileRevealTriggers())
    }

    @Test("Version 2 migration preserves supplied layout and installs current defaults")
    func migratesV2() throws {
        let profile = completeProfile(schemaVersion: 2)
        var document = try #require(
            JSONSerialization.jsonObject(with: rawEncode(profile)) as? [String: Any]
        )
        document.removeValue(forKey: "appearance")
        document.removeValue(forKey: "shelfBehavior")
        document.removeValue(forKey: "revealTriggers")
        document.removeValue(forKey: "autoRehide")
        document.removeValue(forKey: "applicationMenuOverlapBehavior")

        let migrated = try ProfileCodec().decode(JSONSerialization.data(withJSONObject: document))

        #expect(migrated.schemaVersion == ProfileSchema.currentVersion)
        #expect(migrated.layout == profile.layout)
        #expect(migrated.autoRehide == ProfileAutoRehide())
    }

    @Test("Version 3 migration installs an explicit timed auto-rehide strategy")
    func migratesV3AutoRehideStrategy() throws {
        let profile = completeProfile(schemaVersion: 3)
        var document = try #require(
            JSONSerialization.jsonObject(with: rawEncode(profile)) as? [String: Any]
        )
        var autoRehide = try #require(document["autoRehide"] as? [String: Any])
        autoRehide.removeValue(forKey: "strategy")
        document["autoRehide"] = autoRehide

        let migrated = try ProfileCodec().decode(JSONSerialization.data(withJSONObject: document))

        #expect(migrated.schemaVersion == ProfileSchema.currentVersion)
        #expect(migrated.autoRehide.strategy == .timed)
    }

    @Test("Archive export is deterministic and import validates all profiles")
    func archiveRoundTrip() throws {
        let profile = completeProfile()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try ProfileCodec().export([profile], at: date)
        let second = try ProfileCodec().export([profile], at: date)
        let imported = try ProfileCodec().importArchive(first)

        #expect(first == second)
        #expect(imported.exportedAt == date)
        #expect(imported.profiles == [profile])
    }

    @Test("Archive import migrates embedded older profiles")
    func archiveMigratesProfiles() throws {
        let current = completeProfile()
        var legacy = try #require(
            JSONSerialization.jsonObject(with: rawEncode(current)) as? [String: Any]
        )
        legacy["schemaVersion"] = 2
        legacy.removeValue(forKey: "appearance")
        legacy.removeValue(forKey: "shelfBehavior")
        legacy.removeValue(forKey: "revealTriggers")
        legacy.removeValue(forKey: "autoRehide")
        legacy.removeValue(forKey: "applicationMenuOverlapBehavior")
        let archive: [String: Any] = [
            "formatVersion": 1,
            "exportedAt": "2026-01-01T00:00:00Z",
            "profiles": [legacy],
        ]

        let imported = try ProfileCodec().importArchive(
            JSONSerialization.data(withJSONObject: archive)
        )

        #expect(imported.profiles[0].schemaVersion == ProfileSchema.currentVersion)
    }

    @Test("Duplicate item identities across sections are rejected")
    func rejectsDuplicateItems() {
        let duplicate = item(1)
        let profile = BarlineProfile(
            name: "Invalid",
            layout: ProfileLayout(visible: [duplicate], hidden: [duplicate])
        )

        #expect(throws: ProfileValidationError.duplicateItem(duplicate)) {
            try ProfileValidator().validate(profile)
        }
    }

    @Test("Groups and spacers cannot reference absent items")
    func rejectsDanglingLayoutMetadata() {
        let known = item(1)
        let unknown = item(2)
        let groupID = UUID(50)
        let spacerID = UUID(51)
        let badGroup = BarlineProfile(
            name: "Invalid group",
            layout: ProfileLayout(visible: [known]),
            groups: [ProfileGroup(id: groupID, name: "Tools", itemIDs: [unknown])]
        )
        let badSpacer = BarlineProfile(
            name: "Invalid spacer",
            layout: ProfileLayout(visible: [known]),
            spacers: [ProfileSpacer(id: spacerID, placement: .after(unknown))]
        )

        #expect(throws: ProfileValidationError.groupContainsUnknownItem(groupID, unknown)) {
            try ProfileValidator().validate(badGroup)
        }
        #expect(throws: ProfileValidationError.spacerReferencesUnknownItem(spacerID, unknown)) {
            try ProfileValidator().validate(badSpacer)
        }
    }

    @Test("Invalid display, timing, appearance, and hotkey values are rejected")
    func rejectsInvalidScalarValues() {
        let emptyDisplay = BarlineProfile(
            name: "Display",
            displayOverrides: [DisplayProfileOverride(displayID: MenuBarDisplayID(" "), layout: .init())]
        )
        let badDelay = BarlineProfile(name: "Delay", autoRehide: .init(delaySeconds: -.infinity))
        let badAppearance = BarlineProfile(
            name: "Appearance", appearance: .init(itemSpacing: -.infinity)
        )
        let excessiveSpacing = BarlineProfile(
            name: "Spacing", appearance: .init(itemSpacing: 17)
        )
        let fractionalSpacing = BarlineProfile(
            name: "Fractional spacing", appearance: .init(itemSpacing: 1.5)
        )
        let malformedColor = BarlineProfile(
            name: "Malformed color", appearance: .init(tintHex: "blue")
        )
        let badHotkey = BarlineProfile(
            name: "Hotkey", hotkey: ProfileHotkey(key: "", modifiers: [])
        )

        #expect(throws: ProfileValidationError.emptyDisplayID) { try ProfileValidator().validate(emptyDisplay) }
        #expect(throws: ProfileValidationError.invalidAutoRehideDelay) { try ProfileValidator().validate(badDelay) }
        #expect(throws: ProfileValidationError.invalidAppearance) { try ProfileValidator().validate(badAppearance) }
        #expect(throws: ProfileValidationError.invalidAppearance) {
            try ProfileValidator().validate(excessiveSpacing)
        }
        #expect(throws: ProfileValidationError.invalidAppearance) {
            try ProfileValidator().validate(fractionalSpacing)
        }
        #expect(throws: ProfileValidationError.invalidAppearance) {
            try ProfileValidator().validate(malformedColor)
        }
        #expect(throws: ProfileValidationError.invalidHotkey) { try ProfileValidator().validate(badHotkey) }
    }

    @Test("Profile metadata and stable identity validation rejects corrupt values")
    func rejectsInvalidMetadata() {
        let unstable = MenuBarItemID(bundleIdentifier: "")
        let badName = BarlineProfile(name: " \n ")
        let badDates = BarlineProfile(
            name: "Dates",
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let badIdentity = BarlineProfile(
            name: "Identity",
            layout: ProfileLayout(visible: [unstable])
        )
        let badVersion = BarlineProfile(name: "Version", schemaVersion: 2)

        #expect(throws: ProfileValidationError.emptyName) {
            try ProfileValidator().validate(badName)
        }
        #expect(throws: ProfileValidationError.invalidTimestampOrder) {
            try ProfileValidator().validate(badDates)
        }
        #expect(throws: ProfileValidationError.unstableItemIdentity(unstable)) {
            try ProfileValidator().validate(badIdentity)
        }
        #expect(throws: ProfileValidationError.unsupportedSchemaVersion(2)) {
            try ProfileValidator().validate(badVersion)
        }
    }

    @Test("Duplicate layout metadata and invalid spacer widths are rejected")
    func rejectsDuplicateLayoutMetadata() {
        let known = item(1)
        let groupID = UUID(70)
        let spacerID = UUID(71)
        let group = ProfileGroup(id: groupID, name: "Tools", itemIDs: [known])
        let spacer = ProfileSpacer(id: spacerID, placement: .after(known))
        let duplicateGroups = BarlineProfile(
            name: "Groups",
            layout: ProfileLayout(visible: [known]),
            groups: [group, group]
        )
        let emptyGroup = BarlineProfile(
            name: "Group name",
            layout: ProfileLayout(visible: [known]),
            groups: [ProfileGroup(id: groupID, name: "", itemIDs: [known])]
        )
        let duplicateSpacers = BarlineProfile(
            name: "Spacers",
            layout: ProfileLayout(visible: [known]),
            spacers: [spacer, spacer]
        )
        let invalidSpacer = BarlineProfile(
            name: "Spacer width",
            layout: ProfileLayout(visible: [known]),
            spacers: [ProfileSpacer(id: spacerID, placement: .after(known), width: 0)]
        )

        #expect(throws: ProfileValidationError.duplicateGroup(groupID)) {
            try ProfileValidator().validate(duplicateGroups)
        }
        #expect(throws: ProfileValidationError.emptyGroupName(groupID)) {
            try ProfileValidator().validate(emptyGroup)
        }
        #expect(throws: ProfileValidationError.duplicateSpacer(spacerID)) {
            try ProfileValidator().validate(duplicateSpacers)
        }
        #expect(throws: ProfileValidationError.invalidSpacerWidth(spacerID)) {
            try ProfileValidator().validate(invalidSpacer)
        }
    }

    @Test("Duplicate display overrides and malformed archives are rejected")
    func rejectsDuplicateDisplaysAndMalformedArchives() {
        let display = DisplayProfileOverride(displayID: primaryDisplay, layout: ProfileLayout())
        let duplicateDisplays = BarlineProfile(
            name: "Displays",
            displayOverrides: [display, display]
        )

        #expect(throws: ProfileValidationError.duplicateDisplay(primaryDisplay)) {
            try ProfileValidator().validate(duplicateDisplays)
        }
        #expect(throws: ProfileValidationError.self) {
            try ProfileCodec().importArchive(Data("[]".utf8))
        }
        #expect(throws: ProfileValidationError.self) {
            try ProfileCodec().importArchive(Data("{\"formatVersion\":1}".utf8))
        }
    }

    @Test("Archive rejects duplicates, empty sets, and unsupported formats")
    func rejectsInvalidArchives() throws {
        let profile = completeProfile()
        #expect(throws: ProfileValidationError.emptyArchive) {
            try ProfileCodec().export([])
        }
        #expect(throws: ProfileValidationError.duplicateProfile(profile.id)) {
            try ProfileCodec().export([profile, profile])
        }

        let unsupportedString = """
        {"formatVersion":99,"exportedAt":"2026-01-01T00:00:00Z","profiles":[]}
        """
        let unsupported = Data(unsupportedString.utf8)
        #expect(throws: ProfileValidationError.unsupportedArchiveVersion(99)) {
            try ProfileCodec().importArchive(unsupported)
        }
    }

    @Test("Archive import bounds bytes, profile count, collections, and string fields")
    func rejectsOversizedArchives() throws {
        let oversizedBytes = Data(repeating: 0x20, count: ProfileCodec.maximumArchiveByteCount + 1)
        #expect(throws: ProfileValidationError.archiveTooLarge(oversizedBytes.count)) {
            try ProfileCodec().importArchive(oversizedBytes)
        }

        let profileDocument = try #require(
            JSONSerialization.jsonObject(with: rawEncode(completeProfile())) as? [String: Any]
        )
        let tooManyProfiles = archiveDocument(
            profiles: Array(repeating: profileDocument, count: ProfileCodec.maximumProfileCount + 1)
        )
        #expect(throws: ProfileValidationError.archiveLimitExceeded("profile count")) {
            try ProfileCodec().importArchive(JSONSerialization.data(withJSONObject: tooManyProfiles))
        }

        var excessiveCollection = profileDocument
        excessiveCollection["groups"] = Array(
            repeating: ["id": UUID().uuidString, "name": "Group", "itemIDs": []],
            count: ProfileCodec.maximumCollectionCount + 1
        )
        #expect(throws: ProfileValidationError.archiveLimitExceeded("collection count")) {
            try ProfileCodec().importArchive(
                JSONSerialization.data(withJSONObject: archiveDocument(profiles: [excessiveCollection]))
            )
        }

        var excessiveField = profileDocument
        excessiveField["name"] = String(repeating: "x", count: ProfileCodec.maximumStringLength + 1)
        #expect(throws: ProfileValidationError.archiveLimitExceeded("string length")) {
            try ProfileCodec().importArchive(
                JSONSerialization.data(withJSONObject: archiveDocument(profiles: [excessiveField]))
            )
        }
    }

    @Test("Export enforces the same JSON bounds as import")
    func exportRejectsOversizedStrings() {
        var profile = completeProfile()
        profile.name = String(repeating: "x", count: ProfileCodec.maximumStringLength + 1)

        #expect(throws: ProfileValidationError.archiveLimitExceeded("string length")) {
            try ProfileCodec().export([profile])
        }
        #expect(throws: ProfileValidationError.archiveLimitExceeded("string length")) {
            try ProfileCodec().encode(profile)
        }
    }

    @Test("Export bounds collections and accepts the exact collection limit")
    func exportBoundsCollections() throws {
        let knownItem = item(1)
        var profile = completeProfile()
        profile.layout = ProfileLayout(visible: [knownItem])
        profile.groups = (0 ..< ProfileCodec.maximumCollectionCount).map { index in
            ProfileGroup(name: "Group \(index)", itemIDs: [knownItem])
        }
        profile.spacers = []
        profile.displayOverrides = []

        let boundaryArchive = try ProfileCodec().export([profile])
        #expect(try ProfileCodec().importArchive(boundaryArchive).profiles == [profile])

        profile.groups.append(ProfileGroup(name: "Too many", itemIDs: [knownItem]))
        #expect(throws: ProfileValidationError.archiveLimitExceeded("collection count")) {
            try ProfileCodec().export([profile])
        }
    }

    @Test("Future and missing schema versions are rejected before decode")
    func rejectsBadSchemaVersions() {
        let future = Data("{\"schemaVersion\":999}".utf8)
        let missing = Data("{\"name\":\"No version\"}".utf8)

        #expect(throws: ProfileValidationError.unsupportedSchemaVersion(999)) {
            try ProfileCodec().decode(future)
        }
        #expect(throws: ProfileValidationError.self) {
            try ProfileCodec().decode(missing)
        }
    }

    private func completeProfile(schemaVersion: Int = ProfileSchema.currentVersion) -> BarlineProfile {
        let one = item(1)
        let two = item(2)
        let three = item(3)
        let groupID = UUID(60)
        let spacerID = UUID(61)
        return BarlineProfile(
            id: UUID(62),
            name: "Work",
            symbol: "briefcase",
            layout: ProfileLayout(visible: [one], hidden: [two], alwaysHidden: [three]),
            groups: [ProfileGroup(id: groupID, name: "Work tools", itemIDs: [one, two])],
            spacers: [ProfileSpacer(id: spacerID, placement: .after(one), width: 16)],
            displayOverrides: [
                DisplayProfileOverride(
                    displayID: primaryDisplay,
                    layout: ProfileLayout(visible: [two], hidden: [one], alwaysHidden: [three])
                ),
            ],
            appearance: ProfileAppearance(
                tintHex: "#102030",
                gradientHex: ["#102030", "#405060"],
                showsBorder: true,
                showsShadow: true,
                shape: .split,
                itemSpacing: 4
            ),
            shelfBehavior: ProfileShelfBehavior(isEnabled: true),
            revealTriggers: ProfileRevealTriggers(click: true, hover: true, scroll: false),
            autoRehide: ProfileAutoRehide(isEnabled: true, delaySeconds: 3),
            hotkey: ProfileHotkey(key: "1", modifiers: [.command, .option]),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            schemaVersion: schemaVersion
        )
    }

    private func item(_ index: Int) -> MenuBarItemID {
        MenuBarItemID(
            bundleIdentifier: "com.example.item\(index)",
            accessibilityIdentifier: "status-\(index)"
        )
    }

    private func descriptor(
        _ id: MenuBarItemID,
        order: Int,
        isSystem: Bool = false,
        isControl: Bool = false
    ) -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(
            id: id,
            section: .visible,
            order: order,
            displayID: primaryDisplay,
            isSystemItem: isSystem,
            isBarlineControlItem: isControl
        )
    }

    private func encodedItem(_ item: MenuBarItemID) -> [String: Any] {
        [
            "bundleIdentifier": item.bundleIdentifier,
            "accessibilityIdentifier": item.accessibilityIdentifier as Any,
        ]
    }

    private func rawEncode(_ profile: BarlineProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(profile)
    }

    private func archiveDocument(profiles: [[String: Any]]) -> [String: Any] {
        [
            "formatVersion": ProfileSchema.archiveFormatVersion,
            "exportedAt": "2026-01-01T00:00:00Z",
            "profiles": profiles,
        ]
    }
}

private extension UUID {
    init(_ suffix: UInt8) {
        self.init(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
    }
}
