//
//  ContextualRulesSection.swift
//  Barline
//

import BarlineCore
import SwiftUI
import UniformTypeIdentifiers

struct ContextualRulesSection: View {
    @ObservedObject var manager: ContextualRulesManager
    let profiles: [BarlineProfile]
    @State private var editedRule: ContextualLayoutRule?
    @State private var showsEditor = false

    var body: some View {
        Section("Automatic Layout Rules") {
            Toggle("Enable local rules", isOn: Binding(
                get: { manager.preferences.isEnabled },
                set: { enabled in
                    var updated = manager.preferences
                    updated.isEnabled = enabled
                    Task { await manager.save(updated) }
                }
            ))
            Text("Configured macOS Focus layouts take priority. Manual layout changes pause rules until you resume. When nothing matches, your current layout stays unchanged.")
                .foregroundStyle(.secondary)
            Text("Rules also start paused when Barline reopens. Resume after checking your layout; a failed save or interrupted session must never silently resume automation.")
                .font(.caption).foregroundStyle(.secondary)
            Text(manager.status).accessibilityIdentifier("rules-status")
            if manager.preferences.isEnabled {
                Button(manager.isPaused ? "Resume Rules" : "Pause Rules") {
                    var updated = manager.preferences
                    updated.isPaused = !manager.isPaused
                    Task { await manager.save(updated) }
                }
            }
            ForEach(manager.preferences.rules, id: \.id) { rule in
                HStack {
                    VStack(alignment: .leading) {
                        Text(RuleEditorSheet.description(rule.condition))
                        Text("\(profiles.first { $0.id == rule.targetLayoutID }?.name ?? "Unavailable layout") · Priority \(rule.priority) · \(rule.isEnabled ? "Enabled" : "Disabled")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editedRule = rule; showsEditor = true }
                        .accessibilityLabel("Edit rule: \(RuleEditorSheet.description(rule.condition))")
                    Button("Remove", role: .destructive) {
                        var updated = manager.preferences
                        updated.rules.removeAll { $0.id == rule.id }
                        Task { await manager.save(updated) }
                    }
                    .accessibilityLabel("Remove rule: \(RuleEditorSheet.description(rule.condition))")
                }
            }
            Button("Add Rule…") { editedRule = nil; showsEditor = true }
                .disabled(profiles.isEmpty || manager.preferences.rules.count >= 64)
            Text("Higher priorities win; equal priorities use the order above. Changes wait for three seconds of stable context and for menus and item restoration to finish.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Rules never restart other apps. If a layout changes system item spacing, apply it manually before using it in a rule.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!manager.isAvailable || manager.isSaving)
        .sheet(isPresented: $showsEditor) {
            RuleEditorSheet(rule: editedRule, profiles: profiles) { rule in
                var updated = manager.preferences
                if let index = updated.rules.firstIndex(where: { $0.id == rule.id }) {
                    updated.rules[index] = rule
                } else {
                    updated.rules.append(rule)
                }
                return await manager.save(updated)
            }
        }
    }
}

private struct RuleEditorSheet: View {
    enum Kind: String, CaseIterable { case app = "Frontmost app", power = "Power source", battery = "Battery below" }
    let rule: ContextualLayoutRule?
    let profiles: [BarlineProfile]
    let save: (ContextualLayoutRule) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.app
    @State private var bundleID = ""
    @State private var source = LayoutRulePowerSource.external
    @State private var threshold = 20
    @State private var priority = 0
    @State private var enabled = true
    @State private var target: UUID?
    @State private var showsAppPicker = false
    @State private var isBusy = false
    @State private var appFailure = false
    @State private var saveFailure = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Enabled", isOn: $enabled)
                Picker("When", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                switch kind {
                case .app:
                    LabeledContent("Application", value: bundleID.isEmpty ? "Choose an app" : bundleID)
                    Button("Choose Application…") { showsAppPicker = true }
                case .power:
                    Picker("Source", selection: $source) {
                        Text("External power").tag(LayoutRulePowerSource.external)
                        Text("Battery").tag(LayoutRulePowerSource.battery)
                    }
                case .battery:
                    Stepper("Below \(threshold)% while on battery", value: $threshold, in: 1 ... 100)
                }
                Picker("Apply layout", selection: $target) {
                    Text("Choose a saved layout").tag(UUID?.none)
                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                Stepper("Priority: \(priority)", value: $priority, in: 0 ... 1000)
            }
            .formStyle(.grouped)
            .navigationTitle(rule == nil ? "Add Layout Rule" : "Edit Layout Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = draft else { return }
                        isBusy = true
                        Task {
                            let saved = await save(value)
                            isBusy = false
                            if saved {
                                dismiss()
                            } else {
                                saveFailure = true
                            }
                        }
                    }.disabled(draft == nil || isBusy)
                }
            }
            .disabled(isBusy)
        }
        .frame(width: 520, height: 370)
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            target = rule?.targetLayoutID ?? profiles.first?.id
            guard let rule else { return }
            priority = rule.priority
            enabled = rule.isEnabled
            switch rule.condition {
            case let .foregroundBundle(value): kind = .app; bundleID = value
            case let .powerSource(value): kind = .power; source = value
            case let .batteryBelow(value): kind = .battery; threshold = value
            }
        }
        .fileImporter(isPresented: $showsAppPicker, allowedContentTypes: [.application]) { result in
            guard case let .success(url) = result else { return }
            isBusy = true
            Task {
                let identifier = await Task.detached {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    return Bundle(url: url)?.bundleIdentifier
                }.value
                isBusy = false
                if let identifier {
                    bundleID = identifier
                } else {
                    appFailure = true
                }
            }
        }
        .alert("This application has no readable identifier", isPresented: $appFailure) {
            Button("OK", role: .cancel) {}
        }
        .alert("Couldn’t save this rule", isPresented: $saveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your draft is still here. Automation is paused; check local storage before trying again.")
        }
    }

    private var draft: ContextualLayoutRule? {
        guard let target, profiles.contains(where: { $0.id == target }) else { return nil }
        let condition: ContextualLayoutRule.Condition = switch kind {
        case .app: .foregroundBundle(bundleID)
        case .power: .powerSource(source)
        case .battery: .batteryBelow(threshold)
        }
        let value = ContextualLayoutRule(
            id: rule?.id ?? UUID(),
            targetLayoutID: target,
            isEnabled: enabled,
            priority: priority,
            condition: condition
        )
        return value.isValid ? value : nil
    }

    static func description(_ condition: ContextualLayoutRule.Condition) -> String {
        switch condition {
        case let .foregroundBundle(value): "When \(value) is frontmost"
        case let .powerSource(value): value == .battery ? "When on battery" : "When on external power"
        case let .batteryBelow(value): "When battery is below \(value)%"
        }
    }
}
