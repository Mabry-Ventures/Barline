//
//  GeneralSettings.swift
//  Barline
//

import Combine
import OSLog
import SwiftUI

// MARK: - GeneralSettings

/// Model for the app's General settings.
@MainActor
final class GeneralSettings: ObservableObject {
    /// A Boolean value that indicates whether the Barline icon
    /// should be shown.
    @Published var showBarlineIcon = true

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var barlineIcon: ControlItemImageSet = .defaultBarlineIcon

    /// The last user-selected custom Barline icon.
    @Published var lastCustomBarlineIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom Barline icons
    /// should be rendered as template images.
    @Published var customBarlineIconIsTemplate = false

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    @Published var useBarlineShelf = false

    /// The location where the Barline Bar appears.
    @Published var barlineShelfLocation: BarlineShelfLocation = .dynamic

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    @Published var showOnClick = true

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = false

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    @Published var showOnScroll = true

    /// The offset to apply to the menu bar item spacing and padding.
    @Published var itemSpacingOffset: Double = 0

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    @Published var autoRehide = true

    /// A strategy that determines how the auto-rehide feature works.
    @Published var rehideStrategy: RehideStrategy = .smart

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    @Published var rehideInterval: TimeInterval = 15

    /// Encoder for properties.
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showBarlineIcon, assign: &showBarlineIcon)
        Defaults.ifPresent(key: .customBarlineIconIsTemplate, assign: &customBarlineIconIsTemplate)
        Defaults.ifPresent(key: .useBarlineShelf, assign: &useBarlineShelf)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        Defaults.ifPresent(key: .itemSpacingOffset, assign: &itemSpacingOffset)
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval, assign: &rehideInterval)

        Defaults.ifPresent(key: .barlineShelfLocation) { rawValue in
            if let location = BarlineShelfLocation(rawValue: rawValue) {
                barlineShelfLocation = location
            }
        }
        Defaults.ifPresent(key: .rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }

        if let data = Defaults.data(forKey: .barlineIcon) {
            do {
                barlineIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                Logger.serialization.error("Error decoding Barline icon: \(error, privacy: .public)")
            }
            if case .custom = barlineIcon.name {
                lastCustomBarlineIcon = barlineIcon
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $showBarlineIcon
            .receive(on: DispatchQueue.main)
            .sink { showBarlineIcon in
                Defaults.set(showBarlineIcon, forKey: .showBarlineIcon)
            }
            .store(in: &c)

        $barlineIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] barlineIcon in
                guard let self else {
                    return
                }
                if case .custom = barlineIcon.name {
                    lastCustomBarlineIcon = barlineIcon
                }
                do {
                    let data = try encoder.encode(barlineIcon)
                    Defaults.set(data, forKey: .barlineIcon)
                } catch {
                    Logger.serialization.error("Error encoding Barline icon: \(error, privacy: .public)")
                }
            }
            .store(in: &c)

        $customBarlineIconIsTemplate
            .receive(on: DispatchQueue.main)
            .sink { isTemplate in
                Defaults.set(isTemplate, forKey: .customBarlineIconIsTemplate)
            }
            .store(in: &c)

        $useBarlineShelf
            .receive(on: DispatchQueue.main)
            .sink { useBarlineShelf in
                Defaults.set(useBarlineShelf, forKey: .useBarlineShelf)
            }
            .store(in: &c)

        $barlineShelfLocation
            .receive(on: DispatchQueue.main)
            .sink { location in
                Defaults.set(location.rawValue, forKey: .barlineShelfLocation)
            }
            .store(in: &c)

        $showOnClick
            .receive(on: DispatchQueue.main)
            .sink { showOnClick in
                Defaults.set(showOnClick, forKey: .showOnClick)
            }
            .store(in: &c)

        $showOnHover
            .receive(on: DispatchQueue.main)
            .sink { showOnHover in
                Defaults.set(showOnHover, forKey: .showOnHover)
            }
            .store(in: &c)

        $showOnScroll
            .receive(on: DispatchQueue.main)
            .sink { showOnScroll in
                Defaults.set(showOnScroll, forKey: .showOnScroll)
            }
            .store(in: &c)

        $itemSpacingOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] offset in
                Defaults.set(offset, forKey: .itemSpacingOffset)
                appState?.spacingManager.offset = Int(offset)
            }
            .store(in: &c)

        $autoRehide
            .receive(on: DispatchQueue.main)
            .sink { autoRehide in
                Defaults.set(autoRehide, forKey: .autoRehide)
            }
            .store(in: &c)

        $rehideStrategy
            .receive(on: DispatchQueue.main)
            .sink { strategy in
                Defaults.set(strategy.rawValue, forKey: .rehideStrategy)
            }
            .store(in: &c)

        $rehideInterval
            .receive(on: DispatchQueue.main)
            .sink { interval in
                Defaults.set(interval, forKey: .rehideInterval)
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: - RehideStrategy

/// A type that determines how the auto-rehide feature works.
enum RehideStrategy: Int, CaseIterable, Identifiable {
    /// Menu bar items are rehidden using a smart algorithm.
    case smart = 0
    /// Menu bar items are rehidden after a given time interval.
    case timed = 1
    /// Menu bar items are rehidden when the focused app changes.
    case focusedApp = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .smart: "Smart"
        case .timed: "Timed"
        case .focusedApp: "Focused app"
        }
    }
}
