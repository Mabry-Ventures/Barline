//
//  ProfilesSettingsPane.swift
//  Barline
//

import SwiftUI

struct ProfilesSettingsPane: View {
    @ObservedObject var manager: ProfileManager
    @State private var profileName = "Work"

    var body: some View {
        Form {
            Section("Saved Profiles") {
                if manager.profiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "person.crop.rectangle.stack",
                        description: Text("Capture the current menu bar layout to create one.")
                    )
                } else {
                    ForEach(manager.profiles) { profile in
                        HStack {
                            Label(profile.name, systemImage: profile.symbol ?? "menubar.rectangle")
                            Spacer()
                            if manager.activeProfileID == profile.id {
                                Text("Active").foregroundStyle(.secondary)
                            }
                            Button("Apply") { Task { await manager.activate(profile) } }
                                .accessibilityLabel("Apply \(profile.name) profile")
                            Button(role: .destructive) { Task { await manager.delete(profile) } } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(profile.name) profile")
                        }
                    }
                }
            }

            Section("Create") {
                TextField("Profile name", text: $profileName)
                HStack {
                    Button("Capture Current Layout") {
                        Task { await manager.captureCurrentProfile(named: profileName) }
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Create Presentation Profile") {
                        Task { await manager.createPresentationProfile() }
                    }
                }
            }

            Section("Automation") {
                Text("Shortcuts and Focus pass only stable profile identifiers through the App Intents extension. Barline validates and applies the profile transactionally in the app process.")
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = manager.statusMessage {
                Section { Text(statusMessage).accessibilityIdentifier("profile-status") }
            }
        }
        .formStyle(.grouped)
        .disabled(manager.isBusy)
    }
}
