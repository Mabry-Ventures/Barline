//
//  BarlineMenuServiceConnection.swift
//  Barline
//

import BarlineCore
import CoreGraphics
import Foundation
import OSLog
import Security
import XPC

@available(macOS 26.0, *)
extension BarlineMenuService {
    final class Connection: Sendable {
        static let shared = Connection()

        private let session: Session
        private let queue: DispatchQueue
        private let logger: Logger

        /// Returns a strict peer requirement for the embedded compatibility service.
        ///
        /// Apple-issued development and distribution signatures have a team
        /// identifier, so production uses the strongest same-team plus exact
        /// signing-identifier check. Local gates intentionally use ad-hoc signing,
        /// which has no team identifier; those builds remain constrained to the
        /// service's exact signing identifier and the local/ad-hoc validation
        /// category instead of disabling peer validation.
        fileprivate static func servicePeerRequirement() -> XPCPeerRequirement {
            let signingIdentifier = "com.mabryventures.Barline.MenuBarService"
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

        private init() {
            let queue = DispatchQueue(
                label: "BarlineMenuService.Connection.queue",
                qos: .userInteractive
            )
            let logger = Logger(category: "BarlineMenuService.Connection")
            session = Session(logger: logger)
            self.queue = queue
            self.logger = logger
        }

        func start() async {
            logger.debug("Starting BarlineMenuService connection")
            guard case .start = await send(.start) else {
                logger.error("Start request returned an invalid response")
                return
            }
        }

        func capabilities() async throws -> MenuBarCapabilities {
            guard case let .capabilities(result) = await send(.capabilities) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func snapshot() async throws -> MenuBarSnapshot {
            guard case let .snapshot(result) = await send(.snapshot) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult {
            guard case let .mutation(result) = await send(.move(operation)) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult {
            guard case let .mutation(result) = await send(.reveal(item)) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) async throws {
            guard case let .activation(result) = await send(.activate(item: item, button: button)) else {
                throw MenuBarBackendError.interrupted
            }
            _ = try result.value()
        }

        func capture(_ items: [MenuBarItemID]) async throws -> [MenuBarCapturedImage] {
            guard case let .capturedImages(result) = await send(.capture(items)) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func captureBackground(
            displayID: CGDirectDisplayID,
            sampleHeight: CGFloat? = nil
        ) async throws -> MenuBarBackgroundCapture {
            guard case let .background(result) = await send(
                .captureBackground(
                    displayID: displayID,
                    sampleHeight: sampleHeight.map(Double.init)
                )
            ) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func environment() async throws -> MenuBarEnvironmentSnapshot {
            guard case let .environment(result) = await send(.environment) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func configureCursorInBackground(_ enabled: Bool) async {
            _ = await send(.configureCursorInBackground(enabled))
        }

        func pointContext(at point: CGPoint) async throws -> MenuBarPointContext {
            guard case let .pointContext(result) = await send(
                .pointContext(MenuBarPoint(x: point.x, y: point.y))
            ) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func beginRevealObservation(
            for item: MenuBarItemID
        ) async throws -> MenuBarRevealObservationToken {
            guard case let .revealObservation(result) = await send(.beginRevealObservation(item)) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func revealObservationIsVisible(
            _ token: MenuBarRevealObservationToken
        ) async throws -> Bool {
            guard case let .boolean(result) = await send(.revealObservationIsVisible(token)) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func endRevealObservation(_ token: MenuBarRevealObservationToken) async {
            _ = await send(.endRevealObservation(token))
        }

        func restore(_ snapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult {
            guard case let .mutation(result) = await send(.restore(snapshot)) else {
                throw MenuBarBackendError.interrupted
            }
            return try result.value()
        }

        func health() async -> MenuBarBackendHealth {
            guard case let .health(health) = await send(.health) else {
                return MenuBarBackendHealth(
                    backendName: "XPC",
                    state: .unavailable,
                    message: "Compatibility service did not respond"
                )
            }
            return health
        }

        func restart() async {
            session.cancel(reason: "Explicit compatibility restart")
            _ = await send(.restart)
        }

        private func send(_ request: Request) async -> Response? {
            await withCheckedContinuation { continuation in
                queue.async { [session] in
                    continuation.resume(returning: session.send(request: request))
                }
            }
        }
    }
}

private extension BarlineMenuService.ServiceResult {
    func value() throws -> Value {
        switch self {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}

@available(macOS 26.0, *)
extension BarlineMenuService {
    private final class Session: @unchecked Sendable {
        private struct State: @unchecked Sendable {
            var session: XPCSession?
            var generation: UInt64 = 0
        }

        private let name = BarlineMenuService.name
        private let state = OSAllocatedUnfairLock(initialState: State())
        private let callbackQueue = DispatchQueue(
            label: "BarlineMenuService.Connection.callback",
            qos: .userInteractive,
            attributes: .concurrent
        )
        private let transportQueue = DispatchQueue(
            label: "BarlineMenuService.Connection.transport",
            qos: .userInteractive,
            attributes: .concurrent
        )
        private let recoveryScheduled = OSAllocatedUnfairLock(initialState: false)
        private let logger: Logger

        init(logger: Logger) {
            self.logger = logger
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        func cancel(reason: String) {
            let oldSession = state.withLock { state -> XPCSession? in
                state.generation &+= 1
                return state.session.take()
            }
            oldSession?.cancel(reason: reason)
        }

        func send(request: Request) -> Response? {
            let semaphore = DispatchSemaphore(value: 0)
            let result = OSAllocatedUnfairLock<Response?>(initialState: nil)
            transportQueue.async { [self] in
                let response = performSend(request: request)
                result.withLock { $0 = response }
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + 5) == .success else {
                logger.error("Compatibility request timed out")
                cancel(reason: "Request timed out")
                return nil
            }
            return result.withLock { $0.take() }
        }

        private func performSend(request: Request) -> Response? {
            do {
                let (session, generation) = try getOrCreateSession()
                let reply = try session.sendSync(request)
                let response = try reply.decode(as: Response.self)
                let remainsCurrent = state.withLock { $0.generation == generation }
                return remainsCurrent ? response : nil
            } catch {
                logger.error("Session failed with error \(error)")
                cancel(reason: "Send failed: \(error.localizedDescription)")
                return nil
            }
        }

        private func getOrCreateSession() throws -> (XPCSession, UInt64) {
            if let existing = state.withLock({ state -> (XPCSession, UInt64)? in
                state.session.map { ($0, state.generation) }
            }) {
                return existing
            }
            let generation = state.withLock { state in
                state.generation &+= 1
                return state.generation
            }
            let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                guard let self else { return }
                logger.warning("Session was cancelled with error \(error.localizedDescription)")
                state.withLock { state in
                    guard state.generation == generation else { return }
                    state.generation &+= 1
                    state.session = nil
                }
                scheduleRecovery()
            }
            session.setPeerRequirement(BarlineMenuService.Connection.servicePeerRequirement())
            session.setTargetQueue(callbackQueue)
            try session.activate()
            let installed = state.withLock { state -> Bool in
                guard state.generation == generation, state.session == nil else {
                    return false
                }
                state.session = session
                return true
            }
            guard installed else {
                session.cancel(reason: "Superseded during activation")
                throw MenuBarBackendError.interrupted
            }
            return (session, generation)
        }

        private func scheduleRecovery() {
            let shouldSchedule = recoveryScheduled.withLock { scheduled in
                guard !scheduled else { return false }
                scheduled = true
                return true
            }
            guard shouldSchedule else { return }
            performRecoveryAttempt(0)
        }

        private func performRecoveryAttempt(_ attempt: Int) {
            let boundedAttempt = min(max(attempt, 0), 3)
            let delay = 0.1 * pow(2, Double(boundedAttempt))
            transportQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                if case .start? = performSend(request: .start) {
                    recoveryScheduled.withLock { $0 = false }
                    logger.notice("Compatibility service recovered after interruption")
                } else if boundedAttempt < 3 {
                    performRecoveryAttempt(boundedAttempt + 1)
                } else {
                    recoveryScheduled.withLock { $0 = false }
                    logger.error("Compatibility service recovery attempts were exhausted")
                }
            }
        }
    }
}
