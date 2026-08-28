//
//  IntentCommandInbox.swift
//  Barline
//

import Foundation

public enum BarlineIntentDestination: String, Codable, Sendable {
    case search
    case profiles
    case settings
}

public enum BarlineIntentCommandKind: String, Codable, Sendable {
    case openDestination
    case activateProfile
    case setPresentationMode
}

/// A durable command written by the App Intents extension and consumed by the
/// main app. The flat representation is intentionally stable so an extension
/// can write it without linking the rest of BarlineCore.
public struct BarlineIntentCommand: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date
    public let kind: BarlineIntentCommandKind
    public let destination: BarlineIntentDestination?
    public let profileID: UUID?
    public let presentationModeEnabled: Bool?

    public static func open(
        _ destination: BarlineIntentDestination,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: currentSchemaVersion,
            id: id,
            createdAt: createdAt,
            kind: .openDestination,
            destination: destination,
            profileID: nil,
            presentationModeEnabled: nil
        )
    }

    public static func activateProfile(
        _ profileID: UUID,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: currentSchemaVersion,
            id: id,
            createdAt: createdAt,
            kind: .activateProfile,
            destination: nil,
            profileID: profileID,
            presentationModeEnabled: nil
        )
    }

    public static func setPresentationMode(
        _ isEnabled: Bool,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: currentSchemaVersion,
            id: id,
            createdAt: createdAt,
            kind: .setPresentationMode,
            destination: nil,
            profileID: nil,
            presentationModeEnabled: isEnabled
        )
    }

    public var isValid: Bool {
        guard schemaVersion == Self.currentSchemaVersion else { return false }
        return switch kind {
        case .openDestination:
            destination != nil && profileID == nil && presentationModeEnabled == nil
        case .activateProfile:
            destination == nil && profileID != nil && presentationModeEnabled == nil
        case .setPresentationMode:
            destination == nil && profileID == nil && presentationModeEnabled != nil
        }
    }
}

public enum IntentCommandInboxError: Error, Equatable, Sendable {
    case invalidCommand
}

/// A one-file-per-command inbox. Unique filenames avoid cross-process
/// read-modify-write races, and atomic replacement prevents partial commands
/// from becoming visible to the consumer.
public actor IntentCommandInbox {
    public static let directoryName = "IntentCommands"
    public static let notificationName = "com.mabryventures.Barline.intent-command-enqueued"

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(containerURL: URL) {
        directoryURL = containerURL.appendingPathComponent(Self.directoryName, isDirectory: true)
        fileManager = .default
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public func enqueue(_ command: BarlineIntentCommand) throws {
        guard command.isValid else { throw IntentCommandInboxError.invalidCommand }
        try ensureDirectoryExists()
        let data = try encoder.encode(command)
        try data.write(to: url(for: command.id), options: [.atomic])
    }

    public func pendingCommands() throws -> [BarlineIntentCommand] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let expectedID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url),
                  let command = try? decoder.decode(BarlineIntentCommand.self, from: data),
                  command.id == expectedID,
                  command.isValid
            else {
                return nil
            }
            return command
        }
        .sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
    }

    public func acknowledge(_ commandID: UUID) throws {
        let commandURL = url(for: commandID)
        guard fileManager.fileExists(atPath: commandURL.path) else { return }
        try fileManager.removeItem(at: commandURL)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func url(for commandID: UUID) -> URL {
        directoryURL.appendingPathComponent(commandID.uuidString, isDirectory: false)
            .appendingPathExtension("json")
    }
}
