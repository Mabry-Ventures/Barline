//
//  SearchRuntimeAvailability.swift
//  Barline
//

import BarlineCore
import CoreSpotlight
import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Performs capability probes without creating a language-model session. Search
/// callers must always run the deterministic index before consulting this plan.
enum SearchRuntimeAvailability {
    static func current(locale: Locale = .current) -> SearchAvailability {
        let coreSpotlight: SearchCapabilityAvailability = CSSearchableIndex.isIndexingAvailable()
            ? .available
            : .unavailable(.apiUnavailable)
        let foundationModels = foundationModelsAvailability(locale: locale)

        return SearchAvailability(
            coreSpotlight: coreSpotlight,
            foundationModels: foundationModels,
            spotlightSearchTool: spotlightSearchToolAvailability(
                coreSpotlight: coreSpotlight,
                foundationModels: foundationModels
            )
        )
    }

    private static func foundationModelsAvailability(
        locale: Locale
    ) -> SearchCapabilityAvailability {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *) else {
                return .unavailable(.unsupportedOperatingSystem)
            }

            let model = SystemLanguageModel.default
            guard model.supportsLocale(locale) else {
                return .unavailable(.unsupportedLanguage)
            }
            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(.unsupportedHardware)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(.disabled)
            case .unavailable(.modelNotReady):
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.apiUnavailable)
            }
        #else
            return .unavailable(.apiUnavailable)
        #endif
    }

    private static func spotlightSearchToolAvailability(
        coreSpotlight: SearchCapabilityAvailability,
        foundationModels: SearchCapabilityAvailability
    ) -> SearchCapabilityAvailability {
        guard coreSpotlight.isAvailable, foundationModels.isAvailable else {
            return .unavailable(.apiUnavailable)
        }

        // Xcode 26 cannot name the macOS 27 SpotlightSearchTool symbol. The
        // compiler branch becomes active only when building with the macOS 27
        // toolchain, while the runtime check prevents use on older hosts.
        #if compiler(>=6.4)
            if #available(macOS 27.0, *) {
                return .available
            }
            return .unavailable(.unsupportedOperatingSystem)
        #else
            return .unavailable(.apiUnavailable)
        #endif
    }
}
