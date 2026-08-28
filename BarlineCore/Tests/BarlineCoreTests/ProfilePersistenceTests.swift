//
//  ProfilePersistenceTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Profile persistence and Ice import")
struct ProfilePersistenceTests {
    @Test("Atomic saves preserve the previous valid file as a backup")
    func atomicSaveAndBackup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        let first = profile(id: UUID(1), name: "First")
        let second = profile(id: UUID(2), name: "Second")

        try await store.save([first], at: Date(timeIntervalSince1970: 100))
        let initial = try await store.load()
        #expect(initial.profiles == [first])
        #expect(initial.source == .primary)

        try await store.save([second], at: Date(timeIntervalSince1970: 200))
        let backupData = try Data(contentsOf: store.backupURL)
        let backup = try ProfileCodec().importArchive(backupData)

        #expect(try await store.load().profiles == [second])
        #expect(backup.profiles == [first])
    }

    @Test("A corrupt primary recovers from backup and repairs the primary file")
    func recoversCorruptPrimary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        let first = profile(id: UUID(3), name: "Known good")
        let second = profile(id: UUID(4), name: "Current")
        try await store.save([first], at: Date(timeIntervalSince1970: 100))
        try await store.save([second], at: Date(timeIntervalSince1970: 200))
        try Data("corrupt".utf8).write(to: store.primaryURL)

        let recovered = try await store.load()
        let repaired = try await store.load()

        #expect(recovered.profiles == [first])
        #expect(recovered.source == .recoveredBackup)
        #expect(recovered.repairedPrimaryFile)
        #expect(repaired.profiles == [first])
        #expect(repaired.source == .primary)
    }

    @Test("A missing primary can recover from a valid backup")
    func recoversMissingPrimary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        let saved = profile(id: UUID(5), name: "Backup only")
        let data = try ProfileCodec().export([saved])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: store.backupURL)

        let result = try await store.load()

        #expect(result.profiles == [saved])
        #expect(result.source == .recoveredBackup)
        #expect(result.repairedPrimaryFile)
    }

    @Test("A clean store reports no profiles without creating invalid JSON")
    func cleanStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)

        let result = try await store.load()

        #expect(result.profiles.isEmpty)
        #expect(result.source == .notCreated)
        #expect(!FileManager.default.fileExists(atPath: store.primaryURL.path))
    }

    @Test("Corrupt primary and backup fail closed")
    func unrecoverableCorruption() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("bad primary".utf8).write(to: store.primaryURL)
        try Data("bad backup".utf8).write(to: store.backupURL)

        await #expect(throws: ProfileStoreError.unreadablePrimaryAndBackup) {
            try await store.load()
        }
    }

    @Test("A corrupt orphaned backup is not mistaken for a clean store")
    func corruptOrphanedBackup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("bad backup".utf8).write(to: store.backupURL)

        await #expect(throws: ProfileStoreError.unreadablePrimaryAndBackup) {
            try await store.load()
        }
    }

    @Test("Invalid saves do not replace the last valid primary")
    func invalidSaveDoesNotClobber() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        let valid = profile(id: UUID(6), name: "Valid")
        try await store.save([valid])
        let invalid = BarlineProfile(name: "")

        await #expect(throws: ProfileValidationError.emptyName) {
            try await store.save([invalid])
        }

        #expect(try await store.load().profiles == [valid])
    }

    @Test("Ice preferences produce a complete preview without changing storage")
    func previewsIceImport() throws {
        let preferences = IcePreferenceSnapshot(
            source: .community,
            persistentDomain: [
                "UseIceBar": true,
                "ShowOnClick": false,
                "ShowOnHover": true,
                "ShowOnScroll": true,
                "AutoRehide": true,
                "RehideInterval": 2.5,
                "ItemSpacingOffset": 6.0,
                "HideApplicationMenus": false,
                "MenuBarAppearanceConfigurationV2": Data([1]),
                "Hotkeys": Data([2]),
            ]
        )

        let preview = try IceProfileImporter().preview(
            preferences: preferences,
            currentSnapshot: menuBarSnapshot(),
            now: Date(timeIntervalSince1970: 500)
        )

        #expect(preview.source == .community)
        #expect(preview.requiresConfirmation)
        #expect(preview.profile.layout.visible == [item(1)])
        #expect(preview.profile.layout.hidden == [item(2)])
        #expect(preview.profile.layout.alwaysHidden == [item(3)])
        #expect(preview.profile.shelfBehavior.isEnabled)
        #expect(!preview.profile.revealTriggers.click)
        #expect(preview.profile.revealTriggers.hover)
        #expect(preview.profile.revealTriggers.scroll)
        #expect(preview.profile.autoRehide.delaySeconds == 2.5)
        #expect(preview.profile.appearance.itemSpacing == 6)
        #expect(preview.profile.applicationMenuOverlapBehavior == .leaveVisible)
        #expect(preview.warnings.contains(.appearanceRequiresManualReview))
        #expect(preview.warnings.contains(.hotkeysRequireManualReview))
        #expect(preview.importedComponents == Set(IceImportedComponent.allCases))
    }

    @Test("Partial and mistyped Ice preferences use safe defaults and disclose omissions")
    func partialAndCorruptIcePreferences() throws {
        let preferences = IcePreferenceSnapshot(
            source: .upstream,
            persistentDomain: [
                "ShowOnHover": "not a boolean",
                "RehideInterval": true,
                "ItemSpacingOffset": -20.0,
            ]
        )

        let preview = try IceProfileImporter().preview(
            preferences: preferences,
            currentSnapshot: menuBarSnapshot()
        )

        #expect(preview.profile.revealTriggers == ProfileRevealTriggers())
        #expect(preview.profile.autoRehide == ProfileAutoRehide())
        #expect(preview.profile.appearance.itemSpacing == 0)
        #expect(preview.warnings.contains(.invalidPreferenceIgnored("ShowOnHover")))
        #expect(preview.warnings.contains(.invalidPreferenceIgnored("RehideInterval")))
    }

    @Test("Import commit requires explicit replacement on repeat")
    func repeatedImportRequiresReplacement() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileFileStore(directoryURL: directory)
        let preview = try IceProfileImporter().preview(
            preferences: IcePreferenceSnapshot(source: .community, revealOnClick: true),
            currentSnapshot: menuBarSnapshot(),
            now: Date(timeIntervalSince1970: 100)
        )
        await #expect(throws: ProfileStoreError.importConfirmationRequired) {
            try await store.commit(preview, confirmed: false)
        }
        _ = try await store.commit(preview, confirmed: true)

        await #expect(throws: ProfileStoreError.profileConflict(preview.profile.id)) {
            try await store.commit(preview, confirmed: true)
        }

        let replaced = try await store.commit(preview, confirmed: true, replacingExisting: true)
        #expect(replaced == [preview.profile])
    }

    @Test("Approved Ice domains map to distinct stable imported-profile IDs")
    func stableImportIDs() {
        #expect(IceInstallation.allCases.map(\.rawValue) == [
            "com.jordanbaird.Ice",
            "com.lxy1992.Ice",
        ])
        #expect(IceInstallation.upstream.importedProfileID != IceInstallation.community.importedProfileID)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("barline-profile-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func profile(id: UUID, name: String) -> BarlineProfile {
        BarlineProfile(
            id: id,
            name: name,
            layout: ProfileLayout(visible: [item(1)]),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func menuBarSnapshot() -> MenuBarSnapshot {
        let display = MenuBarDisplayID("display")
        return MenuBarSnapshot(
            generation: 7,
            capturedAt: Date(),
            items: [
                descriptor(item(1), section: .visible, order: 0, display: display),
                descriptor(item(2), section: .hidden, order: 0, display: display),
                descriptor(item(3), section: .alwaysHidden, order: 0, display: display),
                descriptor(item(4), section: .visible, order: 1, display: display, control: true),
            ],
            displayIDs: [display],
            activeSpaceIsValid: true
        )
    }

    private func descriptor(
        _ id: MenuBarItemID,
        section: MenuBarSection,
        order: Int,
        display: MenuBarDisplayID,
        control: Bool = false
    ) -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(
            id: id,
            section: section,
            order: order,
            displayID: display,
            isBarlineControlItem: control
        )
    }

    private func item(_ suffix: UInt8) -> MenuBarItemID {
        MenuBarItemID(
            bundleIdentifier: "com.example.item\(suffix)",
            accessibilityIdentifier: "item-\(suffix)"
        )
    }
}

private extension UUID {
    init(_ suffix: UInt8) {
        self.init(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, suffix))
    }
}
