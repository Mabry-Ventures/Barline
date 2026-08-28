//
//  GeneralSettingsPane.swift
//  Barline
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: GeneralSettings
    @State private var isImportingCustomBarlineIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?
    @State private var isApplyingItemSpacingOffset = false
    @State private var tempItemSpacingOffset: CGFloat = 0

    private var itemSpacingOffsetKey: LocalizedStringKey {
        switch tempItemSpacingOffset {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: LocalizedStringKey(tempItemSpacingOffset.formatted())
        }
    }

    private var rehideIntervalKey: LocalizedStringKey {
        let formatted = settings.rehideInterval.formatted()
        if settings.rehideInterval == 1 {
            return LocalizedStringKey(formatted + " second")
        } else {
            return LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        BarlineForm {
            BarlineSection {
                appOptions
            }
            BarlineSection {
                barlineIconOptions
            }
            BarlineSection {
                barlineShelfOptions
            }
            BarlineSection {
                showOptions
            }
            BarlineSection {
                rehideOptions
            }
            BarlineSection {
                spacingOptions
            }
        }
    }

    // MARK: App Options

    @ViewBuilder
    private var appOptions: some View {
        LaunchAtLogin.Toggle()
    }

    // MARK: Barline Icon Options

    @ViewBuilder
    private var barlineIconOptions: some View {
        showBarlineIcon
        if settings.showBarlineIcon {
            barlineIconPicker
        }
    }

    @ViewBuilder
    private var showBarlineIcon: some View {
        Toggle("Show Barline icon", isOn: $settings.showBarlineIcon)
            .annotation("Click to show hidden menu bar items. Right-click to access Barline's settings.")
    }

    @ViewBuilder
    private var barlineIconPicker: some View {
        let labelKey = LocalizedStringKey("Barline icon")

        BarlineMenu(labelKey) {
            Picker(labelKey, selection: $settings.barlineIcon) {
                ForEach(ControlItemImageSet.userSelectableBarlineIcons) { imageSet in
                    Button {
                        settings.barlineIcon = imageSet
                    } label: {
                        barlineIconMenuItem(for: imageSet)
                    }
                    .tag(imageSet)
                }
                if let lastCustomBarlineIcon = settings.lastCustomBarlineIcon {
                    Button {
                        settings.barlineIcon = lastCustomBarlineIcon
                    } label: {
                        barlineIconMenuItem(for: lastCustomBarlineIcon)
                    }
                    .tag(lastCustomBarlineIcon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button("Choose image…") {
                isImportingCustomBarlineIcon = true
            }
        } title: {
            barlineIconMenuItem(for: settings.barlineIcon)
        }
        .annotation("Choose a custom icon to show in the menu bar.")
        .fileImporter(
            isPresented: $isImportingCustomBarlineIcon,
            allowedContentTypes: [.image]
        ) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    settings.barlineIcon = ControlItemImageSet(name: .custom, image: .data(data))
                }
            } catch {
                presentedError = LocalizedErrorWrapper(error)
                isPresentingError = true
            }
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }

        if case .custom = settings.barlineIcon.name {
            Toggle("Custom icon uses dynamic appearance", isOn: $settings.customBarlineIconIsTemplate)
                .annotation {
                    Text(
                        """
                        Display the icon as a monochrome image that dynamically adjusts to match \
                        the menu bar's appearance. This setting removes all color from the icon, \
                        but ensures consistent rendering with both light and dark backgrounds.
                        """
                    )
                    .padding(.trailing, 50)
                }
        }
    }

    @ViewBuilder
    private func barlineIconMenuItem(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.rawValue)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: appState) {
                switch imageSet.name {
                case .custom:
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(Image(nsImage: nsImage), in: context.clipBoundingRect)
                    }
                default:
                    Image(nsImage: nsImage)
                }
            }
        }
    }

    // MARK: Barline Bar Options

    @ViewBuilder
    private var barlineShelfOptions: some View {
        useBarlineShelf
        if settings.useBarlineShelf {
            barlineShelfLocationPicker
        }
    }

    @ViewBuilder
    private var useBarlineShelf: some View {
        Toggle("Use Barline Bar", isOn: $settings.useBarlineShelf)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
    }

    @ViewBuilder
    private var barlineShelfLocationPicker: some View {
        BarlinePicker("Location", selection: $settings.barlineShelfLocation) {
            ForEach(BarlineShelfLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        }
        .annotation {
            switch settings.barlineShelfLocation {
            case .dynamic:
                Text("The Barline Bar's location changes based on context.")
            case .mousePointer:
                Text("The Barline Bar is centered below the mouse pointer.")
            case .barlineIcon:
                Text("The Barline Bar is centered below the Barline icon.")
            }
        }
    }

    // MARK: Show Options

    @ViewBuilder
    private var showOptions: some View {
        Toggle("Show on click", isOn: $settings.showOnClick)
            .annotation("Click inside an empty area of the menu bar to show hidden menu bar items.")
        Toggle("Show on hover", isOn: $settings.showOnHover)
            .annotation("Hover over an empty area of the menu bar to show hidden menu bar items.")
        Toggle("Show on scroll", isOn: $settings.showOnScroll)
            .annotation("Scroll or swipe in the menu bar to show hidden menu bar items.")
    }

    // MARK: Rehide Options

    @ViewBuilder
    private var rehideOptions: some View {
        autoRehide
        if settings.autoRehide {
            rehideStrategyPicker
        }
    }

    @ViewBuilder
    private var autoRehide: some View {
        Toggle("Automatically rehide", isOn: $settings.autoRehide)
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
        VStack {
            BarlinePicker("Strategy", selection: $settings.rehideStrategy) {
                ForEach(RehideStrategy.allCases) { strategy in
                    Text(strategy.localized).tag(strategy)
                }
            }
            .annotation {
                switch settings.rehideStrategy {
                case .smart:
                    Text("Menu bar items are rehidden using a smart algorithm.")
                case .timed:
                    Text("Menu bar items are rehidden after a fixed amount of time.")
                case .focusedApp:
                    Text("Menu bar items are rehidden when the focused app changes.")
                }
            }

            if case .timed = settings.rehideStrategy {
                BarlineSlider(
                    rehideIntervalKey,
                    value: $settings.rehideInterval,
                    in: 0...30,
                    step: 1
                )
            }
        }
    }

    // MARK: Spacing Options

    @ViewBuilder
    private var spacingOptions: some View {
        LabeledContent {
            BarlineSlider(
                itemSpacingOffsetKey,
                value: $tempItemSpacingOffset,
                in: -16...16,
                step: 2
            )
            .disabled(isApplyingItemSpacingOffset)
        } label: {
            LabeledContent {
                Button("Apply") {
                    applyTempItemSpacingOffset()
                }
                .help("Apply the current spacing")
                .disabled(isApplyingItemSpacingOffset || tempItemSpacingOffset == settings.itemSpacingOffset)

                if isApplyingItemSpacingOffset {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .frame(width: 15, height: 15)
                } else {
                    Button {
                        tempItemSpacingOffset = 0
                        applyTempItemSpacingOffset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to the default spacing")
                    .disabled(isApplyingItemSpacingOffset || settings.itemSpacingOffset == 0)
                }
            } label: {
                HStack {
                    Text("Menu bar item spacing")
                    BetaBadge()
                }
            }
        }
        .annotation(
            "Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.",
            spacing: 2
        )
        .annotation(spacing: 10) {
            CalloutBox(
                "Note: You may need to log out and back in for this setting to apply properly.",
                systemImage: "exclamationmark.circle"
            )
        }
        .onAppear {
            tempItemSpacingOffset = settings.itemSpacingOffset
        }
    }

    private func applyTempItemSpacingOffset() {
        isApplyingItemSpacingOffset = true
        settings.itemSpacingOffset = tempItemSpacingOffset
        Task {
            do {
                try await appState.spacingManager.applyOffset()
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
            isApplyingItemSpacingOffset = false
        }
    }
}
