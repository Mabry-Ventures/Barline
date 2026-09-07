//
//  RulePowerReader.swift
//  Barline
//

import BarlineCore
import Foundation
import IOKit.ps

actor RulePowerReader {
    struct Sample: Equatable, Sendable {
        let source: LayoutRulePowerSource?
        let percent: Int?
    }

    func sample() -> Sample {
        guard let information = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return Sample(source: nil, percent: nil)
        }
        let type = IOPSGetProvidingPowerSourceType(information)?.takeUnretainedValue() as String?
        let source: LayoutRulePowerSource? = switch type {
        case kIOPSACPowerValue: .external
        case kIOPSBatteryPowerValue: .battery
        default: nil
        }
        let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let batteries = sources.compactMap { source -> [String: Any]? in
            guard let values = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue() as? [String: Any],
                  values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { return nil }
            return values
        }
        guard batteries.count == 1, let battery = batteries.first,
              let current = battery[kIOPSCurrentCapacityKey] as? Int,
              let maximum = battery[kIOPSMaxCapacityKey] as? Int,
              maximum > 0, (0 ... maximum).contains(current)
        else {
            return Sample(source: source, percent: nil)
        }
        return Sample(source: source, percent: Int(Double(current) / Double(maximum) * 100))
    }
}

/// A narrow main-run-loop notification bridge. Actual power reads stay in the actor.
@MainActor
final class RulePowerObservation {
    private var source: CFRunLoopSource?
    private let changed: @MainActor () -> Void

    init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<RulePowerObservation>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    var isAvailable: Bool {
        source != nil
    }

    isolated deinit {
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
    }
}
