//
//  SnapshotValidationTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Stable identity and snapshot validation")
struct SnapshotValidationTests {
    private let displayID = MenuBarDisplayID("built-in")

    @Test("Identity normalization never depends on a window number")
    func stableIdentityNormalization() {
        let first = MenuBarItemID(
            bundleIdentifier: " COM.EXAMPLE.Tool ",
            accessibilityIdentifier: " Status.Item ",
            title: " Control "
        )
        let second = MenuBarItemID(
            bundleIdentifier: "com.example.tool",
            accessibilityIdentifier: "status.item",
            title: "control"
        )

        #expect(first == second)
        #expect(first.isPlausiblyStable)
        #expect(!first.description.contains("42"))
    }

    @Test("Empty transient snapshots cannot replace known-good state")
    func rejectsEmptySnapshot() {
        let validator = SnapshotValidator()
        let previous = snapshot(generation: 1, itemCount: 3)
        let candidate = snapshot(generation: 2, itemCount: 0)

        #expect(
            validator.validate(candidate, previous: previous, now: candidate.capturedAt)
                == .failure(.emptySnapshot)
        )
    }

    @Test("Implausible item-count collapse is rejected")
    func rejectsCollapse() {
        let validator = SnapshotValidator(
            policy: SnapshotValidationPolicy(maximumCollapseRatio: 0.5)
        )
        let previous = snapshot(generation: 1, itemCount: 10)
        let candidate = snapshot(generation: 2, itemCount: 4)

        #expect(
            validator.validate(candidate, previous: previous, now: candidate.capturedAt)
                == .failure(.implausibleItemCountCollapse(previous: 10, candidate: 4))
        )
    }

    @Test("Duplicate stable identities are rejected")
    func rejectsDuplicateIdentities() {
        let id = itemID(0)
        let candidate = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(),
            items: [
                descriptor(id: id, order: 0),
                descriptor(id: id, order: 1),
            ],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )

        #expect(
            SnapshotValidator().validate(
                candidate,
                previous: nil,
                now: candidate.capturedAt
            ) == .failure(.duplicateItemIdentity(id))
        )
    }

    @Test("Required Barline control items are enforced")
    func requiresControlItem() {
        let controlID = MenuBarItemID(
            bundleIdentifier: "com.mabryventures.barline",
            accessibilityIdentifier: "hidden-control"
        )
        let validator = SnapshotValidator(
            policy: SnapshotValidationPolicy(requiredControlItemIDs: [controlID])
        )
        let candidate = snapshot(generation: 1, itemCount: 2)

        #expect(
            validator.validate(candidate, previous: nil, now: candidate.capturedAt)
                == .failure(.missingRequiredControlItem(controlID))
        )
    }

    @Test("Display identity metadata must be complete, unique, and well-formed")
    func validatesDisplayIdentityMetadata() {
        let validFingerprint = MenuBarDisplayHardwareFingerprint(
            "v1:" + String(repeating: "a", count: 64)
        )
        let malformedFingerprint = MenuBarDisplayHardwareFingerprint("v1:short")
        let base = snapshot(generation: 1, itemCount: 1)
        let mismatch = MenuBarSnapshot(
            generation: base.generation,
            capturedAt: base.capturedAt,
            items: base.items,
            displayIDs: base.displayIDs,
            displayIdentities: [],
            activeSpaceIsValid: true
        )
        let duplicate = MenuBarSnapshot(
            generation: base.generation,
            capturedAt: base.capturedAt,
            items: base.items,
            displayIDs: base.displayIDs,
            displayIdentities: [
                MenuBarDisplayIdentity(runtimeID: displayID, hardwareFingerprint: validFingerprint),
                MenuBarDisplayIdentity(runtimeID: displayID, hardwareFingerprint: validFingerprint),
            ],
            activeSpaceIsValid: true
        )
        let malformed = MenuBarSnapshot(
            generation: base.generation,
            capturedAt: base.capturedAt,
            items: base.items,
            displayIDs: base.displayIDs,
            displayIdentities: [
                MenuBarDisplayIdentity(
                    runtimeID: displayID,
                    hardwareFingerprint: malformedFingerprint
                ),
            ],
            activeSpaceIsValid: true
        )

        #expect(SnapshotValidator().validate(
            mismatch,
            previous: nil,
            now: mismatch.capturedAt
        ) == .failure(.displayIdentitySetMismatch))
        #expect(SnapshotValidator().validate(
            duplicate,
            previous: nil,
            now: duplicate.capturedAt
        ) == .failure(.duplicateDisplayIdentity(displayID)))
        #expect(SnapshotValidator().validate(
            malformed,
            previous: nil,
            now: malformed.capturedAt
        ) == .failure(.malformedDisplayFingerprint))
    }

    @Test("Snapshots beyond the allowed future clock skew are rejected")
    func rejectsFutureTimestamp() {
        let validator = SnapshotValidator(
            policy: SnapshotValidationPolicy(maximumFutureClockSkew: 0.5)
        )
        let now = Date()
        let candidate = MenuBarSnapshot(
            generation: 1,
            capturedAt: now.addingTimeInterval(1),
            items: [descriptor(id: itemID(0), order: 0)],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )

        #expect(
            validator.validate(candidate, previous: nil, now: now)
                == .failure(.futureDatedSnapshot)
        )
    }

    @Test("Item display references must exist in snapshot geometry")
    func rejectsUnknownItemDisplay() {
        let unknown = MenuBarDisplayID("disconnected")
        let candidate = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(),
            items: [
                MenuBarItemDescriptor(
                    id: itemID(0),
                    section: .visible,
                    order: 0,
                    displayID: unknown
                ),
            ],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )

        #expect(
            SnapshotValidator().validate(candidate, previous: nil, now: candidate.capturedAt)
                == .failure(.unknownItemDisplay(unknown))
        )
    }

    @Test("Missing geometry and invalid active space fail closed")
    func rejectsMissingGeometryAndInvalidSpace() {
        let missingGeometry = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(),
            items: [descriptor(id: itemID(0), order: 0)],
            displayIDs: [],
            activeSpaceIsValid: true
        )
        let invalidSpace = MenuBarSnapshot(
            generation: 1,
            capturedAt: missingGeometry.capturedAt,
            items: [descriptor(id: itemID(0), order: 0)],
            displayIDs: [displayID],
            activeSpaceIsValid: false
        )

        #expect(
            SnapshotValidator().validate(
                missingGeometry,
                previous: nil,
                now: missingGeometry.capturedAt
            ) == .failure(.missingDisplayGeometry)
        )
        #expect(
            SnapshotValidator().validate(
                invalidSpace,
                previous: nil,
                now: invalidSpace.capturedAt
            ) == .failure(.invalidActiveSpace)
        )
    }

    @Test("Stale snapshots and unstable identities fail closed")
    func rejectsStaleAndUnstableSnapshot() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let stale = MenuBarSnapshot(
            generation: 1,
            capturedAt: capturedAt,
            items: [descriptor(id: itemID(0), order: 0)],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        let unstableID = MenuBarItemID(bundleIdentifier: "")
        let unstable = MenuBarSnapshot(
            generation: 1,
            capturedAt: capturedAt,
            items: [descriptor(id: unstableID, order: 0)],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )

        #expect(
            SnapshotValidator(
                policy: SnapshotValidationPolicy(maximumAge: 1)
            ).validate(stale, previous: nil, now: capturedAt.addingTimeInterval(2))
                == .failure(.staleSnapshot)
        )
        #expect(
            SnapshotValidator().validate(unstable, previous: nil, now: capturedAt)
                == .failure(.unstableItemIdentity(unstableID))
        )
    }

    @Test("Snapshot generations must advance monotonically")
    func rejectsNonMonotonicGeneration() {
        let previous = snapshot(generation: 4, itemCount: 2)
        let candidate = MenuBarSnapshot(
            generation: 4,
            capturedAt: previous.capturedAt,
            items: previous.items,
            displayIDs: previous.displayIDs,
            activeSpaceIsValid: true
        )

        #expect(
            SnapshotValidator().validate(candidate, previous: previous, now: candidate.capturedAt)
                == .failure(.nonMonotonicGeneration(previous: 4, candidate: 4))
        )
    }

    @Test("System-item continuity is enforced independently of total item count")
    func rejectsSystemItemCollapse() {
        let systemItems = (0 ..< 4).map { index in
            MenuBarItemDescriptor(
                id: itemID(index),
                section: .visible,
                order: index,
                displayID: displayID,
                isSystemItem: true
            )
        }
        let ordinaryItems = (4 ..< 10).map { descriptor(id: itemID($0), order: $0) }
        let capturedAt = Date()
        let previous = MenuBarSnapshot(
            generation: 1,
            capturedAt: capturedAt,
            items: systemItems + ordinaryItems,
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        let candidate = MenuBarSnapshot(
            generation: 2,
            capturedAt: capturedAt,
            items: [systemItems[0]] + ordinaryItems,
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        let validator = SnapshotValidator(
            policy: SnapshotValidationPolicy(
                maximumCollapseRatio: 0.9,
                maximumSystemItemCollapseRatio: 0.5
            )
        )

        #expect(
            validator.validate(candidate, previous: previous, now: capturedAt)
                == .failure(.implausibleSystemItemCollapse(previous: 4, candidate: 1))
        )
    }

    @Test("Explicit empty-snapshot policy and present controls are accepted")
    func acceptsExplicitPolicyExceptions() {
        let empty = snapshot(generation: 1, itemCount: 0)
        let controlID = itemID(9)
        let withControl = MenuBarSnapshot(
            generation: 1,
            capturedAt: empty.capturedAt,
            items: [
                MenuBarItemDescriptor(
                    id: controlID,
                    section: .visible,
                    order: 0,
                    displayID: displayID,
                    isBarlineControlItem: true
                ),
            ],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )

        #expect(
            SnapshotValidator(
                policy: SnapshotValidationPolicy(allowsEmptySnapshot: true)
            ).validate(empty, previous: nil, now: empty.capturedAt) == .success(empty)
        )
        #expect(
            SnapshotValidator(
                policy: SnapshotValidationPolicy(requiredControlItemIDs: [controlID])
            ).validate(withControl, previous: nil, now: withControl.capturedAt) == .success(withControl)
        )
    }

    private func snapshot(generation: UInt64, itemCount: Int) -> MenuBarSnapshot {
        MenuBarSnapshot(
            generation: generation,
            capturedAt: Date(),
            items: (0 ..< itemCount).map { descriptor(id: itemID($0), order: $0) },
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
    }

    private func itemID(_ index: Int) -> MenuBarItemID {
        MenuBarItemID(
            bundleIdentifier: "com.example.tool\(index)",
            accessibilityIdentifier: "status-item-\(index)"
        )
    }

    private func descriptor(id: MenuBarItemID, order: Int) -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(
            id: id,
            section: .visible,
            order: order,
            displayID: displayID
        )
    }
}
