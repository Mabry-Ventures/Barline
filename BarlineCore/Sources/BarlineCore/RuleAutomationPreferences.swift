import Foundation

public struct RuleAutomationPreferences: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var isEnabled = false
    public var isPaused = false
    public var rules: [ContextualLayoutRule] = []

    public init() {}

    public func validated() throws -> Self {
        guard schemaVersion == 1, ContextualLayoutRuleSet(rules: rules).isValid else {
            throw ValidationFailure.invalid
        }
        return self
    }

    public enum ValidationFailure: Error { case invalid }
}
