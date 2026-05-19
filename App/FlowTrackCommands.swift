import SwiftUI

struct FlowTrackCommandContext {
    var isHelpModeEnabled: Bool
    var canZoomTimelineIn: Bool
    var canZoomTimelineOut: Bool
    var canResetTimelineZoom: Bool
    var canUsePlayback: Bool
    var canJumpToStart: Bool
    var canGoToPreviousMarker: Bool
    var canGoToNextMarker: Bool
    var canDeleteSelectedMarker: Bool
    var canDuplicateSelectedMarker: Bool
    var toggleHelpMode: () -> Void
    var zoomTimelineIn: () -> Void
    var zoomTimelineOut: () -> Void
    var resetTimelineZoom: () -> Void
    var togglePlayback: () -> Void
    var jumpToStart: () -> Void
    var goToPreviousMarker: () -> Void
    var goToNextMarker: () -> Void
    var deleteSelectedMarker: () -> Void
    var duplicateSelectedMarker: () -> Void
}

private struct FlowTrackCommandContextKey: FocusedValueKey {
    typealias Value = FlowTrackCommandContext
}

extension FocusedValues {
    var flowTrackCommandContext: FlowTrackCommandContext? {
        get { self[FlowTrackCommandContextKey.self] }
        set { self[FlowTrackCommandContextKey.self] = newValue }
    }
}

struct FlowTrackCommands: Commands {
    @FocusedValue(\.flowTrackCommandContext) private var commandContext

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom Timeline In") {
                commandContext?.zoomTimelineIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(commandContext?.canZoomTimelineIn != true)

            Button("Zoom Timeline Out") {
                commandContext?.zoomTimelineOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(commandContext?.canZoomTimelineOut != true)

            Button("Reset Timeline Zoom") {
                commandContext?.resetTimelineZoom()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
            .disabled(commandContext?.canResetTimelineZoom != true)

            Divider()

            Button(commandContext?.isHelpModeEnabled == true ? "Turn Help Mode Off" : "Turn Help Mode On") {
                commandContext?.toggleHelpMode()
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
            .disabled(commandContext == nil)
        }

        CommandMenu("Playback") {
            Button("Play/Pause") {
                commandContext?.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(commandContext?.canUsePlayback != true)

            Button("Jump to Start") {
                commandContext?.jumpToStart()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(commandContext?.canJumpToStart != true)
        }

        CommandMenu("Marker") {
            Button("Previous Marker") {
                commandContext?.goToPreviousMarker()
            }
            .keyboardShortcut(.leftArrow, modifiers: .option)
            .disabled(commandContext?.canGoToPreviousMarker != true)

            Button("Next Marker") {
                commandContext?.goToNextMarker()
            }
            .keyboardShortcut(.rightArrow, modifiers: .option)
            .disabled(commandContext?.canGoToNextMarker != true)

            Divider()

            Button("Delete Selected Marker") {
                commandContext?.deleteSelectedMarker()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(commandContext?.canDeleteSelectedMarker != true)

            Button("Duplicate Selected Marker") {
                commandContext?.duplicateSelectedMarker()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(commandContext?.canDuplicateSelectedMarker != true)
        }

        CommandGroup(after: .help) {
            Button(commandContext?.isHelpModeEnabled == true ? "Turn Help Mode Off" : "Turn Help Mode On") {
                commandContext?.toggleHelpMode()
            }
            .disabled(commandContext == nil)
        }
    }
}
