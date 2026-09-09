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

    @Test("Late source ownership resolution does not masquerade as inventory loss")
    func acceptsSourceOwnershipRefinement() {
        let capturedAt = Date()
        let previous = ownershipSnapshot(
            generation: 1,
            ownership: Array(repeating: .unknown, count: 15),
            capturedAt: capturedAt,
            legacySystemFlag: true
        )
        let candidate = ownershipSnapshot(
            generation: 2,
            ownership: Array(repeating: .system, count: 4) + Array(repeating: .application, count: 11),
            capturedAt: capturedAt
        )
        #expect(previous.items.allSatisfy { !$0.isConfirmedSystemItem })
        #expect(SnapshotValidator().validate(candidate, previous: previous, now: capturedAt) == .success(candidate))
        let unresolvedAgain = ownershipSnapshot(
            generation: 3,
            ownership: Array(repeating: .unknown, count: 15),
            capturedAt: capturedAt
        )
        #expect(SnapshotValidator().validate(
            unresolvedAgain, previous: candidate, now: capturedAt
        ) == .success(unresolvedAgain))
    }

    @Test("Refining a legacy host-system classification preserves the accepted inventory")
    func acceptsLegacyClassificationCorrection() {
        let capturedAt = Date()
        let previous = ownershipSnapshot(
            generation: 1,
            ownership: Array(repeating: nil, count: 15),
            capturedAt: capturedAt,
            legacySystemFlag: true
        )
        let candidate = ownershipSnapshot(
            generation: 2,
            ownership: Array(repeating: .system, count: 4) + Array(repeating: .application, count: 11),
            capturedAt: capturedAt
        )
        #expect(SnapshotValidator().validate(candidate, previous: previous, now: capturedAt) == .success(candidate))
    }

    @Test("Unrelated new system items cannot disguise loss of confirmed system identities")
    func rejectsReplacementSystemInventory() {
        let capturedAt = Date()
        let previous = ownershipSnapshot(
            generation: 1, ownership: Array(repeating: .system, count: 4), capturedAt: capturedAt
        )
        let candidate = MenuBarSnapshot(
            generation: 2,
            capturedAt: capturedAt,
            items: (10 ..< 14).map {
                MenuBarItemDescriptor(id: itemID($0), section: .visible, order: $0, sourceOwnership: .system)
            },
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        #expect(SnapshotValidator().validate(candidate, previous: previous, now: capturedAt)
            == .failure(.implausibleSystemItemCollapse(previous: 4, candidate: 0)))
    }

    @Test("Legacy descriptors decode without explicit ownership")
    func decodesLegacyOwnership() throws {
        let descriptor = descriptor(id: itemID(0), order: 0)
        let encoded = try JSONEncoder().encode(descriptor)
        #expect(try #require(String(data: encoded, encoding: .utf8)).contains("sourceOwnership") == false)
        let decoded = try JSONDecoder().decode(MenuBarItemDescriptor.self, from: encoded)
        #expect(decoded.sourceOwnership == nil)
        #expect(decoded == descriptor)
    }

    @Test("Unknown scenes, native menus, and custom interfaces all defer mutations")
    func menuTrackingDeferral() {
        #expect(!MenuBarTrackingPolicy.isTransientInterface(role: "AXWindow", subrole: "AXFloatingWindow"))
        #expect(MenuBarTrackingPolicy.isTransientInterface(role: "AXMenu", subrole: nil))
        #expect(MenuBarTrackingPolicy.isTransientInterface(role: "AXPopover", subrole: nil))
        #expect(MenuBarTrackingPolicy.isTransientInterface(role: "AXWindow", subrole: "AXPopover"))
        for sceneIsAvailable in [false, true] {
            for nativeMenu in [false, true] {
                for sourceInterface in [false, true] {
                    #expect(MenuBarTrackingPolicy.blocksMutation(
                        sceneIsAvailable: sceneIsAvailable,
                        nativeMenuIsVisible: nativeMenu,
                        sourceInterfaceIsVisible: sourceInterface
                    ) == (!sceneIsAvailable || nativeMenu || sourceInterface))
                }
            }
        }
    }

    @Test("Old saved-layout IDs reconnect through unique source and semantic identity")
    func reconnectsLegacySavedLayout() throws {
        let legacyID = MenuBarItemID(
            bundleIdentifier: "com.example.utility",
            title: "status",
            fallbackFingerprint: "Control Center:status:25"
        )
        let hostedID = MenuBarItemID(
            bundleIdentifier: "barline.hosted-menu-item",
            title: "status",
            fallbackFingerprint: "Control Center:status:25"
        )
        let snapshot = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(),
            items: [
                MenuBarItemDescriptor(
                    id: hostedID,
                    section: .hidden,
                    order: 0,
                    sourceOwnership: .application,
                    tagNamespace: "com.example.utility"
                ),
            ],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        let profile = BarlineProfile(
            name: "Saved before upgrade",
            layout: ProfileLayout(hidden: [legacyID]),
            groups: [ProfileGroup(name: "Group", itemIDs: [legacyID])],
            spacers: [ProfileSpacer(placement: .after(legacyID))]
        )
        let stored = profile.resolvedPresentation(for: nil)
        let resolved = try stored.resolvingItemIdentities(in: snapshot)
        #expect(resolved.layout.hidden == [hostedID])
        #expect(resolved.groups[0].itemIDs == [hostedID])
        #expect(resolved.spacers[0].placement == .after(hostedID))
        #expect(profile.layout.hidden == [legacyID])
        #expect(DisplayProfileOverrideResolver().resolvePersistedPresentation(
            profile: profile, persisted: stored, snapshot: snapshot
        ) == resolved)
        #expect(DisplayProfileOverrideResolver().resolvePersistedPresentation(
            profile: profile, persisted: resolved, snapshot: snapshot
        ) == resolved)
    }

    @Test("Legacy migration never guesses between identical hosted items")
    func rejectsAmbiguousLegacyItems() {
        let legacyID = MenuBarItemID(
            bundleIdentifier: "com.example.utility",
            title: "status",
            fallbackFingerprint: "Control Center:status:25"
        )
        let candidates = (0 ..< 2).map { index in
            MenuBarItemDescriptor(
                id: MenuBarItemID(
                    bundleIdentifier: "barline.hosted-menu-item",
                    title: "status",
                    alias: "occurrence-\(index)",
                    fallbackFingerprint: legacyID.fallbackFingerprint
                ),
                section: .visible,
                order: index,
                sourceOwnership: .application,
                tagNamespace: "com.example.utility"
            )
        }
        let snapshot = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(),
            items: candidates,
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        #expect(snapshot.resolvedItemID(for: legacyID) == nil)
        let presentation = BarlineProfile(name: "Ambiguous", layout: ProfileLayout(visible: [legacyID]))
            .resolvedPresentation(for: nil)
        #expect(throws: MenuBarBackendError.staleItem(legacyID)) {
            try presentation.resolvingItemIdentities(in: snapshot)
        }
    }

    private func ownershipSnapshot(
        generation: UInt64,
        ownership: [MenuBarSourceOwnership?],
        capturedAt: Date,
        legacySystemFlag: Bool = false
    ) -> MenuBarSnapshot {
        MenuBarSnapshot(
            generation: generation,
            capturedAt: capturedAt,
            items: ownership.enumerated().map { index, ownership in
                MenuBarItemDescriptor(
                    id: itemID(index),
                    section: .visible,
                    order: index,
                    isSystemItem: legacySystemFlag || ownership == .system,
                    sourceOwnership: ownership
                )
            },
            displayIDs: [displayID],
            activeSpaceIsValid: true
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
