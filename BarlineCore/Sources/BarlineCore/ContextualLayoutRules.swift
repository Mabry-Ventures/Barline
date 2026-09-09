import Foundation

public enum LayoutRulePowerSource: String, Codable, Equatable, Sendable {
    case battery
    case external
}

/// One local predicate per rule. Native Focus is intentionally not a rule
/// condition: the system Focus integration owns that higher-priority authority.
public struct ContextualLayoutRule: Codable, Equatable, Sendable {
    public enum Condition: Codable, Equatable, Sendable {
        case foregroundBundle(String)
        case powerSource(LayoutRulePowerSource)
        case batteryBelow(Int)
    }

    public let id: UUID
    public let targetLayoutID: UUID
    public let isEnabled: Bool
    public let priority: Int
    public let condition: Condition

    public init(
        id: UUID = UUID(), targetLayoutID: UUID, isEnabled: Bool = true,
        priority: Int = 0, condition: Condition
    ) {
        self.id = id
        self.targetLayoutID = targetLayoutID
        self.isEnabled = isEnabled
        self.priority = priority
        self.condition = condition
    }

    public var isValid: Bool {
        guard (0 ... 1000).contains(priority) else { return false }
        switch condition {
        case let .foregroundBundle(bundle): return Self.validBundle(bundle)
        case .powerSource: return true
        case let .batteryBelow(threshold): return (1 ... 100).contains(threshold)
        }
    }

    fileprivate static func validBundle(_ bundle: String) -> Bool {
        let components = bundle.split(separator: ".", omittingEmptySubsequences: false)
        return !bundle.isEmpty && bundle.utf8.count <= 255 && components.count > 1 &&
            components.allSatisfy { component in
                !component.isEmpty && component.utf8.allSatisfy {
                    (65 ... 90).contains($0) || (97 ... 122).contains($0) ||
                        (48 ... 57).contains($0) || $0 == 45 || $0 == 95
                }
            }
    }
}

/// Persisted array order is the explicit tie-breaker between equal priorities.
/// The enclosing decoder must bound input bytes before decoding this model.
public struct ContextualLayoutRuleSet: Codable, Equatable, Sendable {
    public let rules: [ContextualLayoutRule]

    public init(rules: [ContextualLayoutRule]) {
        self.rules = rules
    }

    public var isValid: Bool {
        rules.count <= 64 && Set(rules.map(\.id)).count == rules.count && rules.allSatisfy(\.isValid)
    }
}

/// One coherent observation, not independently cached values from unrelated
/// generations. The event adapter resets stableSince whenever any input or
/// authority/safety flag changes; evaluate performs no sampling or polling.
public struct ContextualLayoutContext: Codable, Equatable, Sendable {
    public let generation: UInt64
    public let capturedAt: Date
    public let stableSince: Date
    public let foregroundBundleID: String?
    public let powerSource: LayoutRulePowerSource?
    public let batteryPercent: Int?
    public let nativeFocusIsActive: Bool?
    public let manualOverrideIsActive: Bool
    public let interactionIsActive: Bool
    public let mutationIsActive: Bool
    public let recoveryIsPending: Bool

    public init(
        generation: UInt64, capturedAt: Date, stableSince: Date,
        foregroundBundleID: String? = nil, powerSource: LayoutRulePowerSource? = nil,
        batteryPercent: Int? = nil, nativeFocusIsActive: Bool?, manualOverrideIsActive: Bool,
        interactionIsActive: Bool, mutationIsActive: Bool, recoveryIsPending: Bool
    ) {
        self.generation = generation
        self.capturedAt = capturedAt
        self.stableSince = stableSince
        self.foregroundBundleID = foregroundBundleID
        self.powerSource = powerSource
        self.batteryPercent = batteryPercent
        self.nativeFocusIsActive = nativeFocusIsActive
        self.manualOverrideIsActive = manualOverrideIsActive
        self.interactionIsActive = interactionIsActive
        self.mutationIsActive = mutationIsActive
        self.recoveryIsPending = recoveryIsPending
    }

    fileprivate var isValid: Bool {
        generation > 0 && capturedAt.timeIntervalSinceReferenceDate.isFinite &&
            stableSince.timeIntervalSinceReferenceDate.isFinite && stableSince <= capturedAt &&
            foregroundBundleID.map(ContextualLayoutRule.validBundle) != false &&
            batteryPercent.map { (0 ... 100).contains($0) } != false
    }
}

public enum ContextualLayoutRuleReason: String, Codable, Equatable, Sendable {
    case invalidRules
    case invalidContext
    case staleContext
    case missingContext
    case nativeFocusActive
    case manualOverrideActive
    case interactionActive
    case mutationActive
    case recoveryPending
    case contextUnstable
    case noEnabledRules
    case noMatchingRule
    case targetLayoutMissing
    case alreadyApplied
    case foregroundBundleMatched
    case powerSourceMatched
    case lowBatteryMatched
}

public struct ContextualLayoutProposal: Equatable, Sendable {
    public let contextGeneration: UInt64
    public let ruleID: UUID
    public let targetLayoutID: UUID
    public let reason: ContextualLayoutRuleReason
}

public enum ContextualLayoutEvaluation: Equatable, Sendable {
    case noChange(ContextualLayoutRuleReason)
    case deferred(ContextualLayoutRuleReason)
    case proposal(ContextualLayoutProposal)
}

/// Pure proposal generation only. A proposal is NOT authorization to mutate.
/// Before committing, revalidate context/rule/layout generations and all safety
/// flags inside the existing transactional coordinator's exclusive lease.
public enum ContextualLayoutRuleEvaluator {
    public static let maximumContextAge: TimeInterval = 10
    public static let minimumStableDuration: TimeInterval = 3

    public static func evaluate(
        _ ruleSet: ContextualLayoutRuleSet, context: ContextualLayoutContext,
        availableLayoutIDs: Set<UUID>, currentLayoutID: UUID?, now: Date
    ) -> ContextualLayoutEvaluation {
        guard ruleSet.isValid else { return .noChange(.invalidRules) }
        guard context.isValid, now.timeIntervalSinceReferenceDate.isFinite else { return .noChange(.invalidContext) }
        let age = now.timeIntervalSince(context.capturedAt)
        guard age >= 0, age <= maximumContextAge else { return .noChange(.staleContext) }
        guard let nativeFocusIsActive = context.nativeFocusIsActive else { return .noChange(.missingContext) }
        if nativeFocusIsActive {
            return .deferred(.nativeFocusActive)
        }
        if context.manualOverrideIsActive {
            return .deferred(.manualOverrideActive)
        }
        if context.interactionIsActive {
            return .deferred(.interactionActive)
        }
        if context.mutationIsActive {
            return .deferred(.mutationActive)
        }
        if context.recoveryIsPending {
            return .deferred(.recoveryPending)
        }
        guard now.timeIntervalSince(context.stableSince) >= minimumStableDuration else {
            return .deferred(.contextUnstable)
        }

        let ordered = ruleSet.rules.enumerated().filter(\.element.isEnabled).sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
        }
        guard !ordered.isEmpty else { return .noChange(.noEnabledRules) }
        for (_, rule) in ordered {
            // Unknown higher-priority context must not accidentally elect a
            // lower-priority rule which a fresh observation would override.
            guard let reason = match(rule.condition, context: context) else { return .noChange(.missingContext) }
            guard reason != .noMatchingRule else { continue }
            guard availableLayoutIDs.contains(rule.targetLayoutID) else { return .noChange(.targetLayoutMissing) }
            guard rule.targetLayoutID != currentLayoutID else { return .noChange(.alreadyApplied) }
            return .proposal(ContextualLayoutProposal(
                contextGeneration: context.generation, ruleID: rule.id, targetLayoutID: rule.targetLayoutID, reason: reason
            ))
        }
        // No implicit default/undo on context loss or when a predicate ceases
        // matching. That avoids oscillation and preserves the user's layout.
        return .noChange(.noMatchingRule)
    }

    private static func match(
        _ condition: ContextualLayoutRule.Condition, context: ContextualLayoutContext
    ) -> ContextualLayoutRuleReason? {
        switch condition {
        case let .foregroundBundle(bundle):
            guard let foreground = context.foregroundBundleID else { return nil }
            return foreground.caseInsensitiveCompare(bundle) == .orderedSame ? .foregroundBundleMatched : .noMatchingRule
        case let .powerSource(expected):
            guard let power = context.powerSource else { return nil }
            return power == expected ? .powerSourceMatched : .noMatchingRule
        case let .batteryBelow(threshold):
            guard let power = context.powerSource else { return nil }
            guard power == .battery else { return .noMatchingRule }
            guard let percent = context.batteryPercent else { return nil }
            return percent < threshold ? .lowBatteryMatched : .noMatchingRule
        }
    }
}
