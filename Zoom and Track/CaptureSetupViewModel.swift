//
//  CaptureSetupViewModel.swift
//  Zoom and Track
//

import Combine
import AppKit
import AVKit
import Foundation

@MainActor
final class CaptureSetupViewModel: ObservableObject {
    @Published var displays: [ShareableCaptureTarget] = []
    @Published var windows: [ShareableCaptureTarget] = []
    @Published var selectedTargetID: String?
    @Published var sessionState: RecordingSessionState = .idle
    @Published var statusMessage = "Choose one display or one window."
    @Published var hasScreenRecordingPermission = false
    @Published var isBusy = false
    @Published var recordingSummary: RecordingInspectionSummary?
    @Published var selectedOutputFolderPath: String?
    @Published var player: AVPlayer?
    @Published var activeRecordingTargetName: String?
    @Published var recordingStartedAt: Date?
    
    private var hasRestoredLastRecording = false
    private var activePlaybackScopeURL: URL?

    private let permissionsService = PermissionsService()
    private let screenCaptureService = ScreenCaptureService()
    private let mediaWriterService = MediaWriterService()
    private let projectBundleService = ProjectBundleService()
    private let inputEventCaptureService = InputEventCaptureService()
    private lazy var recordingCoordinator = RecordingCoordinator(
        screenCaptureService: screenCaptureService,
        mediaWriterService: mediaWriterService,
        projectBundleService: projectBundleService,
        inputEventCaptureService: inputEventCaptureService
    )

    init() {
        recordingCoordinator.onStateChange = { [weak self] state, message in
            guard let self else { return }
            sessionState = state
            statusMessage = message
            isBusy = state == .loadingTargets || state == .preparing || state == .stopping
        }
        recordingCoordinator.onSummaryAvailable = { [weak self] summary in
            self?.applyPlaybackSummary(summary)
        }
        recordingCoordinator.onPlaybackLoadFailure = { [weak self] message in
            self?.releasePlaybackState()
            self?.statusMessage = message
        }
        applyOutputDirectoryResolution()
    }

    var selectedTarget: ShareableCaptureTarget? {
        (displays + windows).first(where: { $0.id == selectedTargetID })
    }

    var canStartRecording: Bool {
        selectedTarget != nil && sessionState != .preparing && sessionState != .recording && sessionState != .stopping
    }

    var canStopRecording: Bool {
        sessionState == .recording || sessionState == .preparing
    }

    func load() async {
        hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
        recordingCoordinator.onStateChange?(.loadingTargets, "Loading capture targets…")

        do {
            let targets = try await screenCaptureService.fetchTargets()
            displays = targets.displays
            windows = targets.windows

            if let selectedTargetID, (displays + windows).contains(where: { $0.id == selectedTargetID }) == false {
                self.selectedTargetID = nil
            }

            sessionState = .idle
            statusMessage = hasScreenRecordingPermission
                ? "Choose one display or one window."
                : "Screen Recording permission is required."
            isBusy = false
            applyOutputDirectoryResolutionIfNeeded()
            await restoreLastRecordingIfNeeded()
        } catch {
            sessionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            isBusy = false
        }
    }

    func requestPermission() async {
        _ = permissionsService.requestScreenRecordingPermission()
        hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
        statusMessage = hasScreenRecordingPermission
            ? "Permission granted. Reload targets if needed."
            : "Grant Screen Recording permission in System Settings, then relaunch the app if capture still fails."
    }

    func startRecording() async {
        guard let selectedTarget else { return }
        releasePlaybackState()
        activeRecordingTargetName = selectedTarget.displayTitle
        recordingStartedAt = Date()
        await recordingCoordinator.startRecording(
            target: selectedTarget,
            outputDirectory: projectBundleService.resolvedSelectedOutputDirectory()
        )
    }

    func stopRecording() async {
        await recordingCoordinator.stopRecording()
        recordingStartedAt = nil
    }

    func revealInFinder() {
        guard let bundleURL = recordingSummary?.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    func chooseOutputFolder() {
        guard let url = projectBundleService.chooseOutputDirectory() else { return }
        selectedOutputFolderPath = url.path
        statusMessage = "Output folder selected."
    }

    func openRecording() {
        guard let bundleURL = projectBundleService.openRecordingBundle() else { return }

        Task {
            do {
                let summary = try await projectBundleService.loadRecordingInspection(from: bundleURL)
                _ = projectBundleService.persistLastRecordingBundle(bundleURL)
                try loadPlayback(summary)
                activeRecordingTargetName = nil
                recordingStartedAt = nil
                statusMessage = "Loaded \(summary.bundleName)"
            } catch {
                releasePlaybackState()
                statusMessage = "Playback could not load \(bundleURL.path): \(error.localizedDescription)"
            }
        }
    }

    private func applyOutputDirectoryResolution() {
        switch projectBundleService.resolveSelectedOutputDirectory() {
        case .none:
            selectedOutputFolderPath = nil
        case .resolved(let url):
            selectedOutputFolderPath = url.path
        case .invalid(let message):
            selectedOutputFolderPath = nil
            statusMessage = message
        }
    }

    private func applyOutputDirectoryResolutionIfNeeded() {
        switch projectBundleService.resolveSelectedOutputDirectory() {
        case .none:
            selectedOutputFolderPath = nil
        case .resolved(let url):
            selectedOutputFolderPath = url.path
        case .invalid(let message):
            selectedOutputFolderPath = nil
            if !message.isEmpty {
                statusMessage = message
            }
        }
    }

    private func restoreLastRecordingIfNeeded() async {
        guard !hasRestoredLastRecording else { return }
        hasRestoredLastRecording = true

        switch projectBundleService.resolveLastRecordingBundle() {
        case .none:
            return
        case .resolved(let url):
            do {
                let summary = try await projectBundleService.loadRecordingInspection(from: url)
                try loadPlayback(summary)
            } catch {
                releasePlaybackState()
                if statusMessage.isEmpty || statusMessage == "Choose one display or one window." {
                    statusMessage = "Playback could not load \(url.path): \(error.localizedDescription)"
                }
            }
        case .invalid(let message):
            if !message.isEmpty {
                statusMessage = message
            }
        }
    }

    private func applyPlaybackSummary(_ summary: RecordingInspectionSummary) {
        do {
            try loadPlayback(summary)
        } catch {
            releasePlaybackState()
            statusMessage = "Playback could not load \(summary.recordingURL.path): \(error.localizedDescription)"
        }
    }

    private func loadPlayback(_ summary: RecordingInspectionSummary) throws {
        releasePlaybackState()

        guard FileManager.default.fileExists(atPath: summary.recordingURL.path) else {
            throw NSError(
                domain: "CaptureSetupViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "recording.mov is missing at \(summary.recordingURL.path)"]
            )
        }

        let playbackScopeURL = try projectBundleService.beginPlaybackAccess(for: summary.bundleURL)
        if !FileManager.default.isReadableFile(atPath: summary.recordingURL.path) {
            projectBundleService.endPlaybackAccess(playbackScopeURL)
            throw NSError(
                domain: "CaptureSetupViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Playback could not access \(summary.recordingURL.path). Open Recording again."]
            )
        }

        activePlaybackScopeURL = playbackScopeURL

        recordingSummary = summary
        player = AVPlayer(playerItem: AVPlayerItem(url: summary.recordingURL))
    }

    private func releasePlaybackState() {
        player?.pause()
        player = nil
        recordingSummary = nil
        projectBundleService.endPlaybackAccess(activePlaybackScopeURL)
        activePlaybackScopeURL = nil
    }
}
