//
//  HotkeyRecorder.swift
//  Barline
//

import Combine
import SwiftUI

// MARK: - HotkeyRecorder

struct HotkeyRecorder<Label: View>: View {
    @StateObject private var model: HotkeyRecorderModel

    private let label: Label

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        _model = StateObject(wrappedValue: HotkeyRecorderModel(hotkey: hotkey))
        self.label = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                segmentStack
            } label: {
                label
            }
            if let message = model.hotkey.registrationError {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.hotkey.isSaving)
        .onDisappear { model.stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in model.stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.stopRecording() }
    }

    private var segmentStack: some View {
        HStack(spacing: 1) {
            leadingSegment
            trailingSegment
        }
        .frame(width: 132, height: 24)
    }

    private var leadingSegment: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else {
                model.startRecording()
            }
        } label: {
            leadingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderButtonStyle(
                segment: .leading,
                isHighlighted: model.isRecording
            )
        )
    }

    private var trailingSegment: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.hotkey.keyCombination != nil {
                Task { await model.hotkey.requestChange(nil) }
            } else {
                model.startRecording()
            }
        } label: {
            trailingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderButtonStyle(
                segment: .trailing,
                isHighlighted: false
            )
        )
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var leadingSegmentLabel: some View {
        if model.isRecording {
            Text("Type Hotkey")
        } else if model.hotkey.keyCombination != nil {
            if let keyCombination = model.hotkey.keyCombination {
                Text(keyCombination.displayValue)
            } else {
                Text("ERROR")
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var trailingSegmentLabel: some View {
        let (name, label, padding) = if model.isRecording {
            ("escape", "Cancel", 6.0)
        } else if model.hotkey.keyCombination != nil {
            ("xmark", "Clear", 7.5)
        } else {
            ("record.circle", "Record", 5.5)
        }
        Image(systemName: name)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .padding(padding)
            .accessibilityLabel(label)
    }
}

// MARK: - HotkeyRecorderModel

@MainActor
private final class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    private var recordingToken: UUID?

    let hotkey: Hotkey

    private lazy var monitor = EventMonitor.local(for: .keyDown) { [weak self] event in
        guard let self else {
            return event
        }
        handleKeyDown(event: event)
        return nil
    }

    private var cancellables = Set<AnyCancellable>()

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        hotkey.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    func startRecording() {
        guard !isRecording else {
            return
        }
        recordingToken = hotkey.beginRecording()
        monitor.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else {
            return
        }
        monitor.stop()
        if let recordingToken {
            hotkey.endRecording(recordingToken)
        }
        recordingToken = nil
        isRecording = false
    }

    private func handleKeyDown(event: NSEvent) {
        guard !event.isARepeat, !hotkey.isSaving else { return }
        let keyCombination = KeyCombination(event: event)
        guard !keyCombination.modifiers.isEmpty else {
            if keyCombination.key == .escape {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return
        }
        guard keyCombination.modifiers != .shift else {
            NSSound.beep()
            return
        }
        monitor.stop()
        Task {
            _ = await hotkey.requestChange(keyCombination)
            stopRecording()
        }
    }
}

// MARK: - HotkeyRecorderButtonStyle

private struct HotkeyRecorderButtonStyle: ButtonStyle {
    enum Segment {
        case leading
        case trailing
    }

    var segment: Segment
    var isHighlighted: Bool

    private var radii: RectangleCornerRadii {
        let r: CGFloat = if #available(macOS 26.0, *) {
            6
        } else {
            5
        }
        return switch segment {
        case .leading: RectangleCornerRadii(topLeading: r, bottomLeading: r)
        case .trailing: RectangleCornerRadii(bottomTrailing: r, topTrailing: r)
        }
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        } else {
            UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let isProminent = configuration.isPressed != isHighlighted
        borderShape
            .fill(isProminent ? .tertiary : .quaternary)
            .opacity(isProminent ? 0.5 : 0.75)
            .overlay {
                configuration.label
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
