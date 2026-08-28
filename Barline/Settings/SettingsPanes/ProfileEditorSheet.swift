//
//  ProfileEditorSheet.swift
//  Barline
//

import BarlineCore
import SwiftUI

struct ProfileEditorSheet: View {
    let profile: BarlineProfile
    let canResetFromWorkspace: Bool
    let onSave: (String, String?, [ProfileGroup], [ProfileSpacer]) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var groups: [ProfileGroup]
    @State private var spacers: [ProfileSpacer]
    @State private var showsResetConfirmation = false

    init(
        profile: BarlineProfile,
        canResetFromWorkspace: Bool,
        onSave: @escaping (String, String?, [ProfileGroup], [ProfileSpacer]) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.profile = profile
        self.canResetFromWorkspace = canResetFromWorkspace
        self.onSave = onSave
        self.onReset = onReset
        _name = State(initialValue: profile.name)
        _symbol = State(initialValue: profile.symbol ?? "")
        _groups = State(initialValue: profile.groups)
        _spacers = State(initialValue: profile.spacers)
    }

    private var itemIDs: [MenuBarItemID] {
        profile.layout.allItemIDs
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSymbol: String? {
        let value = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    LabeledContent("Symbol") {
                        HStack {
                            Image(systemName: normalizedSymbol ?? "menubar.rectangle")
                            TextField("SF Symbol", text: $symbol)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Groups") {
                    if groups.isEmpty {
                        Text("No groups")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { group in
                        groupEditor(group)
                    }
                    Button("Add Group", systemImage: "plus") {
                        groups.append(ProfileGroup(name: "New Group", itemIDs: []))
                    }
                }

                Section("Spacers") {
                    if spacers.isEmpty {
                        Text("No spacers")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(spacers) { spacer in
                        spacerEditor(spacer)
                    }
                    Menu("Add Spacer", systemImage: "plus") {
                        ForEach(BarlineCore.MenuBarSection.allCases, id: \.self) { section in
                            Button("End of \(sectionLabel(section))") {
                                spacers.append(ProfileSpacer(placement: .end(section)))
                            }
                        }
                    }
                }

                Section("Recovery") {
                    Button("Reset Profile from Current Workspace", role: .destructive) {
                        showsResetConfirmation = true
                    }
                    .disabled(!canResetFromWorkspace)
                    Text("Replaces this profile’s layout and modeled workspace settings, and removes its groups, spacers, and display overrides. Other profiles and app settings are preserved.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(normalizedName, normalizedSymbol, groups, spacers)
                        dismiss()
                    }
                    .disabled(
                        normalizedName.isEmpty || groups.contains {
                            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                    )
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .confirmationDialog(
            "Reset \(profile.name)?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Profile", role: .destructive) {
                onReset()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current validated layout and supported workspace settings will replace this profile.")
        }
    }

    @ViewBuilder
    private func groupEditor(_ group: ProfileGroup) -> some View {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            HStack {
                TextField("Group name", text: $groups[index].name)
                Menu("Items (\(groups[index].itemIDs.count))") {
                    ForEach(itemIDs, id: \.self) { itemID in
                        Button {
                            toggle(itemID, inGroupAt: index)
                        } label: {
                            if groups[index].itemIDs.contains(itemID) {
                                Label(itemLabel(itemID), systemImage: "checkmark")
                            } else {
                                Text(itemLabel(itemID))
                            }
                        }
                    }
                }
                Button(role: .destructive) {
                    groups.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete \(group.name) group")
            }
        }
    }

    @ViewBuilder
    private func spacerEditor(_ spacer: ProfileSpacer) -> some View {
        if let index = spacers.firstIndex(where: { $0.id == spacer.id }) {
            VStack(alignment: .leading) {
                HStack {
                    Text(spacerLabel(spacers[index].placement))
                    Spacer()
                    Stepper(
                        "\(Int(spacers[index].width)) pt",
                        value: $spacers[index].width,
                        in: 1 ... 160,
                        step: 1
                    )
                    Button(role: .destructive) {
                        spacers.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete spacer")
                }
                Menu("Change Placement") {
                    ForEach(BarlineCore.MenuBarSection.allCases, id: \.self) { section in
                        Button("Beginning of \(sectionLabel(section))") {
                            spacers[index].placement = .beginning(section)
                        }
                        Button("End of \(sectionLabel(section))") {
                            spacers[index].placement = .end(section)
                        }
                    }
                    if !itemIDs.isEmpty {
                        Divider()
                        ForEach(itemIDs, id: \.self) { itemID in
                            Button("After \(itemLabel(itemID))") {
                                spacers[index].placement = .after(itemID)
                            }
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func toggle(_ itemID: MenuBarItemID, inGroupAt index: Int) {
        if let memberIndex = groups[index].itemIDs.firstIndex(of: itemID) {
            groups[index].itemIDs.remove(at: memberIndex)
        } else {
            groups[index].itemIDs.append(itemID)
        }
    }

    private func itemLabel(_ itemID: MenuBarItemID) -> String {
        itemID.alias ?? itemID.title ?? itemID.accessibilityIdentifier ?? itemID.bundleIdentifier
    }

    private func sectionLabel(_ section: BarlineCore.MenuBarSection) -> String {
        switch section {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }

    private func spacerLabel(_ placement: ProfileSpacer.Placement) -> String {
        switch placement {
        case let .beginning(section): "Beginning of \(sectionLabel(section))"
        case let .after(itemID): "After \(itemLabel(itemID))"
        case let .end(section): "End of \(sectionLabel(section))"
        }
    }
}
