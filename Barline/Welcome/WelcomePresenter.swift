//
//  WelcomePresenter.swift
//  Barline
//

import BarlineCore
import OSLog

/// Opens the first-run walkthrough at launch or when the user asks for it.
@MainActor
enum WelcomePresenter {
    private static let logger = Logger(category: "Welcome")

    /// Presents the walkthrough on a fresh install, or resumes one that a
    /// relaunch interrupted. Call after the move-to-Applications check, so any
    /// permission granted here attaches to where Barline keeps running.
    static func presentAtLaunchIfNeeded(appState: AppState, isFreshInstall: Bool) {
        let model = appState.welcome
        let savedStep = model.savedStep
        if let forcedStep {
            present(appState: appState, at: forcedStep, persistingProgress: false)
            return
        }
        guard
            WelcomeFlow.shouldPresentAtLaunch(
                isEligible: isEligibleBuild,
                isFreshInstall: isFreshInstall,
                isCompleted: model.isCompleted,
                savedStep: savedStep
            )
        else {
            return
        }
        logger.info("Presenting the first-run walkthrough")
        present(appState: appState, at: WelcomeFlow.openingStep(savedStep: savedStep), persistingProgress: true)
    }

    /// Opens the walkthrough from the beginning at the user's request.
    static func showAgain(appState: AppState) {
        appState.welcome.replay()
        appState.activate(withPolicy: .regular)
        appState.openWindow(.welcome)
    }

    private static func present(appState: AppState, at step: WelcomeStep, persistingProgress: Bool) {
        appState.welcome.begin(at: step, persistingProgress: persistingProgress)
        appState.activate(withPolicy: .regular)
        appState.openWindow(.welcome)
    }

    /// Only copies distributed to users are eligible. Development builds and
    /// locally built Release products, including gate lanes that launch a Release
    /// build from build products, must never open the walkthrough on their own.
    private static var isEligibleBuild: Bool {
        #if DEBUG
            false
        #else
            DistributionIdentity.isDeveloperIDSigned
        #endif
    }

    /// Development-only manual verification: `--barline-welcome-step <step>`
    /// opens the walkthrough at that step without recording any progress.
    private static var forcedStep: WelcomeStep? {
        #if DEBUG
            let arguments = CommandLine.arguments
            guard
                let index = arguments.firstIndex(of: "--barline-welcome-step"),
                arguments.indices.contains(index + 1)
            else {
                return nil
            }
            return WelcomeStep(rawValue: arguments[index + 1])
        #else
            nil
        #endif
    }
}
