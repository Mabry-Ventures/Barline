//
//  SearchItemPreferencesProbe.swift
//  Barline
//

import BarlineCore
import Darwin
import Foundation

/// Bounded, no-UI regression probe of the actual app persistence actor.
@main
enum SearchItemPreferencesProbe {
    enum Failure: Error { case check(String) }

    static let itemID = MenuBarItemID(
        bundleIdentifier: "com.example.search-probe",
        accessibilityIdentifier: "synthetic-item"
    )

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.check(message) }
    }

    static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("SearchItemPreferences.json")
    }

    static func requirePrivateFile(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        try require(
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            "committed file permissions must be 0600"
        )
    }

    static func requireNoStage(in directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try require(
            !names.contains { $0.hasPrefix(".SearchItemPreferences.") },
            "temporary stage must not survive success or failure"
        )
    }

    static func main() async throws {
        try require(CommandLine.arguments.count == 2, "expected isolated fixture directory")
        // Permission failure injection must not silently pass under root.
        try require(geteuid() != 0, "run probe as a non-root user")
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let directory = root.appendingPathComponent("preferences", isDirectory: true)
        let store = SearchItemPreferences(directory: directory)
        try await require(store.load() == .empty, "missing store loads empty")
        try require(!FileManager.default.fileExists(atPath: directory.path), "load performs no writes")
        _ = try await store.setFavorite(true, for: itemID)
        let file = storeURL(in: directory)
        try requirePrivateFile(file)
        _ = try await store.setAlias("My Alias", for: itemID)
        try requirePrivateFile(file)
        let reopened = SearchItemPreferences(directory: directory)
        let loaded = try await reopened.load()
        try require(
            loaded.isFavorite(itemID) && loaded.alias(for: itemID) == "My Alias",
            "first write and replacement survive reopen"
        )
        try requireNoStage(in: directory)
        print("PASS: first write, replacement, reopen, 0600 permissions, stage cleanup")

        var goodData = try Data(contentsOf: file)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.setAlias("Cancelled", for: itemID)
        }
        do {
            _ = try await cancelled.value
            throw Failure.check("cancelled operation must throw")
        } catch is CancellationError {}
        try require(Data(contentsOf: file) == goodData, "cancelled save preserves original bytes")
        try requireNoStage(in: directory)
        print("PASS: cancellation leaves original unchanged")

        do {
            _ = try await store.setAlias(String(repeating: "x", count: 65), for: itemID)
            throw Failure.check("invalid alias must throw")
        } catch is SearchItemPersonalization.ValidationError {}
        try require(Data(contentsOf: file) == goodData, "validation failure preserves original")
        try requireNoStage(in: directory)

        // Existing bytes remain readable, but staging cannot create a file.
        // This injects a genuine precommit I/O failure without production hooks.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        do {
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
            do {
                _ = try await store.setAlias("Must Not Commit", for: itemID)
                throw Failure.check("non-writable directory must reject staging")
            } catch let error as POSIXError {
                try require(error.code == .EACCES, "expected permission-denied staging failure")
            }
            try require(Data(contentsOf: file) == goodData, "precommit I/O failure preserves bytes")
            let cached = try await store.load()
            try require(cached.alias(for: itemID) == "My Alias", "precommit failure preserves cached state")
            try requireNoStage(in: directory)
        }
        _ = try await store.setAlias("Recovered", for: itemID)
        let recovered = try await SearchItemPreferences(directory: directory).load()
        try require(recovered.alias(for: itemID) == "Recovered", "same actor can save after precommit failure")
        try requirePrivateFile(file)
        try requireNoStage(in: directory)
        print("PASS: validation and real precommit I/O failure preserve disk/cache; retry succeeds")

        goodData = try Data(contentsOf: file)
        let external = try recovered.settingAlias("External", for: itemID).encoded()
        try external.write(to: file)
        do {
            _ = try await store.setFavorite(false, for: itemID)
            throw Failure.check("external replacement must block stale writer")
        } catch SearchItemPreferences.StoreError.changedStore {}
        try require(Data(contentsOf: file) == external, "external replacement preserved")
        let externalReopen = try await SearchItemPreferences(directory: directory).load()
        try require(externalReopen.alias(for: itemID) == "External", "valid external replacement reloads")
        try goodData.write(to: file)
        do {
            _ = try await store.setFavorite(false, for: itemID)
            throw Failure.check("stale writer remains blocked until reopen")
        } catch SearchItemPreferences.StoreError.damagedStore {}
        try require(Data(contentsOf: file) == goodData, "blocked writer does not overwrite restored data")
        print("PASS: external write blocks stale writer, preserves external bytes, fresh actor reloads")

        let malformed = Data("{ malformed }".utf8)
        try malformed.write(to: file)
        let damaged = SearchItemPreferences(directory: directory)
        do {
            _ = try await damaged.load()
            throw Failure.check("malformed load must fail")
        } catch SearchItemPreferences.StoreError.damagedStore {}
        do {
            _ = try await damaged.setAlias("Overwrite", for: itemID)
            throw Failure.check("damaged actor must reject writes")
        } catch SearchItemPreferences.StoreError.damagedStore {}
        try require(Data(contentsOf: file) == malformed, "malformed original preserved")
        try Data(count: SearchItemPersonalization.maximumEncodedBytes + 1).write(to: file)
        do {
            _ = try await SearchItemPreferences(directory: directory).load()
            throw Failure.check("oversized load must fail")
        } catch SearchItemPreferences.StoreError.damagedStore {}
        try requireNoStage(in: directory)
        print("PASS: malformed and oversized stores fail closed without replacing data")
    }
}
