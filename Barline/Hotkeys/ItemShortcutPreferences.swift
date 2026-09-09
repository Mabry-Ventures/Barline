//
//  ItemShortcutPreferences.swift
//  Barline
//

import BarlineCore
import Darwin
import Foundation

/// Sole file owner. No filesystem work runs on the SwiftUI/main executor.
actor ItemShortcutPreferences {
    enum StoreError: Error { case unavailable, damagedStore, changedStore }

    private let suppliedDirectory: URL?
    private var fileURL: URL?
    private var snapshot = ItemShortcutBindings()
    private var loadedData: Data?
    private var hasLoaded = false
    private var writeBlocked = false

    init(directory: URL? = nil) {
        suppliedDirectory = directory
    }

    func load() throws -> ItemShortcutBindings {
        if hasLoaded {
            return snapshot
        }
        do {
            let directory: URL
            if let suppliedDirectory {
                directory = suppliedDirectory
            } else {
                guard let bundleID = Bundle.main.bundleIdentifier else { throw StoreError.unavailable }
                directory = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                ).appendingPathComponent(bundleID, isDirectory: true)
            }
            fileURL = directory.appendingPathComponent("ItemShortcutPreferences.json")
            let data = try readCurrentData()
            let decoded = try data.map(ItemShortcutBindings.decode) ?? ItemShortcutBindings()
            snapshot = decoded
            loadedData = data
            hasLoaded = true
            return snapshot
        } catch {
            writeBlocked = true
            throw StoreError.damagedStore
        }
    }

    func setChord(_ value: ItemShortcutChord?, for itemID: MenuBarItemID) throws -> ItemShortcutBindings {
        try commit { try $0.setting(value, for: itemID) }
    }

    private func commit(_ transform: (ItemShortcutBindings) throws -> ItemShortcutBindings) throws -> ItemShortcutBindings {
        try Task.checkCancellation()
        guard !writeBlocked else { throw StoreError.damagedStore }
        _ = try load()
        guard let fileURL else { throw StoreError.unavailable }
        // Never overwrite a file that changed after it was validated. A relaunch
        // can load a valid external replacement; malformed originals stay intact.
        guard try readCurrentData() == loadedData else {
            writeBlocked = true
            throw StoreError.changedStore
        }
        let replacement = try transform(snapshot)
        let encoded = try replacement.encoded()
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let stagedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".ItemShortcutPreferences.\(UUID().uuidString).tmp")
        // Create privately and exclusively: no permissive intermediate file and
        // no follow-up chmod that could fail after the authoritative rename.
        let descriptor = open(stagedURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = unlink(stagedURL.path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard fchmod(descriptor, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try handle.write(contentsOf: encoded)
        try handle.synchronize()
        try handle.close()
        // Revalidate after staging too; failed validation, I/O or cancellation
        // leaves the original untouched and the stage is cleaned up above.
        guard try readCurrentData() == loadedData else {
            writeBlocked = true
            throw StoreError.changedStore
        }
        try Task.checkCancellation()
        guard rename(stagedURL.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // Nothing after this commit point may throw or report an unchanged save.
        snapshot = replacement
        loadedData = encoded
        return snapshot
    }

    private func readCurrentData() throws -> Data? {
        guard let fileURL else { throw StoreError.unavailable }
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= ItemShortcutBindings.maximumEncodedBytes
            else { throw StoreError.damagedStore }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: ItemShortcutBindings.maximumEncodedBytes + 1) ?? Data()
            guard data.count <= ItemShortcutBindings.maximumEncodedBytes else { throw StoreError.damagedStore }
            return data
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
