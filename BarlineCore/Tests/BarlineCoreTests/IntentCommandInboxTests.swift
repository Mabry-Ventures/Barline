//
//  IntentCommandInboxTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("App Intent command inbox")
struct IntentCommandInboxTests {
    @Test("Multiple commands survive and retain chronological order")
    func multipleCommandsPersist() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = IntentCommandInbox(containerURL: directory)
        let profileID = UUID()
        let first = BarlineIntentCommand.activateProfile(
            profileID,
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let second = BarlineIntentCommand.setPresentationMode(
            true,
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 20)
        )

        try await inbox.enqueue(second)
        try await inbox.enqueue(first)

        #expect(try await inbox.pendingCommands() == [first, second])
    }

    @Test("Acknowledgement removes only the completed command")
    func acknowledgementIsSelective() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = IntentCommandInbox(containerURL: directory)
        let first = BarlineIntentCommand.open(.search)
        let second = BarlineIntentCommand.open(.profiles)
        try await inbox.enqueue(first)
        try await inbox.enqueue(second)

        try await inbox.acknowledge(first.id)

        #expect(try await inbox.pendingCommands() == [second])
    }

    @Test("Re-enqueuing the same command identifier is idempotent")
    func duplicateIdentifierDoesNotDuplicate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = IntentCommandInbox(containerURL: directory)
        let command = BarlineIntentCommand.setPresentationMode(false)

        try await inbox.enqueue(command)
        try await inbox.enqueue(command)

        #expect(try await inbox.pendingCommands() == [command])
    }

    @Test("Invalid and malformed commands never enter the pending stream")
    func invalidCommandsAreIgnored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = IntentCommandInbox(containerURL: directory)
        let invalid = BarlineIntentCommand(
            schemaVersion: BarlineIntentCommand.currentSchemaVersion,
            id: UUID(),
            createdAt: Date(),
            kind: .activateProfile,
            destination: .search,
            profileID: nil,
            presentationModeEnabled: nil
        )

        await #expect(throws: IntentCommandInboxError.invalidCommand) {
            try await inbox.enqueue(invalid)
        }

        let inboxDirectory = directory.appendingPathComponent(IntentCommandInbox.directoryName)
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: inboxDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        )
        #expect(try await inbox.pendingCommands().isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("barline-intent-inbox-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
