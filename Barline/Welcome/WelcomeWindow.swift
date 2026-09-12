//
//  WelcomeWindow.swift
//  Barline
//

import SwiftUI

struct WelcomeWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        BarlineWindow(id: .welcome) {
            WelcomeView(model: appState.welcome)
                .onWindowChange { window in
                    guard let window else {
                        return
                    }
                    // Only the walkthrough's own buttons end it. Quitting, such as
                    // macOS's Quit & Reopen after a Screen Recording grant, leaves
                    // progress in place so the walkthrough resumes.
                    window.standardWindowButton(.closeButton)?.isHidden = true
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .environmentObject(appState)
        .environmentObject(appState.permissions)
    }
}
