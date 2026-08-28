//
//  ProfilesSettingsPane.swift
//  Barline
//

import BarlineCore
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: ProfileManager
    @State private var profileName = "Work"
    @State private var editedProfile: BarlineProfile?
    @State private var exportDocument: ProfileArchiveDocument?
    @State private var showsArchiveExporter = false
    @State private var showsArchiveImporter = false

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
                                .disabled(!appState.permissions.accessibility.hasPermission)
                            Button("Edit") { editedProfile = profile }
                                .accessibilityLabel("Edit \(profile.name) profile")
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
                    .disabled(!appState.permissions.accessibility.hasPermission)
                    Button("Create Presentation Profile") {
                        Task { await manager.createPresentationProfile() }
                    }
                    .disabled(!appState.permissions.accessibility.hasPermission)
                }
                if !appState.permissions.accessibility.hasPermission {
                    Text("Profile management remains available, but capturing or applying menu bar layouts requires Accessibility.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Import and Export") {
                HStack {
                    Button("Import from Ice…") {
                        Task { await manager.discoverIceImports() }
                    }
                    .disabled(!appState.permissions.accessibility.hasPermission)
                    Button("Import Archive…") {
                        showsArchiveImporter = true
                    }
                    Button("Export All Profiles…") {
                        Task {
                            guard let data = await manager.archiveData() else { return }
                            exportDocument = ProfileArchiveDocument(data: data)
                            showsArchiveExporter = true
                        }
                    }
                    .disabled(manager.profiles.isEmpty)
                }
                Text("Imports are validated and previewed before anything is saved. Existing profiles are never replaced without explicit approval.")
                    .foregroundStyle(.secondary)
            }

            if !manager.pendingIceImports.isEmpty {
                Section("Ice Import Preview") {
                    ForEach(manager.pendingIceImports, id: \.source) { preview in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(preview.profile.name, systemImage: "snowflake")
                                .font(.headline)
                            Text("Imports \(preview.importedComponents.count) supported setting groups from \(preview.source.displayName).")
                            if !preview.warnings.isEmpty {
                                Text("\(preview.warnings.count) unsupported or ambiguous setting\(preview.warnings.count == 1 ? "" : "s") will require manual review.")
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Import") {
                                    Task { await manager.commitIceImport(preview, replacingExisting: false) }
                                }
                                if manager.profiles.contains(where: { $0.id == preview.profile.id }) {
                                    Button("Replace Existing", role: .destructive) {
                                        Task { await manager.commitIceImport(preview, replacingExisting: true) }
                                    }
                                }
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) { manager.cancelIceImports() }
                }
            }

            if let preview = manager.pendingArchiveImport {
                Section("Import Preview") {
                    Text(preview.summary)
                    ForEach(preview.profiles) { profile in
                        HStack {
                            Label(profile.name, systemImage: profile.symbol ?? "menubar.rectangle")
                            Spacer()
                            if preview.conflictingProfileIDs.contains(profile.id) {
                                Text("Existing profile")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    HStack {
                        Button("Cancel", role: .cancel) {
                            manager.cancelArchiveImport()
                        }
                        Spacer()
                        if preview.hasConflicts {
                            Button("Import New Only") {
                                Task { await manager.commitArchiveImport(replacingExisting: false) }
                            }
                            Button("Replace Existing and Import", role: .destructive) {
                                Task { await manager.commitArchiveImport(replacingExisting: true) }
                            }
                        } else {
                            Button("Import Profiles") {
                                Task { await manager.commitArchiveImport(replacingExisting: false) }
                            }
                        }
                    }
                }
            }

            Section("Recovery") {
                HStack {
                    Button("Undo Layout Change") {
                        Task { await manager.undoLayoutChange() }
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    Button("Redo Layout Change") {
                        Task { await manager.redoLayoutChange() }
                    }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    Button("Restore Last-Known-Good Layout") {
                        Task { await manager.restoreLastKnownGoodLayout() }
                    }
                }
                .disabled(!appState.permissions.accessibility.hasPermission)
                Text("Undo and redo keep a bounded in-memory layout history. Last-known-good restore does not delete profiles or reset unrelated settings.")
                    .foregroundStyle(.secondary)
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
        .sheet(item: $editedProfile) { profile in
            ProfileEditorSheet(
                profile: profile,
                canResetFromWorkspace: appState.permissions.accessibility.hasPermission
            ) { name, symbol, groups, spacers in
                Task {
                    await manager.update(
                        profile,
                        name: name,
                        symbol: symbol,
                        groups: groups,
                        spacers: spacers
                    )
                }
            } onReset: {
                Task { await manager.resetFromCurrentWorkspace(profile) }
            }
        }
        .fileImporter(
            isPresented: $showsArchiveImporter,
            allowedContentTypes: [.barlineProfileArchive, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await manager.previewArchiveImport(from: url) }
            case .failure:
                manager.statusMessage = "No profile archive was selected."
            }
        }
        .fileExporter(
            isPresented: $showsArchiveExporter,
            document: exportDocument,
            contentType: .barlineProfileArchive,
            defaultFilename: "Barline Profiles"
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                manager.statusMessage = "Profile archive exported."
            case .failure:
                manager.statusMessage = "The profile archive was not saved."
            }
        }
    }
}
