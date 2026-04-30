import SwiftUI

struct TimelineToolbarView: View {
    let hasSelectedMarker: Bool
    let canEditClickFocusMarkers: Bool
    let isPlacingClickFocus: Bool
    let selectedMarker: ZoomPlanItem?
    let showsPulseControls: Bool
    let showsNoZoomFallbackControls: Bool
    let isDrawingNoZoomOverflowRegion: Bool
    let onToggleAddClickFocus: () -> Void
    let onDeleteSelectedMarker: () -> Void
    let onToggleClickPulse: () -> Void
    let onSelectClickPulsePreset: (ClickPulsePreset) -> Void
    let onSelectNoZoomFallbackMode: (NoZoomFallbackMode) -> Void
    let onToggleOverflowRegion: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("markers")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.accentColor)

            TimelineGadgetButton(
                systemName: isPlacingClickFocus ? "xmark" : "plus",
                isActive: isPlacingClickFocus,
                isEnabled: canEditClickFocusMarkers || isPlacingClickFocus,
                help: isPlacingClickFocus ? "Cancel Add Click Focus" : "Add Click Focus",
                action: onToggleAddClickFocus
            )

            if hasSelectedMarker {
                TimelineGadgetButton(
                    systemName: "minus",
                    isActive: false,
                    isEnabled: true,
                    help: "Delete Selected Marker",
                    action: onDeleteSelectedMarker
                )
            }

            if showsPulseControls, let selectedMarker {
                Divider()
                    .frame(height: 14)

                Text("click pulse")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Color.accentColor)

                TimelineGadgetButton(
                    systemName: "pointer.arrow.click.2",
                    isActive: selectedMarker.isClickPulseEnabled,
                    isEnabled: true,
                    help: selectedMarker.isClickPulseEnabled ? "Disable Click Pulse" : "Enable Click Pulse",
                    action: onToggleClickPulse
                )

                if selectedMarker.isClickPulseEnabled, let clickPulse = selectedMarker.clickPulse {
                    Menu {
                        ForEach(ClickPulsePreset.allCases) { preset in
                            Button(preset.displayName) {
                                onSelectClickPulsePreset(preset)
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Click Pulse Style: \(clickPulse.preset.displayName)")
                }
            }

            if showsNoZoomFallbackControls, let selectedMarker {
                Divider()
                    .frame(height: 14)

                Text("overflow")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Color.accentColor)

                HStack(spacing: 2) {
                    ForEach(NoZoomFallbackMode.allCases) { mode in
                        Button {
                            onSelectNoZoomFallbackMode(mode)
                        } label: {
                            Text(mode.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(segmentedPillTextColor(isSelected: selectedMarker.noZoomFallbackMode == mode))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(segmentedPillBackgroundColor(isSelected: selectedMarker.noZoomFallbackMode == mode))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("No Zoom Overflow: \(mode.displayName)")
                    }
                }
                .padding(2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )

                if selectedMarker.noZoomFallbackMode == .scale {
                    Divider()
                        .frame(height: 14)

                    Text("region")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Color.accentColor)

                    TimelineGadgetButton(
                        systemName: isDrawingNoZoomOverflowRegion ? "checkmark" : "viewfinder.rectangular",
                        isActive: isDrawingNoZoomOverflowRegion,
                        isEnabled: true,
                        help: isDrawingNoZoomOverflowRegion ? "Save Scale Overflow Region" : "Draw Scale Overflow Region",
                        action: onToggleOverflowRegion
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

struct TimelineGadgetButton: View {
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
                        inactiveColor: inactiveColor
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
    inactiveColor: Color?
) -> Color {
    if isEnabled {
        if let activeColor {
            return activeColor
        }
        if role == .destructive {
            return .red
        }
        return isActive ? .accentColor : .secondary
    }

    if let inactiveColor {
        return inactiveColor
    }
    return .secondary
}
