//
//  ProfileValidation.swift
//  Barline
//

import Foundation

public enum ProfileValidationError: Error, Codable, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case emptyName
    case invalidTimestampOrder
    case unstableItemIdentity(MenuBarItemID)
    case duplicateItem(MenuBarItemID)
    case duplicateGroup(UUID)
    case emptyGroupName(UUID)
    case groupContainsUnknownItem(UUID, MenuBarItemID)
    case duplicateSpacer(UUID)
    case invalidSpacerWidth(UUID)
    case spacerReferencesUnknownItem(UUID, MenuBarItemID)
    case duplicateDisplay(MenuBarDisplayID)
    case emptyDisplayID
    case invalidDisplayFingerprint(MenuBarDisplayID)
    case invalidPresentationScope
    case invalidAppearance
    case unsupportedShelfBehavior
    case invalidAutoRehideDelay
    case invalidHotkey
    case duplicateProfile(UUID)
    case unsupportedArchiveVersion(Int)
    case emptyArchive
    case archiveTooLarge(Int)
    case archiveLimitExceeded(String)
    case malformedDocument(String)
}

public struct ProfileValidator: Sendable {
    public init() {}

    public func validate(_ profile: BarlineProfile) throws {
        guard profile.schemaVersion == ProfileSchema.currentVersion else {
            throw ProfileValidationError.unsupportedSchemaVersion(profile.schemaVersion)
        }
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileValidationError.emptyName
        }
        guard profile.createdAt <= profile.updatedAt else {
            throw ProfileValidationError.invalidTimestampOrder
        }
        try validateAppearance(profile.appearance)
        guard profile.autoRehide.delaySeconds.isFinite, profile.autoRehide.delaySeconds >= 0 else {
            throw ProfileValidationError.invalidAutoRehideDelay
        }
        guard profile.shelfBehavior.followsActiveDisplay else {
            throw ProfileValidationError.unsupportedShelfBehavior
        }
        if let hotkey = profile.hotkey {
            guard !hotkey.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !hotkey.modifiers.isEmpty
            else {
                throw ProfileValidationError.invalidHotkey
            }
        }

        try validateLayout(profile.layout, groups: profile.groups, spacers: profile.spacers)
        var displays = Set<MenuBarDisplayID>()
        for override in profile.displayOverrides {
            guard !override.displayID.value.isEmpty else { throw ProfileValidationError.emptyDisplayID }
            guard displays.insert(override.displayID).inserted else {
                throw ProfileValidationError.duplicateDisplay(override.displayID)
            }
            if let fingerprint = override.displayFingerprint,
               !fingerprint.isWellFormed
            {
                throw ProfileValidationError.invalidDisplayFingerprint(override.displayID)
            }
            try validateLayout(override.layout, groups: override.groups, spacers: override.spacers)
        }
    }

    public func validate(_ profiles: [BarlineProfile]) throws {
        guard !profiles.isEmpty else { throw ProfileValidationError.emptyArchive }
        var ids = Set<UUID>()
        for profile in profiles {
            guard ids.insert(profile.id).inserted else {
                throw ProfileValidationError.duplicateProfile(profile.id)
            }
            try validate(profile)
        }
    }

    public func validate(_ workspace: ProfileWorkspaceState) throws {
        try validateAppearance(workspace.appearance)
        guard workspace.autoRehide.delaySeconds.isFinite,
              workspace.autoRehide.delaySeconds >= 0
        else {
            throw ProfileValidationError.invalidAutoRehideDelay
        }
        guard workspace.shelfBehavior.followsActiveDisplay else {
            throw ProfileValidationError.unsupportedShelfBehavior
        }
        if let presentation = workspace.presentation {
            switch presentation.source {
            case .base:
                guard presentation.destinationDisplayID == nil else {
                    throw ProfileValidationError.invalidPresentationScope
                }
            case let .displayOverride(sourceDisplayID):
                guard !sourceDisplayID.value.isEmpty,
                      let destinationDisplayID = presentation.destinationDisplayID,
                      !destinationDisplayID.value.isEmpty
                else {
                    throw ProfileValidationError.invalidPresentationScope
                }
            }
            try validateLayout(
                presentation.layout,
                groups: presentation.groups,
                spacers: presentation.spacers
            )
        }
    }

    private func isValidHexColor(_ value: String) -> Bool {
        guard value.count == 7 || value.count == 9, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy(\.isHexDigit)
    }

    private func isValidAppearanceMode(_ mode: ProfileAppearanceMode) -> Bool {
        let hasGradient = !mode.gradientStops.isEmpty || !mode.gradientHex.isEmpty
        return !(mode.tintHex != nil && hasGradient)
            && mode.gradientHex.count <= 8
            && mode.gradientHex.allSatisfy {
                $0.count <= ProfileCodec.maximumStringLength && isValidHexColor($0)
            }
            && mode.gradientStops.count <= 8
            && mode.gradientHex == mode.gradientStops.map(\.colorHex)
            && mode.gradientStops.allSatisfy {
                $0.colorHex.count <= ProfileCodec.maximumStringLength
                    && isValidHexColor($0.colorHex)
                    && $0.location.isFinite
                    && (0 ... 1).contains($0.location)
            }
            && zip(mode.gradientStops, mode.gradientStops.dropFirst()).allSatisfy {
                $0.location <= $1.location
            }
            && (mode.tintHex.map {
                $0.count <= ProfileCodec.maximumStringLength && isValidHexColor($0)
            } ?? true)
            && mode.borderHex.count <= ProfileCodec.maximumStringLength
            && isValidHexColor(mode.borderHex)
            && mode.borderWidth.isFinite
            && (1 ... 3).contains(mode.borderWidth)
    }

    private func validateAppearance(_ appearance: ProfileAppearance) throws {
        guard appearance.itemSpacing.isFinite,
              ProfileAppearance.itemSpacingRange.contains(appearance.itemSpacing),
              appearance.itemSpacing.rounded() == appearance.itemSpacing,
              isValidAppearanceMode(
                  ProfileAppearanceMode(
                      tintHex: appearance.tintHex,
                      gradientHex: appearance.gradientHex,
                      gradientStops: appearance.gradientStops,
                      showsBorder: appearance.showsBorder,
                      borderHex: appearance.borderHex,
                      borderWidth: appearance.borderWidth,
                      showsShadow: appearance.showsShadow
                  )
              )
        else {
            throw ProfileValidationError.invalidAppearance
        }
        if let dynamicAppearance = appearance.dynamicAppearance {
            guard isValidAppearanceMode(dynamicAppearance.light),
                  isValidAppearanceMode(dynamicAppearance.dark)
            else {
                throw ProfileValidationError.invalidAppearance
            }
        } else if appearance.isDynamic {
            throw ProfileValidationError.invalidAppearance
        }
    }

    private func validateLayout(
        _ layout: ProfileLayout,
        groups: [ProfileGroup],
        spacers: [ProfileSpacer]
    ) throws {
        var known = Set<MenuBarItemID>()
        for itemID in layout.allItemIDs {
            guard itemID.isPlausiblyStable else {
                throw ProfileValidationError.unstableItemIdentity(itemID)
            }
            guard known.insert(itemID).inserted else {
                throw ProfileValidationError.duplicateItem(itemID)
            }
        }

        var groupIDs = Set<UUID>()
        for group in groups {
            guard groupIDs.insert(group.id).inserted else {
                throw ProfileValidationError.duplicateGroup(group.id)
            }
            guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProfileValidationError.emptyGroupName(group.id)
            }
            var members = Set<MenuBarItemID>()
            for itemID in group.itemIDs {
                guard known.contains(itemID), members.insert(itemID).inserted else {
                    throw ProfileValidationError.groupContainsUnknownItem(group.id, itemID)
                }
            }
        }

        var spacerIDs = Set<UUID>()
        for spacer in spacers {
            guard spacerIDs.insert(spacer.id).inserted else {
                throw ProfileValidationError.duplicateSpacer(spacer.id)
            }
            guard spacer.width.isFinite, (1 ... 160).contains(spacer.width) else {
                throw ProfileValidationError.invalidSpacerWidth(spacer.id)
            }
            if case let .after(itemID) = spacer.placement, !known.contains(itemID) {
                throw ProfileValidationError.spacerReferencesUnknownItem(spacer.id, itemID)
            }
        }
    }
}
