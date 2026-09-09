//
//  AboutSettingsPane.swift
//  Barline
//

import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var updatesManager: UpdatesManager
    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var lastUpdateCheckString: String {
        if let date = updatesManager.lastUpdateCheckDate {
            date.formatted(date: .abbreviated, time: .standard)
        } else {
            "Never"
        }
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            contentForm(cornerStyle: .continuous)
        } else {
            contentForm(cornerStyle: .circular)
        }
    }

    private func contentForm(cornerStyle: RoundedCornerStyle) -> some View {
        BarlineForm(spacing: 0) {
            mainContent(containerShape: RoundedRectangle(cornerRadius: 20, style: cornerStyle))
            Spacer(minLength: 10)
            bottomBar(containerShape: Capsule(style: cornerStyle))
        }
    }

    private func mainContent(containerShape: some InsettableShape) -> some View {
        BarlineSection(spacing: 0, options: .plain) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            if UpdatesManager.isEnabled {
                Spacer(minLength: 0)
                    .frame(maxHeight: 20)

                updatesSection
                    .layoutPriority(1)
            }
        }
        .padding(.top, 5)
        .padding([.horizontal, .bottom], 30)
        .frame(maxHeight: 500)
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
    }

    private var appIconAndCopyrightSection: some View {
        BarlineSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230)
                }

                VStack(alignment: .leading) {
                    Text("Barline")
                        .font(.system(size: 80))
                        .foregroundStyle(.primary)

                    Text("Version \(Constants.versionString)")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.67))
                }
                .fontWeight(.medium)
            }
        }
    }

    private var updatesSection: some View {
        BarlineSection(options: .hasDividers) {
            automaticallyCheckForUpdates
            automaticallyDownloadUpdates
            if updatesManager.canCheckForUpdates {
                checkForUpdates
            }
        }
        .frame(maxWidth: 600)
    }

    private var automaticallyCheckForUpdates: some View {
        Toggle(
            "Automatically check for updates",
            isOn: $updatesManager.automaticallyChecksForUpdates
        )
    }

    private var automaticallyDownloadUpdates: some View {
        Toggle(
            "Automatically download updates",
            isOn: $updatesManager.automaticallyDownloadsUpdates
        )
    }

    private var checkForUpdates: some View {
        HStack {
            Button("Check for Updates") {
                updatesManager.checkForUpdates()
            }
            Spacer()
            Text("Last checked: \(lastUpdateCheckString)")
                .font(.caption)
        }
    }

    private func bottomBar(containerShape: some InsettableShape) -> some View {
        HStack {
            Button("Quit Barline") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("Acknowledgements") {
                NSWorkspace.shared.open(acknowledgementsURL)
            }
            Link("Source", destination: URL(string: "https://github.com/Mabry-Ventures/mv-barline")!)
            Link("Report a Problem", destination: URL(string: "https://github.com/Mabry-Ventures/mv-barline/issues")!)
            if let supportURL = Constants.supportURL {
                Link("Support Barline", destination: supportURL)
                    .help("Optional support for development. Every feature is already included.")
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        ContainerRelativeShape()
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
