//
//  BarlineMenuServiceConnection.swift
//  Barline
//

import BarlineCore
import Foundation
import OSLog

@available(macOS 26.0, *)
extension BarlineMenuService {
    final class Connection: Sendable {
        static let shared = Connection()

        private let session: Session
        private let queue: DispatchQueue
        private let logger: Logger

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

        func sourcePID(for window: WindowInfo) async -> pid_t? {
            guard case let .sourcePID(pid) = await send(.sourcePID(window)) else {
                logger.error("Source PID request returned an invalid response")
                return nil
            }
            return pid
        }

        func sendLegacy(_ request: LegacyRequest) -> LegacyResponse? {
            guard case let .legacy(response) = session.send(request: .legacy(request)) else {
                logger.error("Legacy compatibility request returned an invalid response")
                return nil
            }
            return response
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
            }
            session.setPeerRequirement(.isFromSameTeam())
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
    }
}
