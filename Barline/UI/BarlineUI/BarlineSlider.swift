//
//  BarlineSlider.swift
//  Barline
//

import CompactSlider
import SwiftUI

struct BarlineSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    @Binding private var value: Value

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        _value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil
    ) where ValueLabel == Text {
        _value = value
        self.bounds = bounds
        self.step = step
        valueLabel = Text(valueLabelKey)
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var height: CGFloat {
        if #available(macOS 26.0, *) {
            24
        } else {
            22
        }
    }

    var body: some View {
        // CompactSlider 2 builds its content from style components instead of a
        // trailing closure: the handle, progress fill, and label are supplied
        // through modifiers. Haptic feedback is opt-in, so the previous
        // explicit disable is no longer required.
        CompactSlider(value: $value, in: bounds, step: step ?? 0)
            .compactSliderHandleStyle(.hidden())
            .compactSliderOptionsByRemoving(.scrollWheel)
            .compactSliderProgress { _ in
                Rectangle().fill(Color.accentColor.opacity(0.5))
            }
            .overlay {
                valueLabel
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
            .frame(height: height)
            .clipShape(borderShape)
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
