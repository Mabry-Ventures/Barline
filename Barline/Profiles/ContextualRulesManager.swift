//
//  ContextualRulesManager.swift
//  Barline
//

import AppKit
import BarlineCore
import Combine

@MainActor
final class ContextualRulesManager: ObservableObject {
    private struct Input: Equatable, Sendable {
        let foreground: String?
        let power: RulePowerReader.Sample
        let focus: Bool?
        let interaction: Bool
    }

    @Published private(set) var preferences = RuleAutomationPreferences()
    @Published private(set) var isAvailable = false
    @Published private(set) var isSaving = false
    @Published private(set) var status = "Rules are off."
    @Published private(set) var saveError: String?
    private let store = ContextualRuleStore()
    private let power = RulePowerReader()
    private weak var appState: AppState?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 1
    private var stableSince = Date()
    private var lastInput: Input?
    private var manualOverride = false
    var isPaused: Bool {
        manualOverride
    }

    private var manualPauseRevision: UInt64 = 0
    private var suspendedContexts = Set<Int>()
    private var cancellables = Set<AnyCancellable>()
    private var powerObservation: RulePowerObservation?
    private var isApplyingRule = false

    func performSetup(with appState: AppState) async {
        self.appState = appState
        observeSession()
        observeInputs(appState)
        do {
            preferences = try await store.load()
            // Launch never turns a failed durable pause into an automatic
            // rearrangement. Enabled rules resume only through explicit UI intent.
            manualOverride = preferences.isPaused || preferences.isEnabled
            isAvailable = true
            restart()
            if preferences.isEnabled {
                status = "Rules paused after launch. Review your layout, then Resume Rules."
            }
        } catch {
            status = "Saved rules couldn’t be read. Automation is off; existing data was preserved."
        }
    }

    @discardableResult
    func save(_ updated: RuleAutomationPreferences) async -> Bool {
        guard isAvailable, !isSaving else { return false }
        isSaving = true
        saveError = nil
        let pauseRevision = manualPauseRevision
        task?.cancel()
        generation &+= 1
        defer { isSaving = false }
        do {
            try await store.save(updated)
            var committed = updated
            if manualPauseRevision != pauseRevision {
                // A user action during disk I/O wins over an earlier Resume.
                committed.isPaused = true
                try await store.save(committed)
            }
            preferences = committed
            manualOverride = committed.isPaused
            isSaving = false
            restart()
            return true
        } catch {
            manualOverride = true
            saveError = "Couldn’t finish saving rules. Automation is paused; reopen Settings after checking local storage."
            status = saveError ?? "Rules are paused."
            return false
        }
    }

    func pauseForManualChange() {
        guard preferences.isEnabled || isSaving else { return }
        manualOverride = true
        manualPauseRevision &+= 1
        generation &+= 1
        task?.cancel()
        status = "Paused after a manual layout change. Resume when ready."
        guard !isSaving else { return }
        var updated = preferences
        updated.isPaused = true
        Task { await save(updated) }
    }

    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        for (index, name) in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification,
        ].enumerated() {
            center.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspendedContexts.insert(index)
                    self?.generation &+= 1
                    self?.lastInput = nil
                    self?.contextDidChange()
                }
            }.store(in: &cancellables)
        }
        for (index, name) in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
        ].enumerated() {
            center.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspendedContexts.remove(index)
                    self?.generation &+= 1
                    self?.lastInput = nil
                    self?.stableSince = Date()
                    self?.contextDidChange()
                }
            }.store(in: &cancellables)
        }
    }

    private func restart() {
        task?.cancel()
        generation &+= 1
        lastInput = nil
        stableSince = Date()
        guard preferences.isEnabled, !manualOverride else {
            powerObservation = nil
            status = manualOverride ? "Rules paused. Your current layout is preserved." : "Rules are off."
            return
        }
        powerObservation = RulePowerObservation { [weak self] in self?.contextDidChange() }
        guard powerObservation?.isAvailable == true else {
            manualOverride = true
            status = "Power notifications are unavailable. Rules are paused."
            return
        }
        contextDidChange()
    }

    private func observeInputs(_ appState: AppState) {
        let inputs: [AnyPublisher<Void, Never>] = [
            NSWorkspace.shared.publisher(for: \.frontmostApplication).map { _ in () }.eraseToAnyPublisher(),
            appState.navigationState.$isBarlineShelfPresented.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            appState.navigationState.$isSearchPresented.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            appState.navigationState.$isSettingsPresented.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            appState.permissions.accessibility.$hasPermission.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            appState.itemManager.$hasPendingRestorations.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(inputs).receive(on: DispatchQueue.main).sink { [weak self] in
            self?.contextDidChange()
        }.store(in: &cancellables)
        appState.$isDraggingMenuBarItem.removeDuplicates().sink { [weak self] dragging in
            guard let self, !isApplyingRule else { return }
            if dragging {
                pauseForManualChange()
            } else {
                contextDidChange()
            }
        }.store(in: &cancellables)
        EventMonitor.publish(events: [.leftMouseUp, .rightMouseUp], scope: .universal)
            .filter { [weak self] _ in self?.isApplyingRule == false }
            .sink { [weak self] _ in
                // A layout move/compensation emits mouse-up too. It cannot
                // invalidate its own authority and start a repeated retry loop.
                // Other safety signals remain live, and admission samples
                // current hardware button state before every backend move.
                self?.contextDidChange()
            }.store(in: &cancellables)
        appState.profileManager.$isBusy.removeDuplicates().filter { !$0 }
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard self?.isApplyingRule == false else { return }
                self?.contextDidChange()
            }.store(in: &cancellables)
    }

    /// Invalidate admission immediately; perform one cancellable settled-context check.
    func contextDidChange() {
        generation &+= 1
        task?.cancel()
        guard isAvailable, preferences.isEnabled, !manualOverride, !isSaving else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let observed = await input()
            guard !Task.isCancelled else { return }
            lastInput = observed
            stableSince = Date()
            do {
                try await Task.sleep(for: .seconds(ContextualLayoutRuleEvaluator.minimumStableDuration))
            } catch { return }
            guard !Task.isCancelled else { return }
            await evaluate()
        }
    }

    private func input() async -> Input {
        let sample = await power.sample()
        return Input(
            foreground: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            power: sample,
            focus: appState?.profileManager.configuredFocusIsActive,
            interaction: !suspendedContexts.isEmpty || NSEvent.pressedMouseButtons != 0 ||
                appState?.navigationState.isBarlineShelfPresented == true ||
                appState?.navigationState.isSearchPresented == true || (appState?.isDraggingMenuBarItem == true && !isApplyingRule)
                || (appState?.navigationState.isSettingsPresented == true && appState?.navigationState.isAppFrontmost == true)
        )
    }

    private func context(_ input: Input, allowOwnMutation: Bool = false) -> ContextualLayoutContext {
        ContextualLayoutContext(
            generation: generation,
            capturedAt: Date(),
            stableSince: stableSince,
            foregroundBundleID: input.foreground,
            powerSource: input.power.source,
            batteryPercent: input.power.percent,
            nativeFocusIsActive: input.focus,
            manualOverrideIsActive: manualOverride,
            interactionIsActive: input.interaction,
            mutationIsActive: !allowOwnMutation && appState?.profileManager.isBusy == true,
            recoveryIsPending: appState?.itemManager.hasPendingRestorations != false
        )
    }

    private func evaluate() async {
        guard let appState, !isSaving, preferences.isEnabled, !manualOverride else { return }
        let observed = await input()
        guard !Task.isCancelled else { return }
        if lastInput != observed {
            contextDidChange()
            return
        }
        let ruleSet = ContextualLayoutRuleSet(rules: preferences.rules)
        let evaluation = ContextualLayoutRuleEvaluator.evaluate(
            ruleSet,
            context: context(observed),
            availableLayoutIDs: Set(appState.profileManager.profiles.map(\.id)),
            currentLayoutID: appState.profileManager.activeProfileID,
            now: Date()
        )
        guard case let .proposal(proposal) = evaluation,
              let profile = appState.profileManager.profiles.first(where: { $0.id == proposal.targetLayoutID })
        else {
            status = explanation(evaluation)
            return
        }
        guard profile.appearance.itemSpacing == appState.settings.general.itemSpacingOffset else {
            status = "This layout changes system item spacing. Apply it manually first; rules never restart other apps."
            return
        }
        let expectedGeneration = await appState.compatibilityCoordinator.mutationGeneration
        isApplyingRule = true
        defer { isApplyingRule = false }
        let applied = await appState.profileManager.activate(
            profile,
            source: .contextualRule,
            expectedGeneration: expectedGeneration,
            admission: { [weak self] in
                guard let self else { throw CancellationError() }
                try await validateAdmission(proposal: proposal, observed: observed, profile: profile)
            }
        )
        if applied {
            status = "Applied \(profile.name): \(reason(proposal.reason))."
        } else if !Task.isCancelled {
            // Do not hammer a failing transaction on every polling tick.
            pauseForManualChange()
            status = "Automatic change couldn’t complete. Rules are paused; review Recovery before resuming."
        }
    }

    private func validateAdmission(proposal: ContextualLayoutProposal, observed: Input, profile: BarlineProfile) async throws {
        try Task.checkCancellation()
        guard let appState, isAvailable, !isSaving, preferences.isEnabled,
              !manualOverride, generation == proposal.contextGeneration,
              appState.permissions.accessibility.hasPermission,
              profile.appearance.itemSpacing == appState.settings.general.itemSpacingOffset,
              appState.profileManager.profiles.first(where: { $0.id == profile.id }) == profile,
              await input() == observed else { throw CancellationError() }
        let fresh = ContextualLayoutRuleEvaluator.evaluate(
            ContextualLayoutRuleSet(rules: preferences.rules),
            context: context(observed, allowOwnMutation: true),
            availableLayoutIDs: [profile.id],
            currentLayoutID: nil,
            now: Date()
        )
        guard case let .proposal(current) = fresh, current == proposal else { throw CancellationError() }
    }

    private func explanation(_ value: ContextualLayoutEvaluation) -> String {
        switch value {
        case let .noChange(reason), let .deferred(reason): explanation(reason)
        case .proposal: "Preparing layout…"
        }
    }

    private func explanation(_ value: ContextualLayoutRuleReason) -> String {
        switch value {
        case .nativeFocusActive: "A configured macOS Focus layout takes priority."
        case .manualOverrideActive: "Paused after a manual layout change."
        case .interactionActive, .mutationActive: "Waiting for the current interaction to finish."
        case .recoveryPending: "Waiting for item restoration."
        case .contextUnstable: "Waiting for context to settle."
        case .alreadyApplied: "The matching layout is already applied."
        case .noEnabledRules: "No enabled rules."
        case .noMatchingRule: "No rule matches. Your current layout is preserved."
        case .targetLayoutMissing: "A matching rule’s saved layout is unavailable."
        default: "Waiting for trustworthy context. No layout changed."
        }
    }

    private func reason(_ value: ContextualLayoutRuleReason) -> String {
        switch value {
        case .foregroundBundleMatched: "the selected app is frontmost"
        case .powerSourceMatched: "the power source matches"
        case .lowBatteryMatched: "battery is below the selected threshold"
        default: "the rule matches"
        }
    }
}
