import SwiftUI

struct TimelineToolbarView: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let hasSelectedMarker: Bool
    let canEditClickFocusMarkers: Bool
    let isPlacingClickFocus: Bool
    let selectedMarker: ZoomPlanItem?
    let showsNoZoomFallbackControls: Bool
    let isDrawingNoZoomOverflowRegion: Bool
    let isTimelineScrubSnappingEnabled: Bool
    let onToggleAddClickFocus: () -> Void
    let onDeleteSelectedMarker: () -> Void
    let onSelectNoZoomFallbackMode: (NoZoomFallbackMode) -> Void
    let onToggleOverflowRegion: () -> Void
    let onToggleTimelineScrubSnapping: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("markers")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(flowTrackTheme.controlStripText)

            if !hasSelectedMarker || isPlacingClickFocus {
                TimelineGadgetButton(
                    systemName: isPlacingClickFocus ? "xmark" : "plus",
                    isActive: isPlacingClickFocus,
                    isEnabled: canEditClickFocusMarkers || isPlacingClickFocus,
                    help: isPlacingClickFocus ? "Cancel Add Click Focus" : "Add Click Focus",
                    action: onToggleAddClickFocus
                )
            }

            if hasSelectedMarker {
                TimelineGadgetButton(
                    systemName: "minus",
                    isActive: false,
                    isEnabled: true,
                    help: "Delete Selected Marker",
                    action: onDeleteSelectedMarker
                )
            }

            if showsNoZoomFallbackControls, let selectedMarker {
                Divider()
                    .frame(height: 14)

                Text("overflow")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(flowTrackTheme.controlStripText)

                HStack(spacing: 2) {
                    ForEach(NoZoomFallbackMode.allCases) { mode in
                        Button {
                            onSelectNoZoomFallbackMode(mode)
                        } label: {
                            Text(mode.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(segmentedPillTextColor(isSelected: selectedMarker.noZoomFallbackMode == mode, theme: flowTrackTheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(segmentedPillBackgroundColor(isSelected: selectedMarker.noZoomFallbackMode == mode, theme: flowTrackTheme))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("No Zoom Overflow: \(mode.displayName)")
                    }
                }
                .padding(2)
                .background(
                    Capsule(style: .continuous)
                        .fill(flowTrackTheme.controlStripBackground)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(flowTrackTheme.controlStripBorder, lineWidth: 1)
                )

                if selectedMarker.noZoomFallbackMode == .scale {
                    Divider()
                        .frame(height: 14)

                    Text("region")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(flowTrackTheme.controlStripText)

                    TimelineGadgetButton(
                        systemName: isDrawingNoZoomOverflowRegion ? "checkmark" : "viewfinder.rectangular",
                        isActive: isDrawingNoZoomOverflowRegion,
                        isEnabled: true,
                        help: isDrawingNoZoomOverflowRegion ? "Save Scale Overflow Region" : "Draw Scale Overflow Region",
                        action: onToggleOverflowRegion
                    )
                }
            }

            Divider()
                .frame(height: 14)

            Text(isTimelineScrubSnappingEnabled ? "snapping on" : "snapping off")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(flowTrackTheme.controlStripText)

            TimelineGadgetButton(
                systemName: "arrow.down.to.line.compact",
                isActive: isTimelineScrubSnappingEnabled,
                isEnabled: true,
                help: "Turn marker snapping on or off while moving the playhead",
                action: onToggleTimelineScrubSnapping
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(flowTrackTheme.controlStripBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(flowTrackTheme.controlStripBorder, lineWidth: 1)
        )
    }
}

struct EffectsTimelineToolbarView: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let hasSelectedMarker: Bool
    let selectedMarker: EffectPlanItem?
    let isDrawingFocusRegion: Bool
    let showsOverlayToggle: Bool
    let isShowingOverlay: Bool
    let isTimelineScrubSnappingEnabled: Bool
    let onAddMarker: () -> Void
    let onDeleteSelectedMarker: () -> Void
    let onToggleFocusRegion: () -> Void
    let onToggleOverlay: () -> Void
    let onToggleTimelineScrubSnapping: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("effects")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(flowTrackTheme.controlStripText)

            if !hasSelectedMarker {
                TimelineGadgetButton(
                    systemName: "plus",
                    isActive: false,
                    isEnabled: true,
                    help: "Add Effect Marker",
                    action: onAddMarker
                )
            }

            if hasSelectedMarker {
                TimelineGadgetButton(
                    systemName: "minus",
                    isActive: false,
                    isEnabled: true,
                    help: "Delete Selected Effect Marker",
                    action: onDeleteSelectedMarker
                )
            }

            if selectedMarker != nil {
                Divider()
                    .frame(height: 14)

                Text("region")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(flowTrackTheme.controlStripText)

                TimelineGadgetButton(
                    systemName: isDrawingFocusRegion ? "checkmark" : "viewfinder.rectangular",
                    isActive: isDrawingFocusRegion,
                    isEnabled: true,
                    help: isDrawingFocusRegion ? "Save Effect Focus Region" : "Draw Effect Focus Region",
                    action: onToggleFocusRegion
                )

                if showsOverlayToggle {
                    Divider()
                        .frame(height: 14)

                    Text("overlay")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(flowTrackTheme.controlStripText)

                    Button(action: onToggleOverlay) {
                        Text("Show Overlay")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(segmentedPillTextColor(isSelected: isShowingOverlay, theme: flowTrackTheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(segmentedPillBackgroundColor(isSelected: isShowingOverlay, theme: flowTrackTheme))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Show the imported distortion color map over the video")
                }
            }

            Divider()
                .frame(height: 14)

            Text(isTimelineScrubSnappingEnabled ? "snapping on" : "snapping off")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(flowTrackTheme.controlStripText)

            TimelineGadgetButton(
                systemName: "arrow.down.to.line.compact",
                isActive: isTimelineScrubSnappingEnabled,
                isEnabled: true,
                help: "Turn marker snapping on or off while moving the playhead",
                action: onToggleTimelineScrubSnapping
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(flowTrackTheme.controlStripBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(flowTrackTheme.controlStripBorder, lineWidth: 1)
        )
    }
}

struct TimelineGadgetButton: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let systemName: String
    let isActive: Bool
    let isEnabled: Bool
    let help: String
    let role: ButtonRole?
    let activeColor: Color?
    let inactiveColor: Color?
    let action: () -> Void

    init(
        systemName: String,
        isActive: Bool,
        isEnabled: Bool,
        help: String,
        role: ButtonRole? = nil,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.help = help
        self.role = role
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    gadgetForegroundColor(
                        isActive: isActive,
                        isEnabled: isEnabled,
                        role: role,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        theme: flowTrackTheme
                    )
                )
                .frame(width: 18, height: 18)
                .contentShape(Rectangle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

private func gadgetForegroundColor(
    isActive: Bool,
    isEnabled: Bool,
    role: ButtonRole?,
    activeColor: Color?,
    inactiveColor: Color?,
    theme: FlowTrackTheme
) -> Color {
    if isEnabled {
        if let activeColor {
            return activeColor
        }
        if role == .destructive {
            return .red
        }
        return isActive ? theme.controlStripText : theme.controlStripMutedText
    }

    if let inactiveColor {
        return inactiveColor
    }
    return theme.controlStripMutedText
}
