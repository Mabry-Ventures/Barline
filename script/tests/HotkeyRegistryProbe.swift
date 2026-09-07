//
//  HotkeyRegistryProbe.swift
//  Barline
//

import Foundation

/// Real Carbon registration only: no synthesized events, app launches or UI activation.
@main
@MainActor
enum HotkeyRegistryProbe {
    enum Failure: Error { case check(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.check(message) }
    }

    static func main() throws {
        let registry = HotkeyRegistry()
        let competitor = HotkeyRegistry()
        let first = KeyCombination(key: .f19, modifiers: [.control, .option, .command, .shift])
        let second = KeyCombination(key: .f18, modifiers: [.control, .option, .command, .shift])
        var errors = 0
        var actions = 0
        let id = try registry.register(combination: first, eventKind: .keyUp,
                                       stateChanged: {
                                           if $0 != nil {
                                               errors += 1
                                           }
                                       }, handler: { actions += 1 }).get()
        defer { registry.unregister(id) }
        try require(registry.isAvailable(id), "initial Carbon registration")
        if case .success = registry.register(combination: first, eventKind: .keyUp, stateChanged: { _ in }, handler: {}) {
            throw Failure.check("duplicate assignment accepted")
        }
        let token = registry.beginRecording()
        let nested = registry.beginRecording()
        let competingID = try competitor.register(combination: first, eventKind: .keyUp, stateChanged: { _ in }, handler: {}).get()
        defer { competitor.unregister(competingID) }
        registry.endRecording(token)
        try require(registry.isSuspended, "nested recorder must stay suspended")
        registry.endRecording(nested)
        try require(!registry.isSuspended && !registry.isAvailable(id) && errors == 1, "native resume conflict stays unavailable")
        competitor.unregister(competingID)
        let retry = registry.beginRecording()
        registry.endRecording(retry)
        try require(registry.isAvailable(id), "resume recovers after reservation released")
        let otherID = try competitor.register(combination: second, eventKind: .keyDown, stateChanged: { _ in }, handler: {}).get()
        defer { competitor.unregister(otherID) }
        if case .success = registry.register(combination: second, eventKind: .keyUp, replacing: id,
                                             stateChanged: { _ in }, handler: {})
        {
            throw Failure.check("native conflicting replacement accepted")
        }
        try require(registry.isAvailable(id), "failed replacement retains original")
        try require(actions == 0, "registration alone must not dispatch")
        registry.unregister(id)
        try require(!registry.isAvailable(id), "removed registration unavailable")
        let reacquired = try competitor.register(combination: first, eventKind: .keyUp, stateChanged: { _ in }, handler: {}).get()
        competitor.unregister(reacquired)
        print("PASS: real Carbon register, duplicate conflict, nested suspension, resume conflict/recovery, failed replacement, cleanup; zero events sent")
    }
}
