@testable import BarlineCore
import Foundation
import Testing

@Suite("Deterministic contextual layout proposals")
struct ContextualLayoutRulesTests {
    private let now = Date(timeIntervalSince1970: 1000)
    private let firstLayout = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondLayout = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test("Typed predicates explain the selected proposal", arguments: [
        (ContextualLayoutRule.Condition.foregroundBundle("COM.EXAMPLE.EDITOR"), ContextualLayoutRuleReason.foregroundBundleMatched),
        (.powerSource(.battery), .powerSourceMatched),
        (.batteryBelow(25), .lowBatteryMatched),
    ])
    func matchingPredicates(_ condition: ContextualLayoutRule.Condition, _ reason: ContextualLayoutRuleReason) {
        let rule = ContextualLayoutRule(targetLayoutID: firstLayout, condition: condition)
        let result = evaluate([rule])
        guard case let .proposal(proposal) = result else { Issue.record("Expected a proposal"); return }
        #expect(proposal.contextGeneration == 7)
        #expect(proposal.ruleID == rule.id)
        #expect(proposal.targetLayoutID == firstLayout)
        #expect(proposal.reason == reason)
        for _ in 0 ..< 100 {
            #expect(evaluate([rule]) == result)
        }
    }

    @Test("Priority wins, with persisted order as an explicit stable tie-breaker")
    func conflicts() {
        let first = ContextualLayoutRule(targetLayoutID: firstLayout, priority: 1, condition: .powerSource(.battery))
        let second = ContextualLayoutRule(targetLayoutID: secondLayout, priority: 1, condition: .batteryBelow(25))
        #expect(target(evaluate([first, second])) == firstLayout)
        #expect(target(evaluate([second, first])) == secondLayout)
        let higher = ContextualLayoutRule(targetLayoutID: secondLayout, priority: 2, condition: .batteryBelow(25))
        #expect(target(evaluate([first, higher])) == secondLayout)
    }

    @Test("Native Focus outranks every custom rule and manual override suspends automation")
    func externalAuthority() {
        #expect(evaluate([rule()], context: context(focus: true, manual: true)) == .deferred(.nativeFocusActive))
        #expect(evaluate([rule()], context: context(manual: true)) == .deferred(.manualOverrideActive))
        #expect(evaluate([rule()], context: context(focus: nil)) == .noChange(.missingContext))
    }

    @Test("User interaction, mutation and recovery each defer proposed changes")
    func unsafeWindows() {
        #expect(evaluate([rule()], context: context(interacting: true)) == .deferred(.interactionActive))
        #expect(evaluate([rule()], context: context(mutating: true)) == .deferred(.mutationActive))
        #expect(evaluate([rule()], context: context(recovering: true)) == .deferred(.recoveryPending))
    }

    @Test("Missing or stale context never produces a mutation proposal")
    func unavailableContext() {
        let foreground = rule(.foregroundBundle("com.example.editor"))
        #expect(evaluate([foreground], context: context(foreground: nil)) == .noChange(.missingContext))
        #expect(evaluate([rule()], context: context(power: nil)) == .noChange(.missingContext))
        #expect(evaluate([rule()], context: context(age: 11, stableDuration: 20)) == .noChange(.staleContext))
        #expect(evaluate([rule()], context: context(age: -1)) == .noChange(.staleContext))
        #expect(evaluate([rule()], context: context(generation: 0)) == .noChange(.invalidContext))
        #expect(evaluate([rule()], context: context(age: 2, stableDuration: 1)) == .noChange(.invalidContext))
    }

    @Test("An unknown higher-priority rule cannot elect a lower-priority rule")
    func unknownConflict() {
        let foreground = ContextualLayoutRule(targetLayoutID: secondLayout, priority: 1,
                                              condition: .foregroundBundle("com.example.editor"))
        #expect(evaluate([rule(), foreground], context: context(foreground: nil)) == .noChange(.missingContext))
    }

    @Test("Disabled and nonmatching rules do nothing, and matching current layout is idempotent")
    func noAction() {
        let disabled = ContextualLayoutRule(targetLayoutID: firstLayout, isEnabled: false, condition: .powerSource(.battery))
        #expect(evaluate([disabled]) == .noChange(.noEnabledRules))
        #expect(evaluate([]) == .noChange(.noEnabledRules))
        #expect(evaluate([rule(.powerSource(.external))]) == .noChange(.noMatchingRule))
        #expect(evaluate([rule()], current: firstLayout) == .noChange(.alreadyApplied))
        #expect(evaluate([rule(.batteryBelow(20))]) == .noChange(.noMatchingRule))
        #expect(evaluate([rule(.batteryBelow(25))], context: context(power: .external, battery: nil))
            == .noChange(.noMatchingRule))
    }

    @Test("Invalid thresholds, identities, priorities and duplicate rules fail closed")
    func invalidRules() {
        for condition in [ContextualLayoutRule.Condition.batteryBelow(0), .batteryBelow(101),
                          .foregroundBundle("com..editor"), .foregroundBundle("com.example.editor\n"),
                          .foregroundBundle(String(repeating: "a", count: 256) + ".editor")]
        {
            #expect(evaluate([rule(condition)]) == .noChange(.invalidRules))
        }
        #expect(evaluate([ContextualLayoutRule(targetLayoutID: firstLayout, priority: -1, condition: .batteryBelow(25))])
            == .noChange(.invalidRules))
        let duplicate = rule()
        #expect(evaluate([duplicate, duplicate]) == .noChange(.invalidRules))
        #expect(evaluate((0 ..< 65).map { _ in rule() }) == .noChange(.invalidRules))
        #expect(evaluate([ContextualLayoutRule(targetLayoutID: UUID(), condition: .powerSource(.battery))])
            == .noChange(.targetLayoutMissing))
        #expect(evaluate([rule()], context: context(battery: -1)) == .noChange(.invalidContext))
    }

    @Test("Flapping inputs must settle before proposal, with no implicit revert when a match ends")
    func flapping() {
        let lowBattery = rule(.batteryBelow(25))
        for duration in [0.0, 0.1, 1.0, 2.9] {
            #expect(evaluate([lowBattery], context: context(stableDuration: duration)) == .deferred(.contextUnstable))
        }
        #expect(target(evaluate([lowBattery], context: context(stableDuration: 3))) == firstLayout)
        #expect(evaluate([lowBattery], context: context(battery: 25, stableDuration: 3), current: firstLayout)
            == .noChange(.noMatchingRule))
    }

    @Test("Models round-trip through Codable and decoded invalid rules remain rejected")
    func codable() throws {
        let rules = ContextualLayoutRuleSet(rules: [rule()])
        #expect(try JSONDecoder().decode(ContextualLayoutRuleSet.self, from: JSONEncoder().encode(rules)) == rules)
        let input = context()
        #expect(try JSONDecoder().decode(ContextualLayoutContext.self, from: JSONEncoder().encode(input)) == input)
        let invalid = ContextualLayoutRuleSet(rules: [rule(.batteryBelow(101))])
        let decoded = try JSONDecoder().decode(ContextualLayoutRuleSet.self, from: JSONEncoder().encode(invalid))
        #expect(!decoded.isValid)
    }

    private func rule(_ condition: ContextualLayoutRule.Condition = .powerSource(.battery)) -> ContextualLayoutRule {
        ContextualLayoutRule(targetLayoutID: firstLayout, condition: condition)
    }

    private func target(_ result: ContextualLayoutEvaluation) -> UUID? {
        guard case let .proposal(proposal) = result else { return nil }
        return proposal.targetLayoutID
    }

    private func evaluate(
        _ rules: [ContextualLayoutRule], context supplied: ContextualLayoutContext? = nil, current: UUID? = nil
    ) -> ContextualLayoutEvaluation {
        ContextualLayoutRuleEvaluator.evaluate(
            ContextualLayoutRuleSet(rules: rules), context: supplied ?? context(),
            availableLayoutIDs: [firstLayout, secondLayout], currentLayoutID: current, now: now
        )
    }

    private func context(
        foreground: String? = "com.example.editor", power: LayoutRulePowerSource? = .battery, battery: Int? = 20,
        focus: Bool? = false, manual: Bool = false, interacting: Bool = false, mutating: Bool = false,
        recovering: Bool = false, age: TimeInterval = 0, stableDuration: TimeInterval = 5, generation: UInt64 = 7
    ) -> ContextualLayoutContext {
        ContextualLayoutContext(
            generation: generation, capturedAt: now.addingTimeInterval(-age),
            stableSince: now.addingTimeInterval(-stableDuration), foregroundBundleID: foreground,
            powerSource: power, batteryPercent: battery, nativeFocusIsActive: focus,
            manualOverrideIsActive: manual, interactionIsActive: interacting, mutationIsActive: mutating,
            recoveryIsPending: recovering
        )
    }
}
