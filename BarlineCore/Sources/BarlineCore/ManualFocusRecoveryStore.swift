import Foundation

/// A bounded, manual-only receipt, separate from active Focus authority.
/// An existing different checkpoint must never be overwritten silently.
public final class ManualFocusRecoveryStore {
    private let defaults: UserDefaults
    private let key: String
    private let store: ProfileAuthorityEnvelopeStore

    public init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
        store = ProfileAuthorityEnvelopeStore(defaults: defaults, key: key)
    }

    public func load() -> ProfileAuthorityEnvelope? {
        guard let data = defaults.data(forKey: key), data.count <= ProfileCodec.maximumArchiveByteCount,
              let value = store.load(), value.phase == .pendingFocus, value.checkpoint != nil else { return nil }
        return value
    }

    public func validateArchiving(_ value: ProfileAuthorityEnvelope) throws {
        guard value.phase == .pendingFocus, value.checkpoint != nil,
              defaults.object(forKey: key) == nil || load() == value
        else {
            throw MenuBarBackendError.operationFailed("manual recovery archive is occupied or invalid")
        }
    }

    public func archive(_ value: ProfileAuthorityEnvelope) throws {
        try validateArchiving(value)
        try store.save(value)
    }

    public func remove(ifMatching token: UUID) {
        guard load()?.token == token else { return }
        store.remove()
    }
}
