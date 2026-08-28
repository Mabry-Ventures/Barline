import AppKit
import SwiftUI

@main
struct BarlineFixtureApp: App {
    private let mode = ProcessInfo.processInfo.environment["BARLINE_FIXTURE_MODE"] ?? "default"
    @StateObject private var statusItems = FixtureStatusItemController()

    var body: some Scene {
        WindowGroup("Barline Fixture") {
            FixtureView(mode: mode)
                .environmentObject(statusItems)
        }
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
