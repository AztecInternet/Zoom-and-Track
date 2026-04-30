import SwiftUI

enum EditInspectorMode: String, CaseIterable, Identifiable {
    case captureInfo = "Edit Capture Info"
    case markers = "Edit Markers List"

    var id: String { rawValue }
}

struct InspectorSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.accentColor)
    }
}

struct EffectsInspectorPlaceholderView: View {
    let effectMarkerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionHeaderView(title: "Effects")
                Text("This phase adds the separate Effects editor mode and ghosted timeline references. Effect markers, lists, and controls land in the next phase.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionHeaderView(title: "Status")
                Text(effectMarkerCount == 0 ? "No effect markers yet" : "\(effectMarkerCount) effect marker" + (effectMarkerCount == 1 ? "" : "s"))
                    .font(.system(size: 13, weight: .medium))
                Text("Zoom & Click bars remain visible in the timeline as non-editable grey reference guides while you are in Effects mode.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct ReviewInspectorCard<PrimaryContent: View>: View {
    let editorMode: ReviewEditorMode
    @Binding var inspectorMode: EditInspectorMode
    let effectMarkerCount: Int
    @ViewBuilder let primaryContent: PrimaryContent

    init(
        editorMode: ReviewEditorMode,
        inspectorMode: Binding<EditInspectorMode>,
        effectMarkerCount: Int,
        @ViewBuilder primaryContent: () -> PrimaryContent
    ) {
        self.editorMode = editorMode
        self._inspectorMode = inspectorMode
        self.effectMarkerCount = effectMarkerCount
        self.primaryContent = primaryContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.system(size: 16, weight: .semibold))

            if editorMode == .effects {
                EffectsInspectorPlaceholderView(effectMarkerCount: effectMarkerCount)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorSectionHeaderView(title: "Mode")

                    Picker("Mode", selection: $inspectorMode) {
                        ForEach(EditInspectorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                primaryContent
            }
        }
    }
}
