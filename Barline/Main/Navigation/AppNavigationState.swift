//
//  AppNavigationState.swift
//  Barline
//

import Combine

/// The model for app-wide navigation.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var isAppFrontmost = false
    @Published var isSettingsPresented = false
    @Published var isBarlineShelfPresented = false
    @Published var isSearchPresented = false
    @Published var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general
}
