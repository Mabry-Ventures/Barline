//
//  ProfileManager.swift
//  Barline
//

import AppKit
import BarlineCore
import Combine
import Foundation
import OSLog

@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles = [BarlineProfile]()
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var loadSource: ProfileStoreLoadSource = .notCreated
    @Published private(set) var pendingArchiveImport: ProfileArchiveImportPreview?
    @Published private(set) var pendingIceImports = [IceImportPreview]()
    @Published private(set) var isBusy = false
    @Published var statusMessage: String?

    private static let appGroupIdentifier = "group.com.mabryventures.Barline"
    private static let profileCatalogKey = "intent.profileCatalog"
    private static let processedCommandIDsKey = "intent.processedCommandIDs"
    private static let profileBeforeFocusIDKey = "focus.profileBeforeFocusID"
    private static let presentationProfileIDKey = "focus.presentationProfileID"
    private static let presentationFocusActiveKey = "focus.presentationModeIsActive"
    private static let maximumProcessedCommandCount = 256

    private let store: ProfileFileStore
    private let commandInbox: IntentCommandInbox?
    private let bridgeDefaults = UserDefaults(suiteName: appGroupIdentifier)
    private let processedDefaults = UserDefaults.standard
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var profileBeforeFocusID: UUID?
    private var activationRequests = [ProfileActivationSource: ProfileActivationRequest]()
    private var bridgeObserver: DarwinNotificationObserver?
    private var isProcessingBridgeCommands = false
    private var needsBridgeCommandRescan = false

    init(fileManager: FileManager = .default) {
        let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )
        let baseURL = containerURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barline", isDirectory: true)
        store = ProfileFileStore(directoryURL: baseURL.appendingPathComponent("Profiles", isDirectory: true))
        commandInbox = containerURL.map(IntentCommandInbox.init(containerURL:))
        profileBeforeFocusID = processedDefaults.string(forKey: Self.profileBeforeFocusIDKey)
            .flatMap(UUID.init(uuidString:))
    }

    func performSetup(with appState: AppState) async {
        self.appState = appState
        configureBridgeObservers()
        await reload()
        await processBridgeCommands()
    }

    func reload() async {
        await performOperation(successMessage: nil) { [store] in
            let result = try await store.load()
            return (result.profiles, result.source)
        } completion: { [weak self] result in
            self?.profiles = result.0
            self?.loadSource = result.1
            self?.publishCatalog()
        }
    }

    func captureCurrentProfile(named name: String) async {
        guard let appState else { return }
        await performOperation(successMessage: "Profile saved.") {
            let snapshot = try await appState.compatibilityCoordinator.refresh()
            let profile = self.profileFromCurrentWorkspace(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                snapshot: snapshot
            )
            let updated = self.profiles + [profile]
            try await self.store.save(updated)
            return updated
        } completion: { [weak self] updated in
            self?.profiles = updated
            self?.publishCatalog()
        }
    }

    func createPresentationProfile() async {
        guard let appState else { return }
        let presentationID = resolvedPresentationProfile()?.id ?? PresentationProfileTemplateBuilder.profileID
        await performOperation(successMessage: "Presentation profile saved.") {
            let snapshot = try await appState.compatibilityCoordinator.refresh()
            let profile = PresentationProfileTemplateBuilder().makeTemplate(
                from: snapshot,
                id: presentationID
            ).profile
            let updated = self.profiles.filter { $0.id != presentationID } + [profile]
            try await self.store.save(updated)
            return updated
        } completion: { [weak self] updated in
            self?.profiles = updated
            self?.processedDefaults.set(
                presentationID.uuidString,
                forKey: Self.presentationProfileIDKey
            )
            self?.publishCatalog()
        }
    }

    @discardableResult
    func activate(_ profile: BarlineProfile, source: ProfileActivationSource = .manual) async -> Bool {
        guard let appState else { return false }
        activationRequests[source] = ProfileActivationRequest(profileID: profile.id, source: source)
        guard
            let request = ProfileActivationResolver().resolve(activationRequests.values),
            let resolvedProfile = profiles.first(where: { $0.id == request.profileID })
        else {
            return false
        }
        var didActivate = false
        await performOperation(successMessage: "Profile applied.") {
            let previousSpacingOffset = appState.spacingManager.offset
            appState.spacingManager.offset = Int(resolvedProfile.appearance.itemSpacing)
            do {
                try await appState.spacingManager.applyOffset()
                _ = try await appState.compatibilityCoordinator.activate(profile: resolvedProfile)
            } catch {
                let activationError = error
                appState.spacingManager.offset = previousSpacingOffset
                do {
                    try await appState.spacingManager.applyOffset()
                } catch {
                    throw MenuBarBackendError.operationFailed(
                        "profile activation failed: \(activationError); spacing rollback failed: \(error)"
                    )
                }
                throw activationError
            }
            return resolvedProfile.id
        } completion: { [weak self] profileID in
            self?.activeProfileID = profileID
            self?.applyWorkspaceSettings(from: resolvedProfile)
            didActivate = true
        }
        return didActivate
    }

    func update(
        _ profile: BarlineProfile,
        name: String,
        symbol: String?,
        groups: [ProfileGroup],
        spacers: [ProfileSpacer]
    ) async {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        if profile.name == "Presentation" || profile.id == PresentationProfileTemplateBuilder.profileID {
            processedDefaults.set(profile.id.uuidString, forKey: Self.presentationProfileIDKey)
        }
        let updatedProfile = BarlineProfile(
            id: profile.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol,
            layout: profile.layout,
            groups: groups,
            spacers: spacers,
            displayOverrides: profile.displayOverrides,
            appearance: profile.appearance,
            shelfBehavior: profile.shelfBehavior,
            revealTriggers: profile.revealTriggers,
            autoRehide: profile.autoRehide,
            applicationMenuOverlapBehavior: profile.applicationMenuOverlapBehavior,
            hotkey: profile.hotkey,
            createdAt: profile.createdAt,
            updatedAt: Date()
        )
        var updated = profiles
        updated[index] = updatedProfile
        await persist(updated, successMessage: "Profile updated.")
    }

    func resetFromCurrentWorkspace(_ profile: BarlineProfile) async {
        guard let appState,
              let index = profiles.firstIndex(where: { $0.id == profile.id })
        else { return }
        await performOperation(successMessage: "Profile reset from the current workspace.") {
            let snapshot = try await appState.compatibilityCoordinator.refresh()
            let reset = self.profileFromCurrentWorkspace(
                id: profile.id,
                name: profile.name,
                symbol: profile.symbol,
                snapshot: snapshot,
                createdAt: profile.createdAt
            )
            var updated = self.profiles
            updated[index] = reset
            try await self.store.save(updated)
            return updated
        } completion: { [weak self] updated in
            self?.profiles = updated
            self?.publishCatalog()
        }
    }

    func restoreLastKnownGoodLayout() async {
        guard let appState else { return }
        await performOperation(successMessage: "Last-known-good layout restored.") {
            _ = try await appState.compatibilityCoordinator.perform(.restoreLastKnownGood)
            return await appState.compatibilityCoordinator.activeProfileID
        } completion: { [weak self] profileID in
            self?.activeProfileID = profileID
        }
    }

    func undoLayoutChange() async {
        guard let appState else { return }
        await performOperation(successMessage: "Layout change undone.") {
            try await appState.compatibilityCoordinator.undo()
        } completion: { _ in }
    }

    func redoLayoutChange() async {
        guard let appState else { return }
        await performOperation(successMessage: "Layout change redone.") {
            try await appState.compatibilityCoordinator.redo()
        } completion: { _ in }
    }

    func archiveData() async -> Data? {
        guard !profiles.isEmpty else {
            statusMessage = "Create a profile before exporting an archive."
            return nil
        }
        isBusy = true
        defer { isBusy = false }
        let profiles = profiles
        do {
            let data = try await Task.detached {
                try ProfileCodec().export(profiles)
            }.value
            statusMessage = "Profile archive ready to save."
            return data
        } catch {
            statusMessage = "The profile archive could not be created."
            Logger(category: "Profiles").error("Profile archive export failed")
            return nil
        }
    }

    func previewArchiveImport(from url: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let archive = try await Task.detached {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                return try ProfileCodec().importArchive(data)
            }.value
            let existingIDs = Set(profiles.map(\.id))
            pendingArchiveImport = ProfileArchiveImportPreview(
                profiles: archive.profiles,
                conflictingProfileIDs: Set(archive.profiles.map(\.id)).intersection(existingIDs)
            )
            statusMessage = "Review the validated archive before importing."
        } catch {
            pendingArchiveImport = nil
            statusMessage = "This profile archive is invalid or unreadable."
            Logger(category: "Profiles").error("Profile archive import validation failed")
        }
    }

    func cancelArchiveImport() {
        pendingArchiveImport = nil
        statusMessage = "Profile import cancelled."
    }

    func commitArchiveImport(replacingExisting: Bool) async {
        guard let preview = pendingArchiveImport else { return }
        let importedIDs = Set(preview.profiles.map(\.id))
        let importedProfiles = replacingExisting
            ? preview.profiles
            : preview.profiles.filter { !preview.conflictingProfileIDs.contains($0.id) }
        guard !importedProfiles.isEmpty else {
            statusMessage = "Every imported profile already exists. Approve replacement to continue."
            return
        }
        let retained = profiles.filter { !replacingExisting || !importedIDs.contains($0.id) }
        let updated = retained + importedProfiles
        await performOperation(successMessage: "Profile archive imported.") {
            try await self.store.save(updated)
            return updated
        } completion: { [weak self] saved in
            if replacingExisting,
               let activeProfileID = self?.activeProfileID,
               importedIDs.contains(activeProfileID)
            {
                self?.activeProfileID = nil
            }
            self?.profiles = saved
            self?.pendingArchiveImport = nil
            self?.publishCatalog()
        }
    }

    func discoverIceImports() async {
        guard let appState else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let snapshot = try await appState.compatibilityCoordinator.refresh()
            let preferences = await IceDefaultsDomainReader().discover()
            let previews = try preferences.map {
                try IceProfileImporter().preview(preferences: $0, currentSnapshot: snapshot)
            }
            pendingIceImports = previews
            statusMessage = previews.isEmpty
                ? "No supported Ice preferences were found."
                : "Review the Ice import before saving it as a Barline profile."
        } catch {
            pendingIceImports = []
            statusMessage = "Ice preferences could not be previewed from the current layout."
            Logger(category: "Profiles").error("Ice profile import preview failed")
        }
    }

    func cancelIceImports() {
        pendingIceImports = []
        statusMessage = "Ice import cancelled."
    }

    func commitIceImport(_ preview: IceImportPreview, replacingExisting: Bool) async {
        await performOperation(successMessage: "Ice settings imported as a Barline profile.") {
            try await self.store.commit(
                preview,
                confirmed: true,
                replacingExisting: replacingExisting
            )
        } completion: { [weak self] updated in
            self?.profiles = updated
            self?.pendingIceImports.removeAll { $0.source == preview.source }
            self?.publishCatalog()
        }
    }

    func delete(_ profile: BarlineProfile) async {
        let remaining = profiles.filter { $0.id != profile.id }
        guard !remaining.isEmpty else {
            statusMessage = "Keep at least one profile so the store remains recoverable."
            return
        }
        await performOperation(successMessage: "Profile deleted.") {
            try await self.store.save(remaining)
            return remaining
        } completion: { [weak self] updated in
            self?.activationRequests = self?.activationRequests.filter { $0.value.profileID != profile.id } ?? [:]
            self?.profiles = updated
            if self?.activeProfileID == profile.id {
                self?.activeProfileID = nil
            }
            self?.publishCatalog()
        }
    }

    private func persist(_ updated: [BarlineProfile], successMessage: String) async {
        await performOperation(successMessage: successMessage) {
            try await self.store.save(updated)
            return updated
        } completion: { [weak self] saved in
            self?.profiles = saved
            self?.publishCatalog()
        }
    }

    private func profileFromCurrentWorkspace(
        id: UUID = UUID(),
        name: String,
        symbol: String? = nil,
        snapshot: MenuBarSnapshot,
        createdAt: Date = Date()
    ) -> BarlineProfile {
        let ordered = snapshot.items.sorted { lhs, rhs in
            lhs.section == rhs.section
                ? lhs.order < rhs.order
                : lhs.section.rawValue < rhs.section.rawValue
        }
        guard let appState else {
            return BarlineProfile(id: id, name: name, symbol: symbol, createdAt: createdAt)
        }
        let general = appState.settings.general
        let advanced = appState.settings.advanced
        return BarlineProfile(
            id: id,
            name: name,
            symbol: symbol,
            layout: ProfileLayout(
                visible: ordered.filter { $0.section == .visible }.map(\.id),
                hidden: ordered.filter { $0.section == .hidden }.map(\.id),
                alwaysHidden: ordered.filter { $0.section == .alwaysHidden }.map(\.id)
            ),
            appearance: ProfileAppearance(
                itemSpacing: min(
                    max(general.itemSpacingOffset, ProfileAppearance.itemSpacingRange.lowerBound),
                    ProfileAppearance.itemSpacingRange.upperBound
                )
            ),
            shelfBehavior: ProfileShelfBehavior(isEnabled: general.useBarlineShelf),
            revealTriggers: ProfileRevealTriggers(
                click: general.showOnClick,
                hover: general.showOnHover,
                scroll: general.showOnScroll
            ),
            autoRehide: ProfileAutoRehide(
                isEnabled: general.autoRehide,
                delaySeconds: max(0, general.rehideInterval)
            ),
            applicationMenuOverlapBehavior:
            advanced.hideApplicationMenus ? .hideWhenNeeded : .leaveVisible,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    private func applyWorkspaceSettings(from profile: BarlineProfile) {
        guard let appState else { return }
        let general = appState.settings.general
        general.useBarlineShelf = profile.shelfBehavior.isEnabled
        general.showOnClick = profile.revealTriggers.click
        general.showOnHover = profile.revealTriggers.hover
        general.showOnScroll = profile.revealTriggers.scroll
        general.itemSpacingOffset = profile.appearance.itemSpacing
        general.autoRehide = profile.autoRehide.isEnabled
        general.rehideInterval = profile.autoRehide.delaySeconds
        appState.settings.advanced.hideApplicationMenus =
            profile.applicationMenuOverlapBehavior == .hideWhenNeeded
    }

    private func configureBridgeObservers() {
        bridgeObserver = DarwinNotificationObserver(name: IntentCommandInbox.notificationName) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.processBridgeCommands()
            }
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.processBridgeCommands() }
            }
            .store(in: &cancellables)
    }

    private func processBridgeCommands() async {
        guard appState != nil, let commandInbox else { return }
        guard !isProcessingBridgeCommands else {
            needsBridgeCommandRescan = true
            return
        }

        isProcessingBridgeCommands = true
        defer { isProcessingBridgeCommands = false }

        repeat {
            needsBridgeCommandRescan = false
            let commands: [BarlineIntentCommand]
            do {
                commands = try await commandInbox.pendingCommands()
            } catch {
                Logger(category: "Profiles").error("Intent command inbox could not be read")
                return
            }

            for command in commands {
                if hasProcessed(command.id) {
                    try? await commandInbox.acknowledge(command.id)
                    continue
                }
                guard await handle(command) else { continue }
                recordProcessed(command.id)
                do {
                    try await commandInbox.acknowledge(command.id)
                } catch {
                    Logger(category: "Profiles").error("Processed intent command could not be acknowledged")
                }
            }
        } while needsBridgeCommandRescan
    }

    private func handle(_ command: BarlineIntentCommand) async -> Bool {
        guard let appState else { return false }

        switch command.kind {
        case .openDestination:
            guard let destination = command.destination else { return true }
            switch destination {
            case .search:
                appState.menuBarManager.searchPanel.show()
            case .profiles:
                appState.navigationState.settingsNavigationIdentifier = .profiles
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            case .settings:
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            }
            return true

        case .activateProfile:
            guard let profileID = command.profileID,
                  let profile = profiles.first(where: { $0.id == profileID })
            else {
                statusMessage = "The profile requested by Shortcuts is no longer available."
                return true
            }
            return await activate(profile, source: .appIntent)

        case .setPresentationMode:
            guard let isEnabled = command.presentationModeEnabled else { return true }
            return await applyPresentationMode(isEnabled)
        }
    }

    private func applyPresentationMode(_ isEnabled: Bool) async -> Bool {
        if isEnabled {
            if !processedDefaults.bool(forKey: Self.presentationFocusActiveKey) {
                profileBeforeFocusID = activeProfileID
                processedDefaults.set(profileBeforeFocusID?.uuidString, forKey: Self.profileBeforeFocusIDKey)
                processedDefaults.set(true, forKey: Self.presentationFocusActiveKey)
            }
            guard let presentation = resolvedPresentationProfile() else {
                statusMessage = "Create a Presentation profile before enabling the Focus filter."
                return true
            }
            return await activate(presentation, source: .focus)
        }

        guard let priorID = profileBeforeFocusID,
              let prior = profiles.first(where: { $0.id == priorID })
        else {
            activationRequests.removeValue(forKey: .focus)
            clearProfileBeforeFocus()
            return true
        }
        guard await activate(prior, source: .focus) else { return false }
        clearProfileBeforeFocus()
        return true
    }

    private func clearProfileBeforeFocus() {
        profileBeforeFocusID = nil
        processedDefaults.removeObject(forKey: Self.profileBeforeFocusIDKey)
        processedDefaults.set(false, forKey: Self.presentationFocusActiveKey)
    }

    private func resolvedPresentationProfile() -> BarlineProfile? {
        if let storedID = processedDefaults.string(forKey: Self.presentationProfileIDKey)
            .flatMap(UUID.init(uuidString:)),
            let profile = profiles.first(where: { $0.id == storedID })
        {
            return profile
        }
        if let stable = profiles.first(where: { $0.id == PresentationProfileTemplateBuilder.profileID }) {
            processedDefaults.set(stable.id.uuidString, forKey: Self.presentationProfileIDKey)
            return stable
        }
        if let legacy = profiles.first(where: { $0.name == "Presentation" }) {
            processedDefaults.set(legacy.id.uuidString, forKey: Self.presentationProfileIDKey)
            return legacy
        }
        return nil
    }

    private func hasProcessed(_ commandID: UUID) -> Bool {
        (processedDefaults.stringArray(forKey: Self.processedCommandIDsKey) ?? [])
            .contains(commandID.uuidString)
    }

    private func recordProcessed(_ commandID: UUID) {
        var identifiers = processedDefaults.stringArray(forKey: Self.processedCommandIDsKey) ?? []
        identifiers.removeAll { $0 == commandID.uuidString }
        identifiers.append(commandID.uuidString)
        if identifiers.count > Self.maximumProcessedCommandCount {
            identifiers.removeFirst(identifiers.count - Self.maximumProcessedCommandCount)
        }
        processedDefaults.set(identifiers, forKey: Self.processedCommandIDsKey)
    }

    private func publishCatalog() {
        struct Entry: Codable { let id: UUID; let name: String }
        let entries = profiles.map { Entry(id: $0.id, name: $0.name) }
        guard let data = try? JSONEncoder().encode(entries),
              let encoded = String(data: data, encoding: .utf8)
        else { return }
        bridgeDefaults?.set(encoded, forKey: Self.profileCatalogKey)
    }

    private func performOperation<Value: Sendable>(
        successMessage: String?,
        operation: () async throws -> Value,
        completion: (Value) -> Void
    ) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let value = try await operation()
            completion(value)
            statusMessage = successMessage
        } catch {
            statusMessage = "The profile operation could not be completed."
            Logger(category: "Profiles").error("Profile operation failed")
        }
    }
}
