//
//  WelcomeFlow.swift
//  Barline
//

/// The steps of Barline's first-run walkthrough, in order.
public enum WelcomeStep: String, CaseIterable, Sendable {
    case welcome
    case accessibility
    case screenRecording
    case barSetup
    case done
}

/// Decisions for the first-run walkthrough. The walkthrough explains
/// permissions and requests each one only when the user clicks to grant it.
/// Every step can be skipped, and nothing it shows blocks using the app.
public enum WelcomeFlow {
    /// Whether to present the walkthrough when Barline launches.
    ///
    /// - Parameters:
    ///   - isEligible: `false` for development and test builds, which must never
    ///     open a window on their own.
    ///   - hadPreferencesBeforeLaunch: Barline's preferences domain held values
    ///     before this launch wrote anything. Users upgrading from an earlier
    ///     version already set Barline up, so they are not shown the walkthrough.
    ///   - isCompleted: The user finished, skipped, or closed the walkthrough.
    ///   - savedStep: The step recorded when the walkthrough was last left open.
    public static func shouldPresentAtLaunch(
        isEligible: Bool,
        hadPreferencesBeforeLaunch: Bool,
        isCompleted: Bool,
        savedStep: WelcomeStep?
    ) -> Bool {
        guard isEligible, !isCompleted else {
            return false
        }
        // A walkthrough interrupted by a relaunch, such as macOS's Quit &
        // Reopen after a Screen Recording grant, resumes even though its first
        // launch already wrote preferences.
        if let savedStep, savedStep != .done {
            return true
        }
        return !hadPreferencesBeforeLaunch
    }

    /// The step to show when the walkthrough opens.
    public static func openingStep(savedStep: WelcomeStep?) -> WelcomeStep {
        guard let savedStep, savedStep != .done else {
            return .welcome
        }
        return savedStep
    }

    public static func step(after step: WelcomeStep) -> WelcomeStep {
        let steps = WelcomeStep.allCases
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else {
            return .done
        }
        return steps[index + 1]
    }

    public static func step(before step: WelcomeStep) -> WelcomeStep? {
        let steps = WelcomeStep.allCases
        guard let index = steps.firstIndex(of: step), index > 0, step != .done else {
            return nil
        }
        return steps[index - 1]
    }

    /// What the bar setup step must tell the user before they open the layout
    /// editor. Mirrors the layout editor's own checks, in the same order, so the
    /// walkthrough never promises something the editor then refuses.
    public enum BarSetupNotice: Equatable, Sendable {
        case ready
        case needsAccessibility
        case menuBarAutoHides
        case needsScreenRecording
    }

    public static func barSetupNotice(
        hasAccessibility: Bool,
        menuBarAutoHides: Bool,
        hasScreenRecording: Bool
    ) -> BarSetupNotice {
        if !hasAccessibility {
            return .needsAccessibility
        }
        if menuBarAutoHides {
            return .menuBarAutoHides
        }
        if !hasScreenRecording {
            return .needsScreenRecording
        }
        return .ready
    }
}
