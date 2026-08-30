//
//  ProfileAuthorityPersistence.swift
//  BarlineCore
//

import Foundation

public struct ProfileActiveAuthority: Codable, Hashable, Sendable {
    public let profileID: UUID
    public let token: UUID
    public let presentation: ResolvedProfilePresentation

    public init(profileID: UUID, token: UUID, presentation: ResolvedProfilePresentation) {
        self.profileID = profileID
        self.token = token
        self.presentation = presentation
    }
}

public struct ProfileAuthorityEnvelope: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable {
        case active
        case pendingFocus
    }

    public let phase: Phase
    public let profileID: UUID
    public let token: UUID
    public let presentation: ResolvedProfilePresentation
    public let priorAuthority: ProfileActiveAuthority?
    public let pendingProfile: BarlineProfile?
    public let checkpoint: MenuBarWorkspaceCheckpoint?

    public init(active authority: ProfileActiveAuthority) {
        phase = .active
        profileID = authority.profileID
        token = authority.token
        presentation = authority.presentation
        priorAuthority = nil
        pendingProfile = nil
        checkpoint = nil
    }

    public init(
        pendingFocusProfile: BarlineProfile,
        token: UUID,
        presentation: ResolvedProfilePresentation,
        checkpoint: MenuBarWorkspaceCheckpoint,
        priorAuthority: ProfileActiveAuthority?
    ) {
        phase = .pendingFocus
        profileID = pendingFocusProfile.id
        self.token = token
        self.presentation = presentation
        self.priorAuthority = priorAuthority
        pendingProfile = pendingFocusProfile
        self.checkpoint = checkpoint
    }

    public var activeAuthority: ProfileActiveAuthority? {
        guard phase == .active else { return nil }
        return ProfileActiveAuthority(
            profileID: profileID,
            token: token,
            presentation: presentation
        )
    }
}

public final class ProfileAuthorityEnvelopeStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ProfileAuthorityEnvelope? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let envelope = try? JSONDecoder().decode(ProfileAuthorityEnvelope.self, from: data) {
            return envelope
        }
        guard let legacy = try? JSONDecoder().decode(ProfileActiveAuthority.self, from: data) else {
            return nil
        }
        return ProfileAuthorityEnvelope(active: legacy)
    }

    public func save(_ envelope: ProfileAuthorityEnvelope) throws {
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= ProfileCodec.maximumArchiveByteCount else {
            throw ProfileValidationError.archiveTooLarge(data.count)
        }
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else {
            throw MenuBarBackendError.operationFailed("profile authority persistence failed")
        }
    }

    public func remove() {
        defaults.removeObject(forKey: key)
    }
}
