//
//  MenuBarCommandValidation.swift
//  Barline
//

import Foundation

/// The bounded data schema accepted from a local system model. This type has no
/// execution behavior and cannot name private APIs, coordinates, processes, or files.
public struct MenuBarCommand: Codable, Equatable, Sendable {
    public let operation: MenuBarCommandOperation
    public let targetItemIDs: [MenuBarItemID]
    public let targetProfileID: ProfileID?
    public let confidence: Double

    public init(
        operation: MenuBarCommandOperation,
        targetItemIDs: [MenuBarItemID] = [],
        targetProfileID: ProfileID? = nil,
        confidence: Double
    ) {
        self.operation = operation
        self.targetItemIDs = targetItemIDs
        self.targetProfileID = targetProfileID
        self.confidence = confidence
    }
}

public enum MenuBarCommandOperation: String, Codable, CaseIterable, Sendable {
    case reveal
    case activate
    case show
    case hide
    case rearrange
    case group
    case activateProfile
    case replaceWithProfile
}

public struct MenuBarCommandValidationPolicy: Sendable {
    public let minimumConfidence: Double
    public let maximumItemTargets: Int
    public let bulkConfirmationThreshold: Int

    public init(
        minimumConfidence: Double = 0.65,
        maximumItemTargets: Int = 20,
        bulkConfirmationThreshold: Int = 1
    ) {
        self.minimumConfidence = min(max(minimumConfidence, 0), 1)
        self.maximumItemTargets = max(1, maximumItemTargets)
        self.bulkConfirmationThreshold = max(1, bulkConfirmationThreshold)
    }
}

public struct MenuBarCommandAuthority: Sendable {
    public let validatedSnapshot: MenuBarSnapshot
    public let expectedGeneration: UInt64
    public let availableProfileIDs: Set<ProfileID>
    public let now: Date

    init(
        validatedSnapshot: MenuBarSnapshot,
        expectedGeneration: UInt64,
        availableProfileIDs: Set<ProfileID> = [],
        now: Date = Date()
    ) {
        self.validatedSnapshot = validatedSnapshot
        self.expectedGeneration = expectedGeneration
        self.availableProfileIDs = availableProfileIDs
        self.now = now
    }

    /// Produces authority only from the coordinator's last validated state. A
    /// package client cannot construct authority from arbitrary model output.
    public static func current(
        from coordinator: MenuBarStateCoordinator,
        availableProfileIDs: Set<ProfileID> = [],
        now: Date = Date()
    ) async throws -> MenuBarCommandAuthority {
        guard let snapshot = await coordinator.currentSnapshot else {
            throw MenuBarCommandAuthorityError.noValidatedSnapshot
        }
        return MenuBarCommandAuthority(
            validatedSnapshot: snapshot,
            expectedGeneration: snapshot.generation,
            availableProfileIDs: availableProfileIDs,
            now: now
        )
    }
}

public enum MenuBarCommandAuthorityError: Error, Equatable, Sendable {
    case noValidatedSnapshot
}

public enum MenuBarCommandValidationError: Error, Equatable, Sendable {
    case invalidConfidence
    case lowConfidenceRequiresSearch
    case staleSnapshot(expected: UInt64, actual: UInt64)
    case snapshotRejected(SnapshotRejectionReason)
    case menuTrackingActive
    case missingItemTargets
    case tooManyItemTargets(maximum: Int, actual: Int)
    case duplicateItemTarget(MenuBarItemID)
    case staleOrUnavailableItem(MenuBarItemID)
    case unexpectedItemTargets
    case missingProfileTarget
    case unexpectedProfileTarget
    case staleOrUnavailableProfile(ProfileID)
    case operationRequiresMultipleItems(MenuBarCommandOperation)
}

public enum MenuBarCommandConfirmationReason: Equatable, Sendable {
    case bulkHide(itemCount: Int)
    case multiItemRearrangement(itemCount: Int)
    case groupMutation(itemCount: Int)
    case profileReplacement(ProfileID)
}

public enum MenuBarCommandConfirmation: Equatable, Sendable {
    case immediate
    case previewRequired(MenuBarCommandConfirmationReason)
}

/// This is the only command form suitable for an execution adapter. It is
/// deliberately non-Codable and has no public initializer, so decoding model
/// output can never manufacture validation authority.
public struct ValidatedMenuBarCommand: Equatable, Sendable {
    public let operation: MenuBarCommandOperation
    public let targetItemIDs: [MenuBarItemID]
    public let targetProfileID: ProfileID?
    public let authorityGeneration: UInt64
    public let confirmation: MenuBarCommandConfirmation

    fileprivate init(
        operation: MenuBarCommandOperation,
        targetItemIDs: [MenuBarItemID],
        targetProfileID: ProfileID?,
        authorityGeneration: UInt64,
        confirmation: MenuBarCommandConfirmation
    ) {
        self.operation = operation
        self.targetItemIDs = targetItemIDs
        self.targetProfileID = targetProfileID
        self.authorityGeneration = authorityGeneration
        self.confirmation = confirmation
    }
}

public struct MenuBarCommandValidator: Sendable {
    public let policy: MenuBarCommandValidationPolicy
    private let snapshotValidator: SnapshotValidator

    public init(
        policy: MenuBarCommandValidationPolicy = MenuBarCommandValidationPolicy(),
        snapshotValidationPolicy: SnapshotValidationPolicy = SnapshotValidationPolicy()
    ) {
        self.policy = policy
        snapshotValidator = SnapshotValidator(policy: snapshotValidationPolicy)
    }

    public func validate(
        _ command: MenuBarCommand,
        authority: MenuBarCommandAuthority
    ) -> Result<ValidatedMenuBarCommand, MenuBarCommandValidationError> {
        guard command.confidence.isFinite, (0 ... 1).contains(command.confidence) else {
            return .failure(.invalidConfidence)
        }
        guard command.confidence >= policy.minimumConfidence else {
            return .failure(.lowConfidenceRequiresSearch)
        }

        let snapshot = authority.validatedSnapshot
        guard snapshot.generation == authority.expectedGeneration else {
            return .failure(
                .staleSnapshot(expected: authority.expectedGeneration, actual: snapshot.generation)
            )
        }
        switch snapshotValidator.validate(snapshot, previous: nil, now: authority.now) {
        case let .failure(reason):
            return .failure(.snapshotRejected(reason))
        case .success:
            break
        }
        guard !snapshot.menuTrackingIsActive else {
            return .failure(.menuTrackingActive)
        }

        if command.targetItemIDs.count > policy.maximumItemTargets {
            return .failure(
                .tooManyItemTargets(
                    maximum: policy.maximumItemTargets,
                    actual: command.targetItemIDs.count
                )
            )
        }
        var uniqueTargets = Set<MenuBarItemID>()
        for itemID in command.targetItemIDs {
            guard uniqueTargets.insert(itemID).inserted else {
                return .failure(.duplicateItemTarget(itemID))
            }
        }
        let availableItems = Set(snapshot.items.map(\.id))
        if let unavailable = command.targetItemIDs.first(where: { !availableItems.contains($0) }) {
            return .failure(.staleOrUnavailableItem(unavailable))
        }

        if command.operation.usesProfile {
            guard command.targetItemIDs.isEmpty else { return .failure(.unexpectedItemTargets) }
            guard let profileID = command.targetProfileID else { return .failure(.missingProfileTarget) }
            guard authority.availableProfileIDs.contains(profileID) else {
                return .failure(.staleOrUnavailableProfile(profileID))
            }
        } else if command.targetProfileID != nil {
            return .failure(.unexpectedProfileTarget)
        }

        switch command.operation {
        case .reveal, .activate:
            guard command.targetItemIDs.count == 1 else { return .failure(.missingItemTargets) }
        case .show, .hide, .rearrange:
            guard !command.targetItemIDs.isEmpty else { return .failure(.missingItemTargets) }
        case .group:
            guard command.targetItemIDs.count >= 2 else {
                return .failure(.operationRequiresMultipleItems(.group))
            }
        case .activateProfile, .replaceWithProfile:
            break
        }

        let confirmation: MenuBarCommandConfirmation
        switch command.operation {
        case .hide where command.targetItemIDs.count > policy.bulkConfirmationThreshold:
            confirmation = .previewRequired(.bulkHide(itemCount: command.targetItemIDs.count))
        case .rearrange where command.targetItemIDs.count > 1:
            confirmation = .previewRequired(
                .multiItemRearrangement(itemCount: command.targetItemIDs.count)
            )
        case .group:
            confirmation = .previewRequired(.groupMutation(itemCount: command.targetItemIDs.count))
        case .replaceWithProfile:
            guard let profileID = command.targetProfileID else {
                return .failure(.missingProfileTarget)
            }
            confirmation = .previewRequired(.profileReplacement(profileID))
        default:
            confirmation = .immediate
        }

        return .success(
            ValidatedMenuBarCommand(
                operation: command.operation,
                targetItemIDs: command.targetItemIDs,
                targetProfileID: command.targetProfileID,
                authorityGeneration: snapshot.generation,
                confirmation: confirmation
            )
        )
    }
}

private extension MenuBarCommandOperation {
    var usesProfile: Bool {
        self == .activateProfile || self == .replaceWithProfile
    }
}
