//
//  ShelfGroupPresentationTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Shelf group presentation")
struct ShelfGroupPresentationTests {
    private let a = MenuBarItemID(bundleIdentifier: "fixture.a")
    private let b = MenuBarItemID(bundleIdentifier: "fixture.b")
    private let c = MenuBarItemID(bundleIdentifier: "fixture.c")
    private let d = MenuBarItemID(bundleIdentifier: "fixture.d")

    private func presentation(
        groups: [ProfileGroup],
        hidden: [MenuBarItemID],
        visible: [MenuBarItemID] = [],
        spacers: [ProfileSpacer] = []
    ) -> ResolvedProfilePresentation {
        ResolvedProfilePresentation(
            source: .base,
            destinationDisplayID: nil,
            layout: ProfileLayout(visible: visible, hidden: hidden),
            groups: groups,
            spacers: spacers
        )
    }

    private func itemIDs(_ elements: [ProfilePresentationElement]) -> [MenuBarItemID] {
        elements.compactMap {
            if case let .item(id) = $0 {
                id
            } else {
                nil
            }
        }
    }

    @Test("Expansion preserves source order and collapse removes only valid members")
    func expandsAndCollapsesWithoutReordering() {
        let group = ProfileGroup(name: "Tools", symbol: "folder", itemIDs: [b, a])
        let source = presentation(groups: [group], hidden: [a, b, c])
        let expanded = ShelfGroupPresentation.elements(presentation: source, section: .hidden, orderedItemIDs: [a, b, c])
        #expect(expanded == [.groupMarker(id: group.id, name: "Tools", symbol: "folder"), .item(a), .item(b), .item(c)])
        let collapsed = ShelfGroupPresentation.elements(
            presentation: source,
            section: .hidden,
            orderedItemIDs: [a, b, c],
            collapsedGroupIDs: [group.id]
        )
        #expect(collapsed == [.groupMarker(id: group.id, name: "Tools", symbol: "folder"), .item(c)])
        #expect(source.groups[0].itemIDs == [b, a])
        #expect(itemIDs(expanded) == [a, b, c])
    }

    @Test("Overlapping groups both fail open to accessible ungrouped items")
    func overlap() {
        let first = ProfileGroup(name: "First", itemIDs: [a, b])
        let second = ProfileGroup(name: "Second", itemIDs: [b, c])
        let elements = ShelfGroupPresentation.elements(
            presentation: presentation(groups: [first, second], hidden: [a, b, c]),
            section: .hidden,
            orderedItemIDs: [a, b, c],
            collapsedGroupIDs: [first.id, second.id]
        )
        #expect(elements == [.item(a), .item(b), .item(c)])
    }

    @Test("Malformed overlap does not permit the otherwise valid group to hide an ambiguous member")
    func overlapWithMissingMember() {
        let first = ProfileGroup(name: "First", itemIDs: [a, b])
        let second = ProfileGroup(name: "Second", itemIDs: [b, d])
        #expect(ShelfGroupPresentation.elements(
            presentation: presentation(groups: [first, second], hidden: [a, b, c]),
            section: .hidden,
            orderedItemIDs: [a, b, c],
            collapsedGroupIDs: [first.id, second.id]
        ) == [.item(a), .item(b), .item(c)])
    }

    @Test("Cross-section and missing members remain accessible rather than partially grouped")
    func crossSectionOrMissing() {
        let group = ProfileGroup(name: "Mixed", itemIDs: [a, b])
        let source = presentation(groups: [group], hidden: [a], visible: [b])
        #expect(ShelfGroupPresentation.elements(
            presentation: source,
            section: .hidden,
            orderedItemIDs: [a],
            collapsedGroupIDs: [group.id]
        ) == [.item(a)])
        #expect(ShelfGroupPresentation.elements(
            presentation: source,
            section: .visible,
            orderedItemIDs: [b],
            collapsedGroupIDs: [group.id]
        ) == [.item(b)])
        #expect(ShelfGroupPresentation.elements(
            presentation: presentation(groups: [group], hidden: [a, b]),
            section: .hidden,
            orderedItemIDs: [a],
            collapsedGroupIDs: [group.id]
        ) == [.item(a)])
    }

    @Test("Interleaved membership cannot reorder or hide unrelated source items")
    func noncontiguousMembers() {
        let group = ProfileGroup(name: "Interleaved", itemIDs: [a, c])
        #expect(ShelfGroupPresentation.elements(
            presentation: presentation(groups: [group], hidden: [a, b, c]),
            section: .hidden,
            orderedItemIDs: [a, b, c],
            collapsedGroupIDs: [group.id]
        ) == [.item(a), .item(b), .item(c)])
    }

    @Test("Duplicate group IDs or members never create duplicate disclosures or hide items")
    func malformedDuplicates() {
        let first = ProfileGroup(name: "First", itemIDs: [a])
        let duplicateID = ProfileGroup(id: first.id, name: "Second", itemIDs: [b])
        let duplicateMember = ProfileGroup(name: "Repeated", itemIDs: [c, c])
        #expect(ShelfGroupPresentation.elements(
            presentation: presentation(groups: [first, duplicateID, duplicateMember], hidden: [a, b, c]),
            section: .hidden,
            orderedItemIDs: [a, b, c],
            collapsedGroupIDs: [first.id, duplicateMember.id]
        ) == [.item(a), .item(b), .item(c)])
    }

    @Test("Duplicate source or layout identity stays accessible and is never collapsible")
    func ambiguousItemIdentity() {
        let group = ProfileGroup(name: "Ambiguous", itemIDs: [a])
        let source = presentation(groups: [group], hidden: [a, b])
        #expect(ShelfGroupPresentation.elements(
            presentation: source,
            section: .hidden,
            orderedItemIDs: [a, a, b],
            collapsedGroupIDs: [group.id]
        ) == [.item(a), .item(b)])
        #expect(ShelfGroupPresentation.elements(
            presentation: presentation(groups: [group], hidden: [a, b], visible: [a]),
            section: .hidden,
            orderedItemIDs: [a, b],
            collapsedGroupIDs: [group.id]
        ) == [.item(a), .item(b)])
    }

    @Test("Multiple disjoint groups collapse independently and ignore stale expansion IDs")
    func independentGroups() {
        let first = ProfileGroup(name: "First", itemIDs: [a, b])
        let second = ProfileGroup(name: "Second", itemIDs: [c, d])
        let source = presentation(groups: [first, second], hidden: [a, b, c, d])
        let elements = ShelfGroupPresentation.elements(
            presentation: source,
            section: .hidden,
            orderedItemIDs: [a, b, c, d],
            collapsedGroupIDs: [first.id, UUID()]
        )
        #expect(itemIDs(elements) == [c, d])
        #expect(elements.count == 4)
        #expect(itemIDs(ShelfGroupPresentation.elements(
            presentation: source,
            section: .hidden,
            orderedItemIDs: [a, b, c, d]
        )) == [a, b, c, d])
    }

    @Test("Only spacers anchored to collapsed members disappear")
    func spacerPreservation() {
        let group = ProfileGroup(name: "Tools", itemIDs: [a, b])
        let beginning = ProfileSpacer(placement: .beginning(.hidden), width: 4)
        let inside = ProfileSpacer(placement: .after(a), width: 8)
        let outside = ProfileSpacer(placement: .after(c), width: 12)
        let end = ProfileSpacer(placement: .end(.hidden), width: 16)
        let elements = ShelfGroupPresentation.elements(
            presentation: presentation(groups: [group], hidden: [a, b, c], spacers: [beginning, inside, outside, end]),
            section: .hidden,
            orderedItemIDs: [a, b, c],
            collapsedGroupIDs: [group.id]
        )
        #expect(elements == [
            .spacer(id: beginning.id, width: 4),
            .groupMarker(id: group.id, name: "Tools", symbol: nil),
            .item(c),
            .spacer(id: outside.id, width: 12),
            .spacer(id: end.id, width: 16),
        ])
    }

    @Test("No presentation, empty groups and unnamed groups preserve item access")
    func noUsableGroups() {
        #expect(ShelfGroupPresentation.elements(presentation: nil, section: .hidden, orderedItemIDs: [a, b]) == [.item(a), .item(b)])
        let empty = ProfileGroup(name: "Empty", itemIDs: [])
        let unnamed = ProfileGroup(name: "  ", itemIDs: [a])
        #expect(ShelfGroupPresentation.elements(
            presentation: presentation(groups: [empty, unnamed], hidden: [a, b]),
            section: .hidden,
            orderedItemIDs: [a, b],
            collapsedGroupIDs: [empty.id, unnamed.id]
        ) == [.item(a), .item(b)])
    }
}
