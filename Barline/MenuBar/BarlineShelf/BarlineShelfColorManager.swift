//
//  BarlineShelfColorManager.swift
//  Barline
//

import Combine
import SwiftUI

@MainActor
final class BarlineShelfColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var barlineShelfPanel: BarlineShelfPanel?

    private var windowImage: CGImage?

    private var cancellables = Set<AnyCancellable>()

    func performSetup(with barlineShelfPanel: BarlineShelfPanel) {
        self.barlineShelfPanel = barlineShelfPanel
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let barlineShelfPanel {
            barlineShelfPanel.publisher(for: \.screen)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] screen in
                    guard
                        let self,
                        let screen,
                        screen == .main
                    else {
                        return
                    }
                    updateWindowImage(for: screen)
                }
                .store(in: &c)

            barlineShelfPanel.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak barlineShelfPanel] isVisible in
                    guard
                        let self,
                        let barlineShelfPanel,
                        let screen = barlineShelfPanel.screen,
                        isVisible,
                        screen == .main
                    else {
                        return
                    }
                    updateColorInfo(with: barlineShelfPanel.frame, screen: screen)
                }
                .store(in: &c)

            barlineShelfPanel.publisher(for: \.frame)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self, weak barlineShelfPanel] frame in
                    guard
                        let self,
                        let barlineShelfPanel,
                        let screen = barlineShelfPanel.screen,
                        barlineShelfPanel.isVisible,
                        screen == .main
                    else {
                        return
                    }
                    withAnimation(.interactiveSpring) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

            Publishers.Merge3(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                    .replace(with: ()),
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ()),
                DistributedNotificationCenter.default()
                    .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                    .replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak barlineShelfPanel] in
                guard
                    let self,
                    let barlineShelfPanel,
                    let screen = barlineShelfPanel.screen,
                    screen == .main
                else {
                    return
                }
                updateWindowImage(for: screen)
                if barlineShelfPanel.isVisible {
                    withAnimation {
                        self.updateColorInfo(with: barlineShelfPanel.frame, screen: screen)
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateWindowImage(for screen: NSScreen) {
        Task { [weak self] in
            guard
                let self,
                let capture = await ScreenCapture.captureMenuBarBackground(
                    displayID: screen.displayID,
                    sampleHeight: 1
                ),
                let image = capture.image
            else {
                return
            }
            windowImage = image
        }
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0 ... 1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether its image contributed to the average.
        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        Task { [weak self] in
            guard
                let self,
                let capture = await ScreenCapture.captureMenuBarBackground(
                    displayID: screen.displayID,
                    sampleHeight: 1
                ),
                let image = capture.image
            else {
                return
            }
            windowImage = image
            updateColorInfo(with: frame, screen: screen)
        }
    }
}
