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
    @Published private(set) var isBusy = false
    @Published var statusMessage: String?

    private static let appGroupIdentifier = "group.com.mabryventures.Barline"
    private static let profileCatalogKey = "intent.profileCatalog"
    private static let pendingDestinationKey = "intent.pendingDestination"
    private static let pendingDestinationTokenKey = "intent.pendingDestinationToken"
    private static let pendingProfileKey = "intent.pendingProfile"
    private static let pendingProfileTokenKey = "intent.pendingProfileToken"
    private static let presentationModeKey = "focus.presentationMode"
    private static let presentationModeTokenKey = "focus.presentationModeToken"

    private let store: ProfileFileStore
    private let bridgeDefaults = UserDefaults(suiteName: appGroupIdentifier)
    private let processedDefaults = UserDefaults.standard
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var profileBeforeFocusID: UUID?
    private var activationRequests = [ProfileActivationSource: ProfileActivationRequest]()

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barline", isDirectory: true)
        store = ProfileFileStore(directoryURL: baseURL.appendingPathComponent("Profiles", isDirectory: true))
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
            let ordered = snapshot.items.sorted { lhs, rhs in
                lhs.section == rhs.section ? lhs.order < rhs.order : lhs.section.rawValue < rhs.section.rawValue
            }
            let profile = BarlineProfile(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                layout: ProfileLayout(
                    visible: ordered.filter { $0.section == .visible }.map(\.id),
                    hidden: ordered.filter { $0.section == .hidden }.map(\.id),
                    alwaysHidden: ordered.filter { $0.section == .alwaysHidden }.map(\.id)
                )
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
        await performOperation(successMessage: "Presentation profile saved.") {
            let snapshot = try await appState.compatibilityCoordinator.refresh()
            let profile = PresentationProfileTemplateBuilder().makeTemplate(from: snapshot).profile
            let updated = self.profiles.filter { $0.name != profile.name } + [profile]
            try await self.store.save(updated)
            return updated
        } completion: { [weak self] updated in
            self?.profiles = updated
            self?.publishCatalog()
        }
    }

    func activate(_ profile: BarlineProfile, source: ProfileActivationSource = .manual) async {
        guard let appState else { return }
        activationRequests[source] = ProfileActivationRequest(profileID: profile.id, source: source)
        guard
            let request = ProfileActivationResolver().resolve(activationRequests.values),
            let resolvedProfile = profiles.first(where: { $0.id == request.profileID })
        else {
            return
        }
        await performOperation(successMessage: "Profile applied.") {
            _ = try await appState.compatibilityCoordinator.activate(profile: resolvedProfile)
            return resolvedProfile.id
        } completion: { [weak self] profileID in
            self?.activeProfileID = profileID
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

    private func configureBridgeObservers() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: bridgeDefaults)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .sink { [weak self] _ in
                Task { await self?.processBridgeCommands() }
            }
            .store(in: &cancellables)
    }

    private func processBridgeCommands() async {
        guard let appState, let bridgeDefaults else { return }

        if consumeToken(forKey: Self.pendingDestinationTokenKey, from: bridgeDefaults),
           let rawDestination = bridgeDefaults.string(forKey: Self.pendingDestinationKey)
        {
            switch rawDestination {
            case "search": appState.menuBarManager.searchPanel.show()
            case "profiles":
                appState.navigationState.settingsNavigationIdentifier = .profiles
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            case "settings":
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            default: break
            }
        }

        if consumeToken(forKey: Self.pendingProfileTokenKey, from: bridgeDefaults),
           let rawProfileID = bridgeDefaults.string(forKey: Self.pendingProfileKey),
           let profileID = UUID(uuidString: rawProfileID),
           let profile = profiles.first(where: { $0.id == profileID })
        {
            await activate(profile, source: .appIntent)
        }

        if consumeToken(forKey: Self.presentationModeTokenKey, from: bridgeDefaults) {
            let isEnabled = bridgeDefaults.bool(forKey: Self.presentationModeKey)
            if isEnabled {
                profileBeforeFocusID = activeProfileID
                if let presentation = profiles.first(where: { $0.name == "Presentation" }) {
                    await activate(presentation, source: .focus)
                } else {
                    statusMessage = "Create a Presentation profile before enabling the Focus filter."
                }
            } else if let priorID = profileBeforeFocusID,
                      let prior = profiles.first(where: { $0.id == priorID })
            {
                await activate(prior, source: .focus)
                profileBeforeFocusID = nil
            }
        }
    }

    private func consumeToken(forKey key: String, from defaults: UserDefaults) -> Bool {
        guard let token = defaults.string(forKey: key) else { return false }
        let processedKey = "processed.\(key)"
        guard processedDefaults.string(forKey: processedKey) != token else { return false }
        processedDefaults.set(token, forKey: processedKey)
        return true
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
