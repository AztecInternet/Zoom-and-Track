import SwiftUI

enum ReviewEditorMode: String, CaseIterable, Identifiable {
    case zoomAndClicks = "Zoom & Clicks"
    case effects = "Effects"

    var id: String { rawValue }
}

struct ReviewEditorModeControlStrip: View {
    let editorMode: ReviewEditorMode
    let onSelectMode: (ReviewEditorMode) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("editor")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 2) {
                ForEach(ReviewEditorMode.allCases) { mode in
                    Button {
                        onSelectMode(mode)
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(segmentedPillTextColor(isSelected: editorMode == mode))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(segmentedPillBackgroundColor(isSelected: editorMode == mode))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mode.rawValue)
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct EffectsPlaceholderControlStrip: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("effects")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 2) {
                Text("mode")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(segmentedPillBackgroundColor(isSelected: false))
                    )

                Text("style")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(segmentedPillBackgroundColor(isSelected: false))
                    )
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

func segmentedPillTextColor(isSelected: Bool) -> Color {
    isSelected ? .white : .secondary
}

func segmentedPillBackgroundColor(isSelected: Bool) -> Color {
    isSelected ? .accentColor : Color.secondary.opacity(0.08)
}
