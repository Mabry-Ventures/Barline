//
//  MenuBarSearchModel.swift
//  Barline
//

import Cocoa
import Combine
import Ifrit

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag)
    }

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    private var cancellables = Set<AnyCancellable>()

    let fuse = Fuse(threshold: 0.5)

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
