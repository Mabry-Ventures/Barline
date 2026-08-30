//
//  BarlineFixtureApp.swift
//  Barline
//

import AppKit
import SwiftUI

@main
struct BarlineFixtureApp: App {
    @NSApplicationDelegateAdaptor(BarlineFixtureAppDelegate.self) private var appDelegate
    private let mode = ProcessInfo.processInfo.environment["BARLINE_FIXTURE_MODE"] ?? "default"
    @StateObject private var statusItems = FixtureStatusItemController()

    var body: some Scene {
        WindowGroup("Barline Fixture") {
            FixtureView(mode: mode)
                .environmentObject(statusItems)
        }
    }
}

@MainActor
private final class BarlineFixtureAppDelegate: NSObject, NSApplicationDelegate {
    private var auditPanel: NSPanel?
    private var auditStatusItems: FixtureStatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        guard CommandLine.arguments.contains("--barline-fixture-accessibility-audit") else {
            return
        }
        let statusItems = FixtureStatusItemController()
        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 480, height: 220),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Barline Fixture Accessibility Audit"
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(
            rootView: FixtureView(mode: "accessibility-audit")
                .environmentObject(statusItems)
        )
        panel.orderFrontRegardless()
        auditStatusItems = statusItems
        auditPanel = panel
    }
}

private struct FixtureView: View {
    @EnvironmentObject var statusItems: FixtureStatusItemController
    let mode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Barline Fixture", systemImage: "menubar.rectangle")
                .font(.title2.bold())
                .accessibilityIdentifier("fixture-title")
            Text("Mode: \(mode)")
                .accessibilityIdentifier("fixture-mode")
            HStack {
                fixtureItem("Network", identifier: "fixture-network")
                fixtureItem("Battery", identifier: "fixture-battery")
                fixtureItem("Clock", identifier: "fixture-clock")
            }
            Text("Status item clicks: \(statusItems.activationCount)")
                .accessibilityIdentifier("fixture-activation-count")
            Button("Apply Presentation Profile") {}
                .accessibilityIdentifier("fixture-apply-profile")
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 220)
    }

    private func fixtureItem(_ title: String, identifier: String) -> some View {
        Text(title)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary, in: Capsule())
            .accessibilityIdentifier(identifier)
    }
}

@MainActor
private final class FixtureStatusItemController: NSObject, ObservableObject {
    @Published private(set) var activationCount = 0
    private var statusItems = [NSStatusItem]()

    override init() {
        super.init()
        let configured = ProcessInfo.processInfo.environment["BARLINE_FIXTURE_ITEMS"]?
            .split(separator: ",")
            .map(String.init) ?? ["Network", "Battery", "Clock"]
        for (index, title) in configured.enumerated() {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = "BarlineFixture.\(index).\(title)"
            statusItem.button?.title = title
            statusItem.button?.setAccessibilityIdentifier("barline-fixture-status-\(index)")
            statusItem.button?.target = self
            statusItem.button?.action = #selector(activateStatusItem)
            statusItems.append(statusItem)
        }
    }

    @objc private func activateStatusItem() {
        activationCount += 1
    }
}
