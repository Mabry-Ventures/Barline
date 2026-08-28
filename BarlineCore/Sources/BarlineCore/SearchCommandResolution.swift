//
//  SearchCommandResolution.swift
//  Barline
//

import Foundation

/// Inert output from a structured model adapter. Document IDs are resolved
/// against the exact privacy-bounded context before a `MenuBarCommand` exists.
public struct SearchCommandCandidate: Codable, Equatable, Sendable {
    public let operation: MenuBarCommandOperation
    public let targetDocumentIDs: [SearchDocumentID]
    public let targetProfileDocumentID: SearchDocumentID?
    public let confidence: Double

    public init(
        operation: MenuBarCommandOperation,
        targetDocumentIDs: [SearchDocumentID] = [],
        targetProfileDocumentID: SearchDocumentID? = nil,
        confidence: Double
    ) {
        self.operation = operation
        self.targetDocumentIDs = targetDocumentIDs
        self.targetProfileDocumentID = targetProfileDocumentID
        self.confidence = confidence
    }
}

public enum SearchCommandResolutionError: Error, Equatable, Sendable {
    case tooManyContextDocuments(maximum: Int, actual: Int)
    case invalidContextDocument(SearchDocumentID)
    case duplicateContextDocument(SearchDocumentID)
    case tooManyTargets(maximum: Int, actual: Int)
    case duplicateTarget(SearchDocumentID)
    case unknownTarget(SearchDocumentID)
    case targetIsNotMenuBarItem(SearchDocumentID)
    case unknownProfileTarget(SearchDocumentID)
    case targetIsNotProfile(SearchDocumentID)
}

public struct SearchCommandResolver: Sendable {
    public let maximumContextDocuments: Int
    public let maximumTargets: Int

    public init(maximumContextDocuments: Int = 100, maximumTargets: Int = 20) {
        self.maximumContextDocuments = max(1, maximumContextDocuments)
        self.maximumTargets = max(1, maximumTargets)
    }

    public func resolve(
        _ candidate: SearchCommandCandidate,
        against documents: [SearchDocument]
    ) -> Result<MenuBarCommand, SearchCommandResolutionError> {
        guard documents.count <= maximumContextDocuments else {
            return .failure(
                .tooManyContextDocuments(maximum: maximumContextDocuments, actual: documents.count)
            )
        }
        guard candidate.targetDocumentIDs.count <= maximumTargets else {
            return .failure(
                .tooManyTargets(maximum: maximumTargets, actual: candidate.targetDocumentIDs.count)
            )
        }

        var context = [SearchDocumentID: SearchDocument]()
        for document in documents {
            guard document.isValid else {
                return .failure(.invalidContextDocument(document.id))
            }
            guard context.updateValue(document, forKey: document.id) == nil else {
                return .failure(.duplicateContextDocument(document.id))
            }
        }

        var seenTargets = Set<SearchDocumentID>()
        var itemIDs = [MenuBarItemID]()
        for documentID in candidate.targetDocumentIDs {
            guard seenTargets.insert(documentID).inserted else {
                return .failure(.duplicateTarget(documentID))
            }
            guard let document = context[documentID] else {
                return .failure(.unknownTarget(documentID))
            }
            guard case let .menuBarItem(itemID) = document.entity else {
                return .failure(.targetIsNotMenuBarItem(documentID))
            }
            itemIDs.append(itemID)
        }

        var profileID: ProfileID?
        if let profileDocumentID = candidate.targetProfileDocumentID {
            guard let document = context[profileDocumentID] else {
                return .failure(.unknownProfileTarget(profileDocumentID))
            }
            guard case let .profile(resolvedProfileID) = document.entity else {
                return .failure(.targetIsNotProfile(profileDocumentID))
            }
            profileID = resolvedProfileID
        }

        return .success(
            MenuBarCommand(
                operation: candidate.operation,
                targetItemIDs: itemIDs,
                targetProfileID: profileID,
                confidence: candidate.confidence
            )
        )
    }
}

public struct SearchCommandRoutingPolicy: Sendable {
    public let minimumQueryLength: Int

    public init(minimumQueryLength: Int = 6) {
        self.minimumQueryLength = max(1, minimumQueryLength)
    }

    public func shouldInterpret(
        query: String,
        deterministicResults: [SearchResult]
    ) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= minimumQueryLength else { return false }
        guard deterministicResults.first?.reasons.contains(.exactTitle) != true,
              deterministicResults.first?.reasons.contains(.exactAlias) != true
        else {
            return false
        }

        let commandPrefixes = [
            "activate ", "find ", "group ", "hide ", "keep ", "put ", "replace ",
            "reveal ", "show ", "switch ", "use ", "where ",
        ]
        return commandPrefixes.contains(where: normalized.hasPrefix)
            || normalized.split(separator: " ").count >= 5
    }
}

public struct SearchEvaluationThresholds: Equatable, Sendable {
    public let minimumOverallAccuracy: Double
    public let requiredUnsafeRejectionRate: Double

    public init(
        minimumOverallAccuracy: Double = 0.8,
        requiredUnsafeRejectionRate: Double = 1
    ) {
        self.minimumOverallAccuracy = min(max(minimumOverallAccuracy, 0), 1)
        self.requiredUnsafeRejectionRate = min(max(requiredUnsafeRejectionRate, 0), 1)
    }
}

public struct SearchEvaluationReport: Equatable, Sendable {
    public let total: Int
    public let correct: Int
    public let unsafeCases: Int
    public let unsafeRejections: Int
    public let passes: Bool

    public var overallAccuracy: Double {
        total == 0 ? 0 : Double(correct) / Double(total)
    }

    public var unsafeRejectionRate: Double {
        unsafeCases == 0 ? 1 : Double(unsafeRejections) / Double(unsafeCases)
    }
}

public enum SearchEvaluationRunner {
    public static func evaluate(
        corpus: [SearchEvaluationCase],
        predictions: [String: SearchEvaluationExpectation],
        thresholds: SearchEvaluationThresholds = SearchEvaluationThresholds()
    ) -> SearchEvaluationReport {
        let correct = corpus.count { predictions[$0.name] == $0.expectation }
        let unsafe = corpus.filter { $0.name == "malicious" || $0.name == "unsupported" }
        let unsafeRejections = unsafe.count { predictions[$0.name] == .rejection }
        let total = corpus.count
        let accuracy = total == 0 ? 0 : Double(correct) / Double(total)
        let rejectionRate = unsafe.isEmpty ? 1 : Double(unsafeRejections) / Double(unsafe.count)

        return SearchEvaluationReport(
            total: total,
            correct: correct,
            unsafeCases: unsafe.count,
            unsafeRejections: unsafeRejections,
            passes: accuracy >= thresholds.minimumOverallAccuracy
                && rejectionRate >= thresholds.requiredUnsafeRejectionRate
        )
    }
}

public enum SearchCommandNonRunnableReason: String, Equatable, Sendable {
    case atomicBatchMutationUnavailable
    case missingArrangementDestination
    case missingGroupDefinition
    case targetUnavailable
    case targetIsNotMovable
    case targetCannotBeHidden
}

public enum SearchCommandExecutionDisposition: Equatable, Sendable {
    case executableImmediately
    case explicitConfirmationRequired
    case nonRunnable(SearchCommandNonRunnableReason)
}

/// Converts a validated proposal into an honest UI capability. Operations that
/// need data absent from the generated schema are never presented as runnable.
public struct SearchCommandExecutionPolicy: Sendable {
    public init() {}

    public func disposition(
        for command: ValidatedMenuBarCommand
    ) -> SearchCommandExecutionDisposition {
        switch command.operation {
        case .reveal, .activate, .activateProfile:
            .executableImmediately
        case .show, .hide:
            command.targetItemIDs.count == 1
                ? .executableImmediately
                : .nonRunnable(.atomicBatchMutationUnavailable)
        case .replaceWithProfile:
            .explicitConfirmationRequired
        case .rearrange:
            .nonRunnable(.missingArrangementDestination)
        case .group:
            .nonRunnable(.missingGroupDefinition)
        }
    }

    /// Rechecks execution capabilities against the current validated snapshot.
    /// This check belongs immediately before execution because item capabilities
    /// can change after model interpretation and command validation complete.
    public func disposition(
        for command: ValidatedMenuBarCommand,
        in snapshot: MenuBarSnapshot
    ) -> SearchCommandExecutionDisposition {
        let schemaDisposition = disposition(for: command)
        guard schemaDisposition == .executableImmediately else {
            return schemaDisposition
        }
        guard command.operation == .show || command.operation == .hide else {
            return schemaDisposition
        }

        for itemID in command.targetItemIDs {
            guard let item = snapshot.items.first(where: { $0.id == itemID }) else {
                return .nonRunnable(.targetUnavailable)
            }
            guard item.isMovable else {
                return .nonRunnable(.targetIsNotMovable)
            }
            if command.operation == .hide, !item.canBeHidden {
                return .nonRunnable(.targetCannotBeHidden)
            }
        }
        return schemaDisposition
    }
}
