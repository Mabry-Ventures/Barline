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

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    private var cancellables = Set<AnyCancellable>()

    private var spotlightDocuments = [SearchDocument]()

    func rankedDocumentIDs(for query: String, documents: [SearchDocument]) -> [SearchDocumentID] {
        do {
            let index = try DeterministicSearchIndex(documents: documents)
            synchronizeSpotlightIfNeeded(with: documents)
            return index.search(query, limit: documents.count).map(\.document.id)
        } catch {
            Logger(category: "Search").error("Search index synchronization failed")
            return []
        }
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
