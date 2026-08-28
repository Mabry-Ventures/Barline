//
//  Listener.swift
//  BarlineMenuService
//

import BarlineCore
import Foundation
import OSLog
import Security
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

    /// Returns a strict peer requirement for the containing Barline app.
    /// Certificate-signed builds require the same team and exact app signing
    /// identifier. Local gates use ad-hoc signing, so they require the exact app
    /// signing identifier and the local/ad-hoc validation category.
    @available(macOS 26.0, *)
    private static func appPeerRequirement() -> XPCPeerRequirement {
        let signingIdentifier = "com.mabryventures.Barline"
        if currentProcessHasTeamIdentifier() {
            return .isFromSameTeam(andMatchesSigningIdentifier: signingIdentifier)
        }
        var requirement = XPCDictionary()
        requirement["signing-identifier"] = signingIdentifier
        requirement["validation-category"] = 10
        return XPCPeerRequirement(lightweightCodeRequirements: requirement)
    }

    private static func currentProcessHasTeamIdentifier() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [CFString: Any],
            let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String
        else {
            return false
        }
        return !teamIdentifier.isEmpty
    }

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
            case let .capture(items):
                let result: BarlineMenuService.ServiceResult<[MenuBarCapturedImage]>? =
                    AsyncRequestBridge.run {
                        do {
                            return try await .success(self.backend.capture(items))
                        } catch let error as MenuBarBackendError {
                            return .failure(error)
                        } catch {
                            return .failure(.operationFailed(error.localizedDescription))
                        }
                    }
                return .capturedImages(result ?? .failure(.timedOut))
            case let .captureBackground(displayID, sampleHeight):
                let result: BarlineMenuService.ServiceResult<MenuBarBackgroundCapture>? =
                    AsyncRequestBridge.run {
                        do {
                            return try await .success(
                                self.backend.captureBackground(
                                    displayID: displayID,
                                    sampleHeight: sampleHeight
                                )
                            )
                        } catch let error as MenuBarBackendError {
                            return .failure(error)
                        } catch {
                            return .failure(.operationFailed(error.localizedDescription))
                        }
                    }
                return .background(result ?? .failure(.timedOut))
            case .environment:
                let result: BarlineMenuService.ServiceResult<MenuBarEnvironmentSnapshot>? =
                    AsyncRequestBridge.run {
                        do {
                            return try await .success(self.backend.environment())
                        } catch let error as MenuBarBackendError {
                            return .failure(error)
                        } catch {
                            return .failure(.operationFailed(error.localizedDescription))
                        }
                    }
                return .environment(result ?? .failure(.timedOut))
            case let .configureCursorInBackground(enabled):
                Bridging.setConnectionProperty(enabled, forKey: "SetsCursorInBackground")
                return .start
            case let .pointContext(point):
                let result: BarlineMenuService.ServiceResult<MenuBarPointContext>? =
                    AsyncRequestBridge.run {
                        do {
                            return try await .success(self.backend.pointContext(point))
                        } catch let error as MenuBarBackendError {
                            return .failure(error)
                        } catch {
                            return .failure(.operationFailed(error.localizedDescription))
                        }
                    }
                return .pointContext(result ?? .failure(.timedOut))
            case let .beginRevealObservation(item):
                let result: BarlineMenuService.ServiceResult<MenuBarRevealObservationToken>? =
                    AsyncRequestBridge.run {
                        do {
                            return try await .success(self.backend.beginRevealObservation(item))
                        } catch let error as MenuBarBackendError {
                            return .failure(error)
                        } catch {
                            return .failure(.operationFailed(error.localizedDescription))
                        }
                    }
                return .revealObservation(result ?? .failure(.timedOut))
            case let .revealObservationIsVisible(token):
                let result: BarlineMenuService.ServiceResult<Bool>? = AsyncRequestBridge.run {
                    do {
                        return try await .success(self.backend.revealObservationIsVisible(token))
                    } catch let error as MenuBarBackendError {
                        return .failure(error)
                    } catch {
                        return .failure(.operationFailed(error.localizedDescription))
                    }
                }
                return .boolean(result ?? .failure(.timedOut))
            case let .endRevealObservation(token):
                _ = AsyncRequestBridge.run { await self.backend.endRevealObservation(token) }
                return .start
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

    /// Activates the listener without checking if it is already active, using
    /// the strict certificate-signed or local ad-hoc peer requirement.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithPeerRequirement() throws {
        listener = try XPCListener(service: name, requirement: Self.appPeerRequirement()) { request in
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
                try uncheckedActivateWithPeerRequirement()
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
