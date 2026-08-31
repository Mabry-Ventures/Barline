//
//  BarlineIntents.swift
//  Barline
//

import AppIntents
import Foundation

private enum BarlineIntentBridge {
    static var appGroupIdentifier: String {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "BarlineAppGroupIdentifier") as? String,
              !identifier.isEmpty,
              !identifier.contains("$(")
        else {
            return "group.com.mabryventures.Barline"
        }
        return identifier
    }

    static let profileCatalogKey = "intent.profileCatalog"
    static let commandDirectoryName = "IntentCommands"
    static let notificationName = "com.mabryventures.Barline.intent-command-enqueued"

    private struct Command: Codable {
        let schemaVersion: Int
        let id: UUID
        let createdAt: Date
        let kind: String
        let destination: String?
        let profileID: UUID?
        let presentationModeEnabled: Bool?
    }

    enum BridgeError: Error {
        case appGroupUnavailable
    }

    static func store(destination: BarlineDestination) throws {
        try enqueue(
            kind: "openDestination",
            destination: destination.rawValue
        )
    }

    static func store(profileID: UUID) throws {
        try enqueue(kind: "activateProfile", profileID: profileID)
    }

    static func storeFocusProfile(_ profileID: UUID?) throws {
        try enqueue(kind: "setFocusProfile", profileID: profileID)
    }

    private static func enqueue(
        kind: String,
        destination: String? = nil,
        profileID: UUID? = nil,
        presentationModeEnabled: Bool? = nil
    ) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw BridgeError.appGroupUnavailable
        }

        let directoryURL = containerURL.appendingPathComponent(commandDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let command = Command(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            kind: kind,
            destination: destination,
            profileID: profileID,
            presentationModeEnabled: presentationModeEnabled
        )
        let data = try JSONEncoder().encode(command)
        try data.write(
            to: directoryURL.appendingPathComponent(command.id.uuidString).appendingPathExtension("json"),
            options: [.atomic]
        )

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

private struct ProfileCatalogEntry: Codable {
    let id: UUID
    let name: String
}

struct BarlineProfileEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Menu Bar Layout")
    static let defaultQuery = BarlineProfileQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BarlineProfileQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [BarlineProfileEntity] {
        catalog().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [BarlineProfileEntity] {
        let normalized = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return catalog().filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(normalized)
        }
    }

    func suggestedEntities() async throws -> [BarlineProfileEntity] {
        catalog()
    }

    private func catalog() -> [BarlineProfileEntity] {
        guard let encoded = UserDefaults(suiteName: BarlineIntentBridge.appGroupIdentifier)?
            .string(forKey: BarlineIntentBridge.profileCatalogKey),
            let data = encoded.data(using: .utf8),
            let entries = try? JSONDecoder().decode([ProfileCatalogEntry].self, from: data)
        else {
            return []
        }
        return entries.map { BarlineProfileEntity(id: $0.id, name: $0.name) }
    }
}

enum BarlineDestination: String, AppEnum {
    case search
    case profiles
    case settings

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Barline Destination")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .search: "Search Menu Bar Items",
        .profiles: "Profiles",
        .settings: "Settings",
    ]
}

struct OpenBarlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Barline"
    static let description = IntentDescription("Opens Barline at a specific destination.")
    static var supportedModes: IntentModes {
        .foreground
    }

    @Parameter(title: "Destination", default: .search)
    var destination: BarlineDestination

    func perform() async throws -> some IntentResult {
        try BarlineIntentBridge.store(destination: destination)
        return .result()
    }
}

struct SwitchBarlineProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Menu Bar Layout"
    static let description = IntentDescription(
        "Requests a saved menu bar layout. Barline validates and applies it transactionally in the app process."
    )
    static var supportedModes: IntentModes {
        .foreground
    }

    @Parameter(title: "Profile")
    var profile: BarlineProfileEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try BarlineIntentBridge.store(profileID: profile.id)
        return .result(dialog: "Profile request sent to Barline for \(profile.name).")
    }
}

struct BarlineFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Menu Bar Layout"
    static let description = IntentDescription(
        "Choose the saved menu bar layout Barline applies while this macOS Focus is active."
    )

    @Parameter(title: "Menu Bar Layout")
    var profile: BarlineProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        if let profile {
            return DisplayRepresentation(title: "\(profile.name)")
        }
        return DisplayRepresentation(title: "No Profile")
    }

    func perform() async throws -> some IntentResult {
        try BarlineIntentBridge.storeFocusProfile(profile?.id)
        return .result()
    }
}

struct BarlineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBarlineIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Search my menu bar with \(.applicationName)",
            ],
            shortTitle: "Open Barline",
            systemImageName: "menubar.rectangle"
        )
        AppShortcut(
            intent: SwitchBarlineProfileIntent(),
            phrases: [
                "Switch profile in \(.applicationName)",
            ],
            shortTitle: "Switch Layout",
            systemImageName: "person.crop.rectangle.stack"
        )
    }
}
