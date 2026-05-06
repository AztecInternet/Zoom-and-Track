import AppKit
import AVKit
import SwiftUI

struct PlaybackVideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.controlsStyle = .none
        nsView.videoGravity = .resizeAspect
    }
}

struct PlaybackVideoLayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.player = player
    }
}

final class PlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

struct PrecisionTimeField: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let action: (Double) -> Void
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(value: value, range: range, action: action, onBeginEditing: onBeginEditing, onEndEditing: onEndEditing)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .right
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        textField.formatter = nil
        textField.stringValue = context.coordinator.displayString(for: value)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.range = range
        context.coordinator.action = action
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onEndEditing = onEndEditing

        if !context.coordinator.isEditing {
            nsView.stringValue = context.coordinator.displayString(for: value)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var originalValue: Double
        var range: ClosedRange<Double>
        var action: (Double) -> Void
        var onBeginEditing: () -> Void
        var onEndEditing: () -> Void
        var isEditing = false

        init(
            value: Double,
            range: ClosedRange<Double>,
            action: @escaping (Double) -> Void,
            onBeginEditing: @escaping () -> Void,
            onEndEditing: @escaping () -> Void
        ) {
            self.originalValue = value
            self.range = range
            self.action = action
            self.onBeginEditing = onBeginEditing
            self.onEndEditing = onEndEditing
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            onBeginEditing()
            if let textField = obj.object as? NSTextField {
                originalValue = parsedValue(from: textField.stringValue) ?? originalValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commit(from: control)
                control.window?.makeFirstResponder(nil)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancel(on: control)
                control.window?.makeFirstResponder(nil)
                return true
            }

            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            commit(from: textField)
            isEditing = false
            onEndEditing()
        }

        private func commit(from control: NSControl) {
            guard let textField = control as? NSTextField else { return }
            let parsed = parsedValue(from: textField.stringValue) ?? originalValue
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            textField.stringValue = displayString(for: clamped)
            originalValue = clamped
            action(clamped)
        }

        private func cancel(on control: NSControl) {
            guard let textField = control as? NSTextField else { return }
            textField.stringValue = displayString(for: originalValue)
            isEditing = false
        }

        func displayString(for value: Double) -> String {
            String(format: "%.2f", value)
        }

        private func parsedValue(from string: String) -> Double? {
            let cleaned = string.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
    }
}
