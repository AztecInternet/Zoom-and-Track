//
//  RecordingCoordinator.swift
//  Zoom and Track
//

import Foundation

@MainActor
final class RecordingCoordinator {
    var onStateChange: ((RecordingSessionState, String) -> Void)?
    var onSummaryAvailable: ((RecordingInspectionSummary) -> Void)?
    var onPlaybackLoadFailure: ((String) -> Void)?

    private let screenCaptureService: ScreenCaptureService
    private let mediaWriterService: MediaWriterService
    private let projectBundleService: ProjectBundleService
    private let inputEventCaptureService: InputEventCaptureService

    private var workspace: RecordingWorkspace?
    private var currentTarget: ShareableCaptureTarget?
    private var isStopping = false

    init(
        screenCaptureService: ScreenCaptureService,
        mediaWriterService: MediaWriterService,
        projectBundleService: ProjectBundleService,
        inputEventCaptureService: InputEventCaptureService
    ) {
        self.screenCaptureService = screenCaptureService
        self.mediaWriterService = mediaWriterService
        self.projectBundleService = projectBundleService
        self.inputEventCaptureService = inputEventCaptureService
    }

    func startRecording(target: ShareableCaptureTarget, outputDirectory: URL?) async {
        guard workspace == nil else { return }

        do {
            update(.preparing, message: "Preparing recording…")
            let workspace = try projectBundleService.createWorkspace(outputDirectory: outputDirectory)
            try mediaWriterService.startWriting(to: workspace.temporaryRecordingURL, width: target.width, height: target.height)
            mediaWriterService.onSessionStart = { [weak self] timestamp, uptime in
                Task { @MainActor in
                    self?.inputEventCaptureService.setSessionStart(videoTimestamp: timestamp, uptime: uptime)
                }
            }

            self.workspace = workspace
            currentTarget = target
            isStopping = false

            inputEventCaptureService.start()

            try await screenCaptureService.startCapture(
                target: target,
                onSampleBuffer: { [weak self] sampleBuffer in
                    guard let self else { return }
                    do {
                        try self.mediaWriterService.append(sampleBuffer: sampleBuffer)
                    } catch {
                        Task { @MainActor in
                            await self.handleFailure(error)
                        }
                    }
                },
                onStreamStop: { [weak self] error in
                    guard let self, let error else { return }
                    Task { @MainActor in
                        await self.handleStreamError(error)
                    }
                }
            )

            update(.recording, message: "Recording \(target.displayTitle)")
        } catch {
            await handleFailure(error)
        }
    }

    func stopRecording() async {
        guard workspace != nil, !isStopping else { return }
        isStopping = true
        update(.stopping, message: "Stopping recording…")

        do {
            try await screenCaptureService.stopCapture()

            guard mediaWriterService.didWriteFrame else {
                throw NSError(domain: "RecordingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video frames were captured."])
            }

            try await mediaWriterService.finishWriting()
            inputEventCaptureService.stop()
            let finalURL = try await finalizeProject()
            update(.finished(finalURL), message: "Saved recording to \(finalURL.lastPathComponent)")
        } catch {
            await handleFailure(error)
        }
    }

    private func finalizeProject() async throws -> URL {
        guard let workspace, let currentTarget else {
            throw NSError(domain: "RecordingCoordinator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recording state is incomplete."])
        }

        let manifest = ProjectManifest(
            id: UUID(),
            name: workspace.finalProjectURL.deletingPathExtension().lastPathComponent,
            createdAt: Date(),
            captureSource: CaptureSource(
                kind: currentTarget.kind,
                sourceID: currentTarget.sourceID,
                title: currentTarget.title,
                subtitle: currentTarget.subtitle,
                width: currentTarget.width,
                height: currentTarget.height
            ),
            recordingFileName: "recording.mov",
            eventFileName: "events.json"
        )

        let events = inputEventCaptureService.finish()
        let finalURL = try projectBundleService.finalizeWorkspace(workspace, manifest: manifest, events: events)
        _ = projectBundleService.persistLastRecordingBundle(finalURL)
        do {
            let summary = try await projectBundleService.loadRecordingInspection(from: finalURL)
            onSummaryAvailable?(summary)
        } catch {
            let recordingURL = finalURL.appendingPathComponent("recording.mov")
            onPlaybackLoadFailure?("Playback could not load \(recordingURL.path): \(error.localizedDescription)")
        }
        reset()
        return finalURL
    }

    private func handleStreamError(_ error: Error) async {
        guard !isStopping else { return }

        if currentTarget?.kind == .window {
            let message = "Selected window is no longer available."
            update(.failed(message), message: message)
        }

        await handleFailure(error, overrideMessage: currentTarget?.kind == .window ? "Selected window is no longer available." : nil)
    }

    private func handleFailure(_ error: Error, overrideMessage: String? = nil) async {
        mediaWriterService.cancelWriting()
        inputEventCaptureService.cancel()
        do {
            try await screenCaptureService.stopCapture()
        } catch {
        }

        projectBundleService.cleanupWorkspace(workspace)

        let message = overrideMessage ?? error.localizedDescription
        reset()
        update(.failed(message), message: message)
    }

    private func reset() {
        workspace = nil
        currentTarget = nil
        isStopping = false
        mediaWriterService.onSessionStart = nil
    }

    private func update(_ state: RecordingSessionState, message: String) {
        onStateChange?(state, message)
    }
}
