//
//  ItemShortcutBindingsTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Stable item shortcut assignments")
struct ItemShortcutBindingsTests {
    private let first = MenuBarItemID(bundleIdentifier: "com.example.fixture", accessibilityIdentifier: "first")
    private let second = MenuBarItemID(bundleIdentifier: "com.example.fixture", accessibilityIdentifier: "second")
    private let chord = ItemShortcutChord(keyCode: 0, modifiers: 9)

    @Test("Stable identity survives round trip and unavailable targets are retained")
    func roundTrip() throws {
        let value = try ItemShortcutBindings().setting(chord, for: first)
        #expect(try ItemShortcutBindings.decode(value.encoded()) == value)
        #expect(value.entries.first?.itemID == first)
        #expect(try value.setting(nil, for: second) == value)
        #expect(try value.setting(nil, for: first).entries.isEmpty)
    }

    @Test("Conflicting assignments reject the complete candidate without changing the original")
    func conflict() throws {
        let value = try ItemShortcutBindings().setting(chord, for: first)
        #expect(throws: ItemShortcutBindings.ValidationError.duplicateChord) {
            try value.setting(chord, for: second)
        }
        #expect(value.entries.count == 1)
        #expect(throws: ItemShortcutBindings.ValidationError.duplicateIdentity) {
            try ItemShortcutBindings(entries: [.init(itemID: first, chord: chord), .init(itemID: first, chord: chord)])
        }
    }

    @Test("Malformed chords cannot reach Carbon integer conversion", arguments: [-1, 128, Int.max, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63])
    func invalidKeys(key: Int) {
        #expect(!ItemShortcutChord(keyCode: key, modifiers: 9).isValid)
    }

    @Test("Bare, shift-only and unknown modifier masks are rejected", arguments: [-1, 0, 4, 16, Int.max])
    func invalidModifiers(modifiers: Int) {
        #expect(!ItemShortcutChord(keyCode: 0, modifiers: modifiers).isValid)
    }

    @Test("Malformed identities and oversized stores are rejected")
    func bounds() throws {
        #expect(throws: ItemShortcutBindings.ValidationError.invalidIdentity) {
            try ItemShortcutBindings().setting(chord, for: MenuBarItemID(bundleIdentifier: ""))
        }
        #expect(throws: ItemShortcutBindings.ValidationError.tooLarge) {
            try ItemShortcutBindings.decode(Data(repeating: 0, count: ItemShortcutBindings.maximumEncodedBytes + 1))
        }
        let value = try ItemShortcutBindings().setting(chord, for: first)
        let data = try value.encoded()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 99
        let future = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ItemShortcutBindings.ValidationError.invalidVersion) {
            try ItemShortcutBindings.decode(future)
        }
    }

    @Test("Repeat events dispatch once and releases without a press do nothing")
    func pressCycle() {
        var cycle = ShortcutPressCycle()
        let unpairedRelease = cycle.keyUp(1)
        let firstPress = cycle.keyDown(1)
        let firstRepeat = cycle.keyDown(1)
        let secondRepeat = cycle.keyDown(1)
        let firstRelease = cycle.keyUp(1)
        let repeatedRelease = cycle.keyUp(1)
        let nextPress = cycle.keyDown(1)
        let nextRelease = cycle.keyUp(1)
        #expect(!unpairedRelease)
        #expect(firstPress)
        #expect(!firstRepeat)
        #expect(!secondRepeat)
        #expect(firstRelease)
        #expect(!repeatedRelease)
        #expect(nextPress)
        #expect(nextRelease)
    }

    @Test("Suspension cancels a pending press and separate bindings stay independent")
    func suspension() {
        var cycle = ShortcutPressCycle()
        let firstPress = cycle.keyDown(1)
        let secondPress = cycle.keyDown(2)
        let firstRelease = cycle.keyUp(1)
        #expect(firstPress)
        #expect(secondPress)
        #expect(firstRelease)
        cycle.reset()
        let canceledRelease = cycle.keyUp(2)
        let nextPress = cycle.keyDown(2)
        let nextRelease = cycle.keyUp(2)
        #expect(!canceledRelease)
        #expect(nextPress)
        #expect(nextRelease)
    }
}
