//
//  FeaturePreferencesProbe.swift
//  Barline
//

import BarlineCore
import Darwin
import Foundation

@main
enum FeaturePreferencesProbe {
    enum Failure: Error { case check(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.check(message) }
    }

    static func rejects(_ message: String, operation: () async throws -> Void) async throws {
        do { try await operation() } catch { return }
        throw Failure.check(message)
    }

    static func main() async throws {
        try require(CommandLine.arguments.count == 2 && geteuid() != 0, "isolated non-root probe required")
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try await rules(in: root.appendingPathComponent("rules", isDirectory: true))
        try await shortcuts(in: root.appendingPathComponent("shortcuts", isDirectory: true))
        print("PASS: rules and shortcut persistence fault injection")
    }

    static func rules(in directory: URL) async throws {
        let file = directory.appendingPathComponent("ContextualRules.json")
        let store = ContextualRuleStore(url: file)
        let empty = try await store.load()
        try require(!empty.isEnabled && empty.rules.isEmpty, "rules default off")
        try require(!FileManager.default.fileExists(atPath: file.path), "loading creates no file")
        var value = RuleAutomationPreferences()
        value.isEnabled = true
        value.rules = [ContextualLayoutRule(targetLayoutID: UUID(), condition: .powerSource(.external))]
        try await store.save(value)
        let reloaded = try await ContextualRuleStore(url: file).load()
        try require(reloaded == value, "rule round trip")
        try privateFile(file)
        let data = try Data(contentsOf: file)
        var replacement = value
        replacement.isPaused = true
        let cancelled = Task { [replacement] in
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.save(replacement)
        }
        try await rejects("cancelled rule save succeeded") { try await cancelled.value }
        try require(Data(contentsOf: file) == data, "rule cancellation preserves bytes")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        try await rejects("unwritable rule save succeeded") { try await store.save(replacement) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try require(Data(contentsOf: file) == data, "rule I/O failure preserves bytes")
        try await store.save(replacement)
        let external = try JSONEncoder().encode(value)
        try external.write(to: file)
        try await rejects("stale rule writer succeeded") { try await store.save(replacement) }
        try require(Data(contentsOf: file) == external, "external rules preserved")
        try await malformedRules(file)
        try noStages(directory)
        print("PASS: rules off by default, round trip, private file, cancellation, write failure, external change, malformed/oversized/symlink")
    }

    static func malformedRules(_ file: URL) async throws {
        for data in [Data("{broken".utf8), Data(count: 128 * 1024 + 1)] {
            try data.write(to: file)
            let damaged = ContextualRuleStore(url: file)
            try await rejects("damaged rule load succeeded") { _ = try await damaged.load() }
            try await rejects("damaged rule write succeeded") { try await damaged.save(RuleAutomationPreferences()) }
            try require(Data(contentsOf: file) == data, "damaged rule data preserved")
        }
        let link = file.deletingLastPathComponent().appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try await rejects("rule symlink followed") { _ = try await ContextualRuleStore(url: link).load() }
    }

    static func shortcuts(in directory: URL) async throws {
        let store = ItemShortcutPreferences(directory: directory)
        _ = try await store.load()
        let id = MenuBarItemID(bundleIdentifier: "com.example.probe", accessibilityIdentifier: "item")
        let chord = ItemShortcutChord(keyCode: 0, modifiers: 1)
        _ = try await store.setChord(chord, for: id)
        let file = directory.appendingPathComponent("ItemShortcutPreferences.json")
        let saved = try await ItemShortcutPreferences(directory: directory).load()
        try require(saved.entries.count == 1, "shortcut round trip")
        try privateFile(file)
        let data = try Data(contentsOf: file)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await store.setChord(nil, for: id)
        }
        try await rejects("cancelled shortcut save succeeded") { try await cancelled.value }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        try await rejects("unwritable shortcut save succeeded") { _ = try await store.setChord(nil, for: id) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try require(Data(contentsOf: file) == data, "shortcut failure preserves bytes")
        _ = try await store.setChord(nil, for: id)
        try data.write(to: file)
        try await rejects("stale shortcut writer succeeded") { _ = try await store.setChord(nil, for: id) }
        try require(Data(contentsOf: file) == data, "external shortcut data preserved")
        for badData in [Data("{broken".utf8), Data(count: ItemShortcutBindings.maximumEncodedBytes + 1)] {
            try badData.write(to: file)
            let damaged = ItemShortcutPreferences(directory: directory)
            try await rejects("damaged shortcut load succeeded") { _ = try await damaged.load() }
            try await rejects("damaged shortcut write succeeded") { _ = try await damaged.setChord(chord, for: id) }
            try require(Data(contentsOf: file) == badData, "damaged shortcut data preserved")
        }
        try noStages(directory)
        print("PASS: shortcuts round trip, private file, cancellation, write failure, external change, malformed/oversized")
    }

    static func privateFile(_ file: URL) throws {
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        try require(mode?.intValue == 0o600, "file mode must be 0600")
    }

    static func noStages(_ directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try require(!names.contains { $0.hasSuffix(".tmp") }, "temporary stages must be cleaned")
    }
}
