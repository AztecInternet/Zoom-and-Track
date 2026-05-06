import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ExportManager {
    enum Outcome {
        case completed(URL)
        case cancelled
        case failed(Error)
    }

    private let exportRenderService = ExportRenderService()
    private var exportTask: Task<Void, Never>?
    private var activeExportOperationID = UUID()

    var hasActiveExport: Bool {
        exportTask != nil
    }

    func chooseExportDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.movie]
        panel.nameFieldStringValue = "\(defaultName) Export.mov"
        panel.isExtensionHidden = false
        panel.title = "Export Video"
        panel.prompt = "Export"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func exportRecording(
        recordingURL: URL,
        summary: RecordingInspectionSummary,
        outputURL: URL,
        onPhaseUpdate: @escaping @MainActor (CaptureSetupViewModel.ExportState, Double, String) -> Void,
        onCompletion: @escaping @MainActor (Outcome) -> Void
    ) {
        let exportOperationID = UUID()
        activeExportOperationID = exportOperationID

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await exportRenderService.exportRecording(
                    recordingURL: recordingURL,
                    summary: summary,
                    outputURL: outputURL
                ) { [weak self] phase, progress in
                    guard let self else { return }
                    guard self.activeExportOperationID == exportOperationID else { return }
                    let clampedProgress = max(0, min(progress, 1))
                    switch phase {
                    case .preparing:
                        await onPhaseUpdate(.preparing, clampedProgress, "Preparing export…")
                    case .exporting:
                        await onPhaseUpdate(.exporting, clampedProgress, "Exporting video…")
                    case .finalizing:
                        await onPhaseUpdate(.finalizing, clampedProgress, "Finalizing movie…")
                    }
                }
                guard activeExportOperationID == exportOperationID else { return }
                await onCompletion(.completed(result.outputURL))
            } catch is CancellationError {
                guard activeExportOperationID == exportOperationID else { return }
                await onCompletion(.cancelled)
            } catch {
                guard activeExportOperationID == exportOperationID else { return }
                await onCompletion(.failed(error))
            }
            if activeExportOperationID == exportOperationID {
                exportTask = nil
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportRenderService.cancelExport()
    }

    func reset() {
        activeExportOperationID = UUID()
        exportTask?.cancel()
        exportTask = nil
        exportRenderService.cancelExport()
    }
}
