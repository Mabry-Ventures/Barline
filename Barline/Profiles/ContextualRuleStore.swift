//
//  ContextualRuleStore.swift
//  Barline
//

import BarlineCore
import Darwin
import Foundation

actor ContextualRuleStore {
    enum Failure: Error { case invalid, changed }
    private var url: URL?
    private var priorData: Data?
    private var loaded = false
    private static let limit = 128 * 1024

    init(url: URL? = nil) {
        self.url = url
    }

    func load() throws -> RuleAutomationPreferences {
        if url == nil {
            guard let identifier = Bundle.main.bundleIdentifier else { throw Failure.invalid }
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent(identifier, isDirectory: true)
            url = directory.appendingPathComponent("ContextualRules.json")
        }
        let data = try read()
        let value = try data.map { try JSONDecoder().decode(RuleAutomationPreferences.self, from: $0).validated() } ?? RuleAutomationPreferences()
        priorData = data
        loaded = true
        return value
    }

    func save(_ value: RuleAutomationPreferences) throws {
        _ = try value.validated()
        guard loaded, let url, try read() == priorData else { throw Failure.changed }
        let data = try JSONEncoder().encode(value)
        guard data.count <= Self.limit else { throw Failure.invalid }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staged = directory.appendingPathComponent(".rules-\(UUID().uuidString).tmp")
        let descriptor = open(staged.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure.invalid }
        defer { _ = unlink(staged.path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try Task.checkCancellation()
        guard try read() == priorData else { throw Failure.changed }
        guard rename(staged.path, url.path) == 0 else { throw Failure.invalid }
        priorData = data
    }

    private func read() throws -> Data? {
        guard let url else { throw Failure.invalid }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= Self.limit else { throw Failure.invalid }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.limit + 1) ?? Data()
            guard data.count <= Self.limit else { throw Failure.invalid }
            return data
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
