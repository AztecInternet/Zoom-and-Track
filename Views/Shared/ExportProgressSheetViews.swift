import AppKit
import SwiftUI

extension ContentView {
    var exportProgressSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exportSheetTitle)
                .font(.title3.weight(.semibold))

            if let exportStatusMessage = viewModel.exportStatusMessage {
                Text(exportStatusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressValueForDisplay)
                .progressViewStyle(.linear)

            Text("\(Int(progressValueForDisplay * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack {
                if case .completed = viewModel.exportState {
                    Button("Reveal in Finder") {
                        viewModel.revealExportInFinder()
                    }

                    Button("Share…") {
                        presentExportSharePicker()
                    }
                    .background(
                        SharingAnchorView { view in
                            exportShareAnchorView = view
                        }
                        .frame(width: 0, height: 0)
                    )
                }

                Spacer()

                switch viewModel.exportState {
                case .preparing, .exporting, .finalizing:
                    Button("Cancel") {
                        viewModel.cancelExport()
                    }
                default:
                    Button("Done") {
                        viewModel.dismissExportSheet()
                    }
                }
            }
        }
    }

    var exportSheetTitle: String {
        switch viewModel.exportState {
        case .idle:
            return "Export"
        case .preparing:
            return "Preparing Export"
        case .exporting:
            return "Exporting Video"
        case .finalizing:
            return "Finalizing Movie"
        case .completed:
            return "Export Complete"
        case .failed:
            return "Export Failed"
        case .cancelled:
            return "Export Cancelled"
        }
    }

    var progressValueForDisplay: Double {
        let progress = max(0, min(viewModel.exportProgress, 1))
        switch viewModel.exportState {
        case .completed:
            return 1
        case .failed, .cancelled, .idle:
            return progress
        default:
            return max(progress, 0.02)
        }
    }

    func presentExportSharePicker() {
        guard let exportedRecordingURL = viewModel.exportedRecordingURL,
              let exportShareAnchorView else {
            return
        }

        let picker = NSSharingServicePicker(items: [exportedRecordingURL])
        picker.show(
            relativeTo: exportShareAnchorView.bounds,
            of: exportShareAnchorView,
            preferredEdge: .maxY
        )
    }
}
