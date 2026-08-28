//
//  MenuBarSearchModel.swift
//  Barline
//

import BarlineCore
import Cocoa
import Combine
import OSLog

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag)
        case profileHeader
        case profile(UUID)
    }

    enum CommandInterpretationState: Equatable {
        case idle
        case deterministicOnly
        case interpreting
        case unavailable(SearchCapabilityUnavailableReason)
        case fallback
        case validated(ValidatedMenuBarCommand)
        case previewRequired(ValidatedMenuBarCommand)
        case nonRunnable(ValidatedMenuBarCommand, SearchCommandNonRunnableReason)
    }

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?
    @Published private(set) var commandInterpretationState: CommandInterpretationState = .idle

    private var cancellables = Set<AnyCancellable>()
    private let commandInterpreter: any MenuBarCommandInterpreting
    private let commandRoutingPolicy = SearchCommandRoutingPolicy()
    private let commandValidator = MenuBarCommandValidator()
    private var commandInterpretationTask: Task<Void, Never>?
    private var commandInterpretationSequence: UInt64 = 0
    private var spotlightDocuments = [SearchDocument]()

    init(commandInterpreter: any MenuBarCommandInterpreting = FoundationModelCommandInterpreter()) {
        self.commandInterpreter = commandInterpreter
    }

    func rankedResults(for query: String, documents: [SearchDocument]) -> [SearchResult] {
        do {
            let index = try DeterministicSearchIndex(documents: documents)
            synchronizeSpotlightIfNeeded(with: documents)
            return index.search(query, limit: documents.count)
        } catch {
            Logger(category: "Search").error("Search index synchronization failed")
            return []
        }
    }

    func rankedDocumentIDs(for query: String, documents: [SearchDocument]) -> [SearchDocumentID] {
        rankedResults(for: query, documents: documents).map(\.document.id)
    }

    func considerCommandInterpretation(
        query: String,
        documents: [SearchDocument],
        deterministicResults: [SearchResult],
        coordinator: MenuBarStateCoordinator,
        availableProfileIDs: Set<ProfileID>
    ) {
        commandInterpretationSequence += 1
        let requestSequence = commandInterpretationSequence
        commandInterpretationTask?.cancel()
        guard commandRoutingPolicy.shouldInterpret(
            query: query,
            deterministicResults: deterministicResults
        ) else {
            commandInterpretationState = .deterministicOnly
            return
        }

        let availability = SearchRuntimeAvailability.current()
        let plan = availability.plan(for: .ambiguousNaturalLanguage)
        guard plan.useFoundationModels else {
            if case let .unavailable(reason) = availability.foundationModels {
                commandInterpretationState = .unavailable(reason)
            } else {
                commandInterpretationState = .fallback
            }
            return
        }

        let context = boundedModelContext(documents: documents, results: deterministicResults)
        let interpreter = commandInterpreter
        let validator = commandValidator
        commandInterpretationState = .interpreting
        commandInterpretationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard self?.commandRequestIsCurrent(requestSequence, query: query) == true else {
                    return
                }
                let command = try await interpreter.interpret(query: query, documents: context)
                guard self?.commandRequestIsCurrent(requestSequence, query: query) == true else {
                    return
                }

                // Model inference can outlive the snapshot it started with. Refresh
                // before creating authority so validation never relies on that stale state.
                _ = try await coordinator.refresh()
                guard self?.commandRequestIsCurrent(requestSequence, query: query) == true else {
                    return
                }
                let authority = try await MenuBarCommandAuthority.current(
                    from: coordinator,
                    availableProfileIDs: availableProfileIDs
                )
                let validated = try validator.validate(command, authority: authority).get()
                guard self?.commandRequestIsCurrent(requestSequence, query: query) == true else {
                    return
                }
                let disposition = SearchCommandExecutionPolicy().disposition(
                    for: validated,
                    in: authority.validatedSnapshot
                )
                if case let .nonRunnable(reason) = disposition {
                    self?.commandInterpretationState = .nonRunnable(validated, reason)
                    return
                }
                switch validated.confirmation {
                case .immediate:
                    self?.commandInterpretationState = .validated(validated)
                case .previewRequired:
                    self?.commandInterpretationState = .previewRequired(validated)
                }
            } catch is CancellationError {
                return
            } catch {
                guard self?.commandRequestIsCurrent(requestSequence, query: query) == true else {
                    return
                }
                self?.commandInterpretationState = .fallback
            }
        }
    }

    func resetCommandInterpretation() {
        commandInterpretationSequence += 1
        commandInterpretationTask?.cancel()
        commandInterpretationTask = nil
        commandInterpretationState = .idle
    }

    func markCommandNonRunnable(
        _ command: ValidatedMenuBarCommand,
        reason: SearchCommandNonRunnableReason
    ) {
        commandInterpretationState = .nonRunnable(command, reason)
    }

    private func commandRequestIsCurrent(_ sequence: UInt64, query: String) -> Bool {
        !Task.isCancelled
            && sequence == commandInterpretationSequence
            && searchText == query
    }

    private func boundedModelContext(
        documents: [SearchDocument],
        results: [SearchResult]
    ) -> [SearchDocument] {
        var seen = Set<SearchDocumentID>()
        return (results.map(\.document) + documents)
            .filter { seen.insert($0.id).inserted }
            .prefix(30)
            .map(\.self)
    }

    func synchronizeSpotlightIfNeeded(with documents: [SearchDocument]) {
        guard documents != spotlightDocuments else { return }
        spotlightDocuments = documents
        Task {
            do {
                try await CoreSpotlightIndexer.shared.replaceAll(with: documents)
            } catch CoreSpotlightIndexingError.unavailable {
                // Search remains fully available through the in-process index.
            } catch {
                Logger(category: "Search").error("Spotlight synchronization failed")
            }
        }
    }

    func performSetup(with panel: MenuBarSearchPanel) {
        configureCancellables(with: panel)
    }

    private func configureCancellables(with panel: MenuBarSearchPanel) {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            panel.publisher(for: \.screen),
            panel.publisher(for: \.isVisible)
        )
        .compactMap { screen, isVisible in
            isVisible ? screen : nil
        }
        .sink { [weak self] screen in
            self?.updateAverageColorInfo(for: screen)
        }
        .store(in: &c)

        cancellables = c
    }

    private func updateAverageColorInfo(for screen: NSScreen) {
        Task { [weak self] in
            guard
                let self,
                let capture = await ScreenCapture.captureMenuBarBackground(
                    displayID: screen.displayID,
                    sampleHeight: 1
                ),
                let image = capture.image,
                let color = image.averageColor(option: .ignoreAlpha)
            else {
                return
            }
            let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)
            if averageColorInfo != info {
                averageColorInfo = info
            }
        }
    }
}
