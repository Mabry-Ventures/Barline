//
//  Listener.swift
//  BarlineMenuService
//

import BarlineCore
import Foundation
import OSLog
import XPC

/// A wrapper around an XPC listener object.
final class Listener: @unchecked Sendable {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = BarlineMenuService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Probe-selected compatibility backend.
    private let backend: any MenuBarBackend

    /// Creates the shared listener.
    private init() {
        backend = MenuBarBackendFactory.make()
    }

    deinit {
        cancel()
    }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> BarlineMenuService.Response? {
        do {
            let request = try message.decode(as: BarlineMenuService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start
            case .capabilities:
                guard let capabilities = AsyncRequestBridge.run({ await self.backend.capabilities }) else {
                    return .capabilities(.failure(.timedOut))
                }
                return .capabilities(.success(capabilities))
            case .snapshot:
                let result: BarlineMenuService.ServiceResult<MenuBarSnapshot>? = AsyncRequestBridge.run {
                    do {
                        return try await .success(self.backend.snapshot())
                    } catch let error as MenuBarBackendError {
                        return .failure(error)
                    } catch {
                        return .failure(.operationFailed(error.localizedDescription))
                    }
                }
                return .snapshot(result ?? .failure(.timedOut))
            case let .move(operation):
                return .mutation(runMutation { try await self.backend.move(operation) })
            case let .reveal(item):
                return .mutation(runMutation { try await self.backend.reveal(item) })
            case let .activate(item, button):
                let result: BarlineMenuService.ServiceResult<BarlineMenuService.EmptyResult>? =
                    AsyncRequestBridge.run {
                        do {
                            try await self.backend.activate(item, button: button)
                            return .success(BarlineMenuService.EmptyResult())
                        } catch let error as MenuBarBackendError {
                            return .failure(error)
                        } catch {
                            return .failure(.operationFailed(error.localizedDescription))
                        }
                    }
                return .activation(result ?? .failure(.timedOut))
            case let .restore(snapshot):
                return .mutation(runMutation { try await self.backend.restore(snapshot) })
            case .health:
                let health = AsyncRequestBridge.run { await self.backend.health() } ?? MenuBarBackendHealth(
                    backendName: "XPC",
                    state: .unavailable,
                    message: "Compatibility request timed out"
                )
                return .health(health)
            case .restart:
                _ = AsyncRequestBridge.run { await self.backend.restart() }
                return .restart
            case let .sourcePID(window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)
            case let .legacy(request):
                return .legacy(handleLegacyRequest(request))
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    private func runMutation(
        _ operation: @escaping @Sendable () async throws -> MenuBarMutationResult
    ) -> BarlineMenuService.ServiceResult<MenuBarMutationResult> {
        AsyncRequestBridge.run {
            do {
                return try await .success(operation())
            } catch let error as MenuBarBackendError {
                return .failure(error)
            } catch {
                return .failure(.operationFailed(error.localizedDescription))
            }
        } ?? .failure(.timedOut)
    }

    private func handleLegacyRequest(
        _ request: BarlineMenuService.LegacyRequest
    ) -> BarlineMenuService.LegacyResponse {
        switch request {
        case let .setConnectionProperty(key, value):
            Bridging.setConnectionProperty(value, forKey: key)
            return .acknowledgement
        case .activeMenuBarDisplay:
            return .displayID(Bridging.getActiveMenuBarDisplayID())
        case .activeSpace:
            return .spaceID(Bridging.getActiveSpaceID())
        case let .currentSpace(displayID):
            return .spaceID(Bridging.getCurrentSpaceID(for: displayID))
        case let .isSpaceFullscreen(spaceID):
            return .boolean(Bridging.isSpaceFullscreen(spaceID))
        case let .windowBounds(windowID):
            return .rectangle(Bridging.getWindowBounds(for: windowID))
        case let .windowLevel(windowID):
            return .integer(Bridging.getWindowLevel(for: windowID))
        case let .windowList(options):
            return .windowIDs(Bridging.getWindowList(option: .init(rawValue: options)))
        case let .menuBarWindowList(options):
            return .windowIDs(Bridging.getMenuBarWindowList(option: .init(rawValue: options)))
        case let .processIsUnresponsive(pid):
            return .boolean(Bridging.isProcessUnresponsive(pid))
        case let .setProcessUnresponsiveTimeout(timeout):
            Bridging.setProcessUnresponsiveTimeout(timeout)
            return .acknowledgement
        case let .captureWindows(windowIDs, screenBounds, options):
            return .data(
                WindowCaptureService.capturePNG(
                    windowIDs: windowIDs,
                    screenBounds: screenBounds,
                    options: options
                )
            )
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { request in
            request.accept { message in
                self.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { request in
            request.accept { message in
                self.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard listener == nil else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            if #available(macOS 26.0, *) {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
    }
}

private enum AsyncRequestBridge {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value
    ) -> Value? {
        let semaphore = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock<Value?>(initialState: nil)
        Task.detached {
            let resolved = await operation()
            result.withLock { $0 = resolved }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 5) == .success else {
            return nil
        }
        return result.withLock { $0.take() }
    }
}
