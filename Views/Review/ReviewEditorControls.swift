import SwiftUI

enum ReviewEditorMode: String, CaseIterable, Identifiable {
    case zoomAndClicks = "Zoom & Clicks"
    case effects = "Effects"

    var id: String { rawValue }
}

struct ReviewEditorModeControlStrip: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let editorMode: ReviewEditorMode
    let onSelectMode: (ReviewEditorMode) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("editor")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(flowTrackTheme.controlStripText)

            HStack(spacing: 2) {
                ForEach(ReviewEditorMode.allCases) { mode in
                    Button {
                        onSelectMode(mode)
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(segmentedPillTextColor(isSelected: editorMode == mode, theme: flowTrackTheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(segmentedPillBackgroundColor(isSelected: editorMode == mode, theme: flowTrackTheme))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mode.rawValue)
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 32)
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

struct EffectsPlaceholderControlStrip: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    var body: some View {
        HStack(spacing: 10) {
            Text("effects")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(flowTrackTheme.controlStripText)

            HStack(spacing: 2) {
                Text("mode")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(flowTrackTheme.controlStripMutedText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(segmentedPillBackgroundColor(isSelected: false, theme: flowTrackTheme))
                    )

                Text("style")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(flowTrackTheme.controlStripMutedText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(segmentedPillBackgroundColor(isSelected: false, theme: flowTrackTheme))
                    )
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 32)
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

func segmentedPillTextColor(isSelected: Bool, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
    isSelected ? theme.accentButtonText : theme.controlStripMutedText
}

func segmentedPillBackgroundColor(isSelected: Bool, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
    isSelected ? theme.controlStripText : theme.controlStripBackground
}

func accentContrastingTextColor(theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
    theme.accentButtonText
}

extension ReviewEditorMode {
    var accentRole: FlowTrackAccentRole {
        switch self {
        case .zoomAndClicks:
            return .zoomAndClicks
        case .effects:
            return .effects
        }
    }
}
