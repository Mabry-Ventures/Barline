//
//  WelcomeModel.swift
//  Barline
//

import BarlineCore
import Combine

/// Tracks the first-run walkthrough's current step and records progress, so a
/// relaunch such as macOS's Quit & Reopen resumes where the user left off.
@MainActor
final class WelcomeModel: ObservableObject {
    @Published private(set) var step: WelcomeStep = .welcome

    /// Development presentations must not write progress into the preferences
    /// domain the installed app shares, or that app would resume a walkthrough
    /// the user never started.
    private var persistsProgress = true

    /// The step recorded when the walkthrough was last left open.
    var savedStep: WelcomeStep? {
        Defaults.string(forKey: .welcomeStep).flatMap(WelcomeStep.init(rawValue:))
    }

    /// Whether the user finished, skipped, or closed the walkthrough.
    var isCompleted: Bool {
        Defaults.bool(forKey: .welcomeCompleted)
    }

    func begin(at step: WelcomeStep, persistingProgress: Bool = true) {
        persistsProgress = persistingProgress
        move(to: step)
    }

    /// Replays the walkthrough from the beginning. When persisting, clears
    /// completion so a replay interrupted by a relaunch resumes, as the
    /// walkthrough promises. Development builds replay without persisting.
    func replay(persistingProgress: Bool) {
        persistsProgress = persistingProgress
        if persistingProgress {
            Defaults.removeObject(forKey: .welcomeCompleted)
        }
        move(to: .welcome)
    }

    func advance() {
        move(to: WelcomeFlow.step(after: step))
    }

    func goBack() {
        guard let previous = WelcomeFlow.step(before: step) else {
            return
        }
        move(to: previous)
    }

    /// Ends the walkthrough. It does not reopen on its own afterward; Settings ›
    /// General can show it again.
    func finish() {
        guard persistsProgress else {
            return
        }
        Defaults.set(true, forKey: .welcomeCompleted)
        Defaults.removeObject(forKey: .welcomeStep)
        Defaults.removeObject(forKey: .welcomePending)
    }

    private func move(to newStep: WelcomeStep) {
        step = newStep
        guard persistsProgress else {
            return
        }
        if newStep == .done {
            finish()
        } else {
            Defaults.set(newStep.rawValue, forKey: .welcomeStep)
        }
    }
}
