//
//  WelcomeFlowTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

@Suite("First-run walkthrough")
struct WelcomeFlowTests {
    @Test("A fresh install presents the walkthrough at launch")
    func freshInstallPresents() {
        #expect(
            WelcomeFlow.shouldPresentAtLaunch(
                isEligible: true,
                hadPreferencesBeforeLaunch: false,
                isCompleted: false,
                savedStep: nil
            )
        )
    }

    @Test("Users upgrading with existing preferences are not interrupted")
    func upgradeDoesNotPresent() {
        #expect(
            !WelcomeFlow.shouldPresentAtLaunch(
                isEligible: true,
                hadPreferencesBeforeLaunch: true,
                isCompleted: false,
                savedStep: nil
            )
        )
    }

    @Test("A walkthrough interrupted by a relaunch resumes")
    func interruptedWalkthroughResumes() {
        for step in [WelcomeStep.welcome, .accessibility, .screenRecording, .barSetup] {
            #expect(
                WelcomeFlow.shouldPresentAtLaunch(
                    isEligible: true,
                    hadPreferencesBeforeLaunch: true,
                    isCompleted: false,
                    savedStep: step
                )
            )
            #expect(WelcomeFlow.openingStep(savedStep: step) == step)
        }
    }

    @Test("Completed, skipped, or closed walkthroughs never reappear on their own")
    func completedDoesNotPresent() {
        for savedStep in [nil, WelcomeStep.screenRecording, .done] {
            for hadPreferences in [false, true] {
                #expect(
                    !WelcomeFlow.shouldPresentAtLaunch(
                        isEligible: true,
                        hadPreferencesBeforeLaunch: hadPreferences,
                        isCompleted: true,
                        savedStep: savedStep
                    )
                )
            }
        }
    }

    @Test("Development builds never open the walkthrough on launch")
    func ineligibleBuildsDoNotPresent() {
        #expect(
            !WelcomeFlow.shouldPresentAtLaunch(
                isEligible: false,
                hadPreferencesBeforeLaunch: false,
                isCompleted: false,
                savedStep: .accessibility
            )
        )
    }

    @Test("A saved done step does not resume and opens at the beginning")
    func doneStepIsNotResumed() {
        #expect(
            WelcomeFlow.shouldPresentAtLaunch(
                isEligible: true,
                hadPreferencesBeforeLaunch: true,
                isCompleted: false,
                savedStep: .done
            ) == false
        )
        #expect(WelcomeFlow.openingStep(savedStep: .done) == .welcome)
        #expect(WelcomeFlow.openingStep(savedStep: nil) == .welcome)
    }

    @Test("Steps run welcome, accessibility, screen recording, bar setup, done")
    func stepOrder() {
        #expect(WelcomeFlow.step(after: .welcome) == .accessibility)
        #expect(WelcomeFlow.step(after: .accessibility) == .screenRecording)
        #expect(WelcomeFlow.step(after: .screenRecording) == .barSetup)
        #expect(WelcomeFlow.step(after: .barSetup) == .done)
        #expect(WelcomeFlow.step(after: .done) == .done)

        #expect(WelcomeFlow.step(before: .welcome) == nil)
        #expect(WelcomeFlow.step(before: .accessibility) == .welcome)
        #expect(WelcomeFlow.step(before: .barSetup) == .screenRecording)
        #expect(WelcomeFlow.step(before: .done) == nil)
    }

    @Test("Bar setup notices follow the layout editor's own precedence")
    func barSetupNotices() {
        #expect(
            WelcomeFlow.barSetupNotice(hasAccessibility: true, menuBarAutoHides: false, hasScreenRecording: true)
                == .ready
        )
        #expect(
            WelcomeFlow.barSetupNotice(hasAccessibility: false, menuBarAutoHides: true, hasScreenRecording: false)
                == .needsAccessibility
        )
        #expect(
            WelcomeFlow.barSetupNotice(hasAccessibility: true, menuBarAutoHides: true, hasScreenRecording: false)
                == .menuBarAutoHides
        )
        #expect(
            WelcomeFlow.barSetupNotice(hasAccessibility: true, menuBarAutoHides: false, hasScreenRecording: false)
                == .needsScreenRecording
        )
    }
}
