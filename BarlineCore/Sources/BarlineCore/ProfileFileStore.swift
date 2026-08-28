//
//  ProfileFileStore.swift
//  Barline
//

import Foundation

public enum ProfileStoreLoadSource: String, Codable, Sendable {
    case primary
    case recoveredBackup
    case notCreated
}

public struct ProfileStoreLoadResult: Sendable {
    public let profiles: [BarlineProfile]
    public let source: ProfileStoreLoadSource
    public let repairedPrimaryFile: Bool

    public init(
        profiles: [BarlineProfile],
        source: ProfileStoreLoadSource,
        repairedPrimaryFile: Bool
    ) {
        self.profiles = profiles
        self.source = source
        self.repairedPrimaryFile = repairedPrimaryFile
    }
}

public enum ProfileStoreError: Error, Equatable, Sendable {
    case unreadablePrimaryAndBackup
    case profileConflict(UUID)
    case importConfirmationRequired
    case invalidStoreLocation
    case filesystemOperationFailed
}

/// Actor-isolated JSON storage for app-side profile persistence.
///
/// Callers supply an app-owned directory, normally beneath Application Support
/// or the App Group container. No filesystem work executes on the main actor.
public actor ProfileFileStore {
    public nonisolated let directoryURL: URL
    public nonisolated let primaryURL: URL
    public nonisolated let backupURL: URL

    private let codec: ProfileCodec

    public init(
        directoryURL: URL,
        primaryFilename: String = "profiles.json",
        backupFilename: String = "profiles.backup.json",
        codec: ProfileCodec = ProfileCodec()
    ) {
        self.directoryURL = directoryURL
        primaryURL = directoryURL.appendingPathComponent(primaryFilename, isDirectory: false)
        backupURL = directoryURL.appendingPathComponent(backupFilename, isDirectory: false)
        self.codec = codec
    }

    public func load() throws -> ProfileStoreLoadResult {
        try ensureDirectory()
        let manager = FileManager.default
        guard manager.fileExists(atPath: primaryURL.path) else {
            if manager.fileExists(atPath: backupURL.path) {
                guard let recovered = tryDecode(backupURL) else {
                    throw ProfileStoreError.unreadablePrimaryAndBackup
                }
                let repaired = (try? writeAtomically(recovered.data, to: primaryURL)) != nil
                return ProfileStoreLoadResult(
                    profiles: recovered.archive.profiles,
                    source: .recoveredBackup,
                    repairedPrimaryFile: repaired
                )
            }
            return ProfileStoreLoadResult(profiles: [], source: .notCreated, repairedPrimaryFile: false)
        }

        if let primary = tryDecode(primaryURL) {
            return ProfileStoreLoadResult(
                profiles: primary.archive.profiles,
                source: .primary,
                repairedPrimaryFile: false
            )
        }

        guard let recovered = tryDecode(backupURL) else {
            throw ProfileStoreError.unreadablePrimaryAndBackup
        }
        let repaired = (try? writeAtomically(recovered.data, to: primaryURL)) != nil
        return ProfileStoreLoadResult(
            profiles: recovered.archive.profiles,
            source: .recoveredBackup,
            repairedPrimaryFile: repaired
        )
    }

    public func save(_ profiles: [BarlineProfile], at date: Date = Date()) throws {
        let encoded = try codec.export(profiles, at: date)
        try ensureDirectory()

        if let current = tryDecode(primaryURL) {
            try writeAtomically(current.data, to: backupURL)
        }
        try writeAtomically(encoded, to: primaryURL)
    }

    @discardableResult
    public func commit(
        _ preview: IceImportPreview,
        confirmed: Bool,
        replacingExisting: Bool = false,
        at date: Date = Date()
    ) throws -> [BarlineProfile] {
        guard confirmed, preview.requiresConfirmation else {
            throw ProfileStoreError.importConfirmationRequired
        }
        var profiles = try load().profiles
        if let index = profiles.firstIndex(where: { $0.id == preview.profile.id }) {
            guard replacingExisting else {
                throw ProfileStoreError.profileConflict(preview.profile.id)
            }
            profiles[index] = preview.profile
        } else {
            profiles.append(preview.profile)
        }
        try save(profiles, at: date)
        return profiles
    }

    private func ensureDirectory() throws {
        guard directoryURL.isFileURL, !directoryURL.path.isEmpty else {
            throw ProfileStoreError.invalidStoreLocation
        }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ProfileStoreError.filesystemOperationFailed
        }
    }

    private func tryDecode(_ url: URL) -> (data: Data, archive: ProfileArchive)? {
        guard let data = try? Data(contentsOf: url),
              let archive = try? codec.importArchive(data)
        else {
            return nil
        }
        return (data, archive)
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ProfileStoreError.filesystemOperationFailed
        }
    }
}
