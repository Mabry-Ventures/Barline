@testable import BarlineCore
import Foundation
import Testing

@Suite("Rule automation preferences")
struct RuleAutomationPreferencesTests {
    @Test("Automation is off until explicitly enabled and pause survives decoding")
    func defaultsAndRoundTrip() throws {
        var value = RuleAutomationPreferences()
        #expect(!value.isEnabled)
        #expect(!value.isPaused)
        #expect(value.rules.isEmpty)
        value.isEnabled = true
        value.isPaused = true
        value.rules = [ContextualLayoutRule(targetLayoutID: UUID(), condition: .batteryBelow(20))]
        let decoded = try JSONDecoder().decode(RuleAutomationPreferences.self, from: JSONEncoder().encode(value))
        #expect(try decoded.validated() == value)
    }

    @Test("Unsupported schema and invalid rules fail closed")
    func invalidPreferences() {
        var value = RuleAutomationPreferences()
        value.schemaVersion = 2
        #expect(throws: RuleAutomationPreferences.ValidationFailure.self) { try value.validated() }
        value.schemaVersion = 1
        value.rules = [ContextualLayoutRule(targetLayoutID: UUID(), condition: .batteryBelow(0))]
        #expect(throws: RuleAutomationPreferences.ValidationFailure.self) { try value.validated() }
    }
}
