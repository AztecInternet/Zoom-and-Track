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
    enum PlaybackPresentationMode {
        case normal
        case renderingPreview
        case playingRenderedPreview
        case previewCompletedSlate
    }

    enum PlaybackTransitionPlateState {
        case hidden
        case fadingIn
        case visible
        case fadingOut
    }

    enum ExportState: Equatable {
        case idle
        case preparing
        case exporting
        case finalizing
        case completed
        case failed(String)
        case cancelled

        var isInProgress: Bool {
            switch self {
            case .preparing, .exporting, .finalizing:
                return true
            default:
                return false
            }
        }
    }

    @Published var displays: [ShareableCaptureTarget] = []
    @Published var windows: [ShareableCaptureTarget] = []
    @Published var selectedTargetID: String?
    @Published var sessionState: RecordingSessionState = .idle
    @Published var statusMessage = "Choose one display or one window."
    @Published var hasScreenRecordingPermission = false
    @Published var isBusy = false
    @Published var recordingSummary: RecordingInspectionSummary?
    @Published var selectedOutputFolderPath: String?
    @Published var mainPlayer: AVPlayer?
    @Published var previewPlayer: AVPlayer?
    @Published var activeRecordingTargetName: String?
    @Published var recordingStartedAt: Date?
    @Published var selectedZoomMarkerID: String?
    @Published var currentPlaybackTime: Double = 0
    @Published var isPlaybackActive = false
    @Published var isRenderingMarkerPreview = false
    @Published var markerPreviewStatusMessage: String?
    @Published private(set) var playbackPresentationMode: PlaybackPresentationMode = .normal
    @Published private(set) var playbackTransitionPlateState: PlaybackTransitionPlateState = .hidden
    @Published private(set) var exportState: ExportState = .idle
    @Published private(set) var exportProgress: Double = 0
    @Published private(set) var exportStatusMessage: String?
    @Published private(set) var exportedRecordingURL: URL?
    
    private var hasRestoredLastRecording = false
    private var activePlaybackScopeURL: URL?
    private var mainPlaybackTimeObserver: Any?
    private var previewPlaybackTimeObserver: Any?
    private var manualSelectionSuppressionUntil: Date?
    private var previewMarkerID: String?
    private var previewEndTime: Double?
    private var wasPlayingBeforeTimelineScrub = false
    private var isTimelineScrubbing = false
    private var markerPreviewRenderTask: Task<Void, Never>?
    private var previewSurfaceTeardownTask: Task<Void, Never>?
    private var playbackTransitionTask: Task<Void, Never>?
    private var activeRenderedPreviewURL: URL?
    private var activeRenderedPreviewShouldDelete = false
    private var renderedPreviewSourceStartTime: Double?
    private var renderingPreviewMarkerID: String?
    private var exportTask: Task<Void, Never>?

    private let permissionsService = PermissionsService()
    private let screenCaptureService = ScreenCaptureService()
    private let mediaWriterService = MediaWriterService()
    private let projectBundleService = ProjectBundleService()
    private let inputEventCaptureService = InputEventCaptureService()
    private let markerPreviewRenderService = MarkerPreviewRenderService()
    private let markerPreviewCacheService = MarkerPreviewCacheService()
    private let exportRenderService = ExportRenderService()
    private let previewTransitionFadeInDuration: TimeInterval = 0.12
    private let previewTransitionHoldDuration: TimeInterval = 0.28
    private let previewTransitionFadeOutDuration: TimeInterval = 0.16
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

    var selectedZoomMarker: ZoomPlanItem? {
        recordingSummary?.zoomMarkers.first { $0.id == selectedZoomMarkerID }
    }

    var activePreviewMarkerID: String? {
        previewMarkerID
    }

    var isRenderedPreviewActive: Bool {
        playbackPresentationMode == .playingRenderedPreview && previewPlayer != nil
    }

    var canExportRecording: Bool {
        recordingSummary != nil && !exportState.isInProgress
    }

    var isExportSheetPresented: Bool {
        exportState != .idle
    }

    func load() async {
        hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
        markerPreviewCacheService.pruneStaleFiles()
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

    func exportRecording() {
        guard let summary = recordingSummary, !exportState.isInProgress else { return }
        guard let outputURL = chooseExportDestination(defaultName: summary.bundleName) else { return }

        cancelPendingMarkerPreviewRender()
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        playbackTransitionPlateState = .hidden
        playbackPresentationMode = .normal

        exportState = .preparing
        exportProgress = 0
        exportStatusMessage = "Preparing export…"
        exportedRecordingURL = nil

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await exportRenderService.exportRecording(
                    recordingURL: summary.recordingURL,
                    summary: summary,
                    outputURL: outputURL
                ) { phase, progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.exportProgress = max(0, min(progress, 1))
                        switch phase {
                        case .preparing:
                            self.exportState = .preparing
                            self.exportStatusMessage = "Preparing export…"
                        case .exporting:
                            self.exportState = .exporting
                            self.exportStatusMessage = "Exporting video…"
                        case .finalizing:
                            self.exportState = .finalizing
                            self.exportStatusMessage = "Finalizing movie…"
                        }
                    }
                }
                exportedRecordingURL = result.outputURL
                exportProgress = 1
                exportState = .completed
                exportStatusMessage = "Export complete."
                NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
            } catch is CancellationError {
                exportState = .cancelled
                exportStatusMessage = "Export cancelled."
            } catch {
                exportState = .failed(error.localizedDescription)
                exportStatusMessage = "Export failed."
            }
            exportTask = nil
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportRenderService.cancelExport()
    }

    func dismissExportSheet() {
        guard !exportState.isInProgress else { return }
        exportState = .idle
        exportProgress = 0
        exportStatusMessage = nil
        exportedRecordingURL = nil
    }

    func revealExportInFinder() {
        guard let exportedRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportedRecordingURL])
    }

    func startMarkerPreview(_ markerID: String) {
        guard let summary = recordingSummary,
              let marker = summary.zoomMarkers.first(where: { $0.id == markerID }),
              mainPlayer != nil else {
            return
        }

        cancelPendingMarkerPreviewRender()
        cancelPreviewSurfaceTeardown()
        cancelPreviewMode()
        if previewPlayer != nil {
            previewPlayer?.pause()
            removePreviewPlaybackObserver()
            previewPlayer = nil
            renderedPreviewSourceStartTime = nil
            cleanupRenderedPreviewFile()
            isPlaybackActive = false
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: true)
        selectedZoomMarkerID = markerID
        renderingPreviewMarkerID = markerID
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        playbackPresentationMode = .renderingPreview
        showPlaybackTransitionPlateImmediately()
        manualSelectionSuppressionUntil = Date().addingTimeInterval(2.0)
        seekMainPlayback(to: previewBounds(for: marker).startTime)

        markerPreviewRenderTask = Task { [weak self] in
            guard let self else { return }

            do {
                if let cachedPreview = try await markerPreviewCacheService.cachedPreview(
                    for: summary.recordingURL,
                    summary: summary,
                    marker: marker
                ) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard self.renderingPreviewMarkerID == markerID else { return }
                        self.isRenderingMarkerPreview = false
                        self.markerPreviewStatusMessage = nil
                        self.playRenderedPreview(cachedPreview, markerID: markerID)
                    }
                    return
                }

                await MainActor.run {
                    guard self.renderingPreviewMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = true
                    self.markerPreviewStatusMessage = "Rendering preview…"
                    self.playbackPresentationMode = .renderingPreview
                    self.showPlaybackTransitionPlateImmediately()
                }

                let renderedPreview = try await markerPreviewRenderService.renderPreview(
                    recordingURL: summary.recordingURL,
                    summary: summary,
                    selectedMarker: marker
                )
                let cachedPreview = try await markerPreviewCacheService.storePreview(
                    renderedPreview,
                    for: summary.recordingURL,
                    summary: summary,
                    marker: marker
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.renderingPreviewMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = false
                    self.markerPreviewStatusMessage = nil
                    self.playRenderedPreview(cachedPreview, markerID: markerID)
                }
            } catch is CancellationError {
                await MainActor.run {
                    if self.renderingPreviewMarkerID == markerID {
                        self.isRenderingMarkerPreview = false
                        self.markerPreviewStatusMessage = nil
                        self.renderingPreviewMarkerID = nil
                        self.playbackPresentationMode = .normal
                        self.playbackTransitionPlateState = .hidden
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.renderingPreviewMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = false
                    self.markerPreviewStatusMessage = nil
                    self.playbackPresentationMode = .normal
                    self.playbackTransitionPlateState = .hidden
                    self.statusMessage = "Rendered preview failed. Using live preview."
                    self.startLiveMarkerPreview(markerID)
                }
            }
        }
    }

    func togglePlayback() {
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if isRenderedPreviewActive {
            stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
            mainPlayer?.play()
            isPlaybackActive = true
            cancelPreviewMode()
            return
        }
        cancelPreviewMode()
        guard let player = mainPlayer else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaybackActive = false
        } else {
            player.play()
            isPlaybackActive = true
        }
    }

    func seekPlaybackInteractively(to seconds: Double) {
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        seekPlayback(to: seconds)
    }

    func jumpPlaybackToStart() {
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        seekPlayback(to: 0)
    }

    func cancelPlaybackPreview() {
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
    }

    func beginTimelineScrub() {
        guard let player = mainPlayer, !isTimelineScrubbing else { return }
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        wasPlayingBeforeTimelineScrub = player.timeControlStatus == .playing
        player.pause()
        isPlaybackActive = false
        isTimelineScrubbing = true
        manualSelectionSuppressionUntil = Date().addingTimeInterval(0.5)
    }

    func updateTimelineScrub(to seconds: Double, snappedMarkerID: String?) {
        guard isTimelineScrubbing else { return }
        if let snappedMarkerID {
            selectedZoomMarkerID = snappedMarkerID
        }
        seekPlayback(to: seconds)
    }

    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?) {
        guard isTimelineScrubbing else { return }
        if let snappedMarkerID {
            selectedZoomMarkerID = snappedMarkerID
        }
        seekPlayback(to: seconds)
        isTimelineScrubbing = false
        manualSelectionSuppressionUntil = Date().addingTimeInterval(0.2)
        if wasPlayingBeforeTimelineScrub {
            mainPlayer?.play()
            isPlaybackActive = true
        }
    }

    func seekTimelineDirectly(to seconds: Double, snappedMarkerID: String?) {
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        if let snappedMarkerID {
            selectedZoomMarkerID = snappedMarkerID
            manualSelectionSuppressionUntil = Date().addingTimeInterval(0.35)
        }
        seekPlayback(to: seconds)
    }

    func setSelectedMarkerEnabled(_ enabled: Bool) {
        updateSelectedMarker { marker in
            marker.enabled = enabled
        }
    }

    func setSelectedMarkerZoomScale(_ zoomScale: Double) {
        updateSelectedMarker { marker in
            marker.zoomScale = zoomScale
        }
    }

    func setSelectedMarkerLeadInTime(_ leadInTime: Double) {
        updateSelectedMarker { marker in
            marker.leadInTime = min(max(leadInTime, 0), 2.0)
            syncMarkerTiming(&marker)
        }
    }

    func setSelectedMarkerZoomInDuration(_ zoomInDuration: Double) {
        updateSelectedMarker { marker in
            marker.zoomInDuration = min(max(zoomInDuration, 0.05), 3.0)
            syncMarkerTiming(&marker)
        }
    }

    func setSelectedMarkerHoldDuration(_ holdDuration: Double) {
        updateSelectedMarker { marker in
            marker.holdDuration = min(max(holdDuration, 0.05), 10.0)
            syncMarkerTiming(&marker)
        }
    }

    func setSelectedMarkerZoomOutDuration(_ zoomOutDuration: Double) {
        updateSelectedMarker { marker in
            marker.zoomOutDuration = min(max(zoomOutDuration, 0.05), 3.0)
            syncMarkerTiming(&marker)
        }
    }

    func setSelectedMarkerEaseStyle(_ easeStyle: ZoomEaseStyle) {
        updateSelectedMarker { marker in
            marker.easeStyle = easeStyle
        }
    }

    func setSelectedMarkerZoomType(_ zoomType: ZoomType) {
        updateSelectedMarker { marker in
            marker.zoomType = zoomType
            syncMarkerTiming(&marker)
        }
    }

    func setSelectedMarkerBounceAmount(_ bounceAmount: Double) {
        updateSelectedMarker { marker in
            marker.bounceAmount = min(max(bounceAmount, 0), 1)
        }
    }

    func deleteSelectedMarker() {
        guard let summary = recordingSummary, let selectedZoomMarkerID else { return }
        var markers = summary.zoomMarkers
        markers.removeAll { $0.id == selectedZoomMarkerID }
        self.selectedZoomMarkerID = nil
        saveZoomMarkers(markers, basedOn: summary)
    }

    func duplicateSelectedMarker() {
        guard let summary = recordingSummary, let selectedMarker = selectedZoomMarker else { return }
        var markers = summary.zoomMarkers
        var duplicate = selectedMarker
        duplicate.id = nextZoomMarkerID(from: markers)
        markers.append(duplicate)
        selectedZoomMarkerID = duplicate.id
        saveZoomMarkers(markers, basedOn: summary)
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
        mainPlayer = AVPlayer(playerItem: AVPlayerItem(url: summary.recordingURL))
        previewPlayer = nil
        selectedZoomMarkerID = nil
        currentPlaybackTime = 0
        isPlaybackActive = false
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        playbackPresentationMode = .normal
        playbackTransitionPlateState = .hidden
        previewMarkerID = nil
        previewEndTime = nil
        installMainPlaybackObserver()
        updateMainPlaybackTime()
    }

    private func releasePlaybackState() {
        cancelPendingMarkerPreviewRender()
        exportTask?.cancel()
        exportRenderService.cancelExport()
        removeMainPlaybackObserver()
        removePreviewPlaybackObserver()
        mainPlayer?.pause()
        previewPlayer?.pause()
        mainPlayer = nil
        previewPlayer = nil
        recordingSummary = nil
        selectedZoomMarkerID = nil
        currentPlaybackTime = 0
        isPlaybackActive = false
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        playbackPresentationMode = .normal
        playbackTransitionPlateState = .hidden
        previewMarkerID = nil
        previewEndTime = nil
        renderedPreviewSourceStartTime = nil
        cancelPlaybackTransitionTask()
        cleanupRenderedPreviewFile()
        projectBundleService.endPlaybackAccess(activePlaybackScopeURL)
        activePlaybackScopeURL = nil
    }

    private func chooseExportDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.movie]
        panel.nameFieldStringValue = "\(defaultName) Export.mov"
        panel.isExtensionHidden = false
        panel.title = "Export Video"
        panel.prompt = "Export"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func seekPlayback(to seconds: Double) {
        guard let player = mainPlayer else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlaybackTime = max(seconds, 0)
    }

    private func updateSelectedMarker(_ mutate: (inout ZoomPlanItem) -> Void) {
        guard let summary = recordingSummary, let selectedZoomMarkerID,
              let index = summary.zoomMarkers.firstIndex(where: { $0.id == selectedZoomMarkerID }) else {
            return
        }

        var markers = summary.zoomMarkers
        mutate(&markers[index])
        saveZoomMarkers(markers, basedOn: summary)
    }

    private func saveZoomMarkers(_ markers: [ZoomPlanItem], basedOn summary: RecordingInspectionSummary) {
        do {
            let envelope = ZoomPlanEnvelope(schemaVersion: 1, source: "events.json", items: markers)
            try projectBundleService.saveZoomPlan(envelope, in: summary.bundleURL)
            recordingSummary = RecordingInspectionSummary(
                bundleURL: summary.bundleURL,
                bundleName: summary.bundleName,
                recordingURL: summary.recordingURL,
                videoAspectRatio: summary.videoAspectRatio,
                contentCoordinateSize: summary.contentCoordinateSize,
                captureSourceKind: summary.captureSourceKind,
                captureSourceTitle: summary.captureSourceTitle,
                totalEventCount: summary.totalEventCount,
                cursorMovedCount: summary.cursorMovedCount,
                leftMouseDownCount: summary.leftMouseDownCount,
                leftMouseUpCount: summary.leftMouseUpCount,
                rightMouseDownCount: summary.rightMouseDownCount,
                rightMouseUpCount: summary.rightMouseUpCount,
                firstEventTimestamp: summary.firstEventTimestamp,
                lastEventTimestamp: summary.lastEventTimestamp,
                duration: summary.duration,
                zoomMarkers: markers
            )
        } catch {
            statusMessage = "Could not save zoomPlan.json: \(error.localizedDescription)"
        }
    }

    private func syncMarkerTiming(_ marker: inout ZoomPlanItem) {
        marker.leadInTime = min(max(marker.leadInTime, 0), 2.0)
        marker.zoomInDuration = min(max(marker.zoomInDuration, 0.05), 3.0)
        marker.holdDuration = min(max(marker.holdDuration, 0.05), 10.0)
        marker.zoomOutDuration = min(max(marker.zoomOutDuration, 0.05), 3.0)

        switch marker.zoomType {
        case .inOut:
            marker.startTime = max(0, marker.sourceEventTimestamp - marker.leadInTime - marker.zoomInDuration)
            marker.holdUntil = marker.sourceEventTimestamp + marker.holdDuration
            marker.endTime = marker.holdUntil + marker.zoomOutDuration
            marker.duration = marker.totalSegmentDuration

        case .inOnly:
            marker.startTime = max(0, marker.sourceEventTimestamp - marker.leadInTime - marker.zoomInDuration)
            marker.holdUntil = marker.sourceEventTimestamp + marker.holdDuration
            marker.endTime = marker.holdUntil
            marker.duration = marker.totalSegmentDuration

        case .outOnly:
            marker.startTime = marker.sourceEventTimestamp
            marker.holdUntil = marker.sourceEventTimestamp
            marker.endTime = marker.sourceEventTimestamp + marker.zoomOutDuration
            marker.duration = marker.totalSegmentDuration
        }
    }

    private func nextZoomMarkerID(from markers: [ZoomPlanItem]) -> String {
        let maxIndex = markers.compactMap { marker in
            Int(marker.id.replacingOccurrences(of: "zoom-", with: ""))
        }.max() ?? 0
        return String(format: "zoom-%04d", maxIndex + 1)
    }

    private func previewBounds(for marker: ZoomPlanItem) -> (startTime: Double, endTime: Double) {
        let startTime = max(0, marker.startTime)
        switch marker.zoomType {
        case .inOut, .outOnly:
            return (startTime, max(marker.endTime, marker.sourceEventTimestamp))
        case .inOnly:
            return (startTime, max(marker.holdUntil, marker.sourceEventTimestamp))
        }
    }

    private func cancelPreviewMode() {
        previewMarkerID = nil
        previewEndTime = nil
    }

    private func cancelPendingMarkerPreviewRender() {
        markerPreviewRenderTask?.cancel()
        markerPreviewRenderTask = nil
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        renderingPreviewMarkerID = nil
    }

    private func startLiveMarkerPreview(_ markerID: String) {
        guard let marker = recordingSummary?.zoomMarkers.first(where: { $0.id == markerID }) else { return }
        guard let player = mainPlayer else { return }
        let previewBounds = previewBounds(for: marker)
        cancelPreviewMode()
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        selectedZoomMarkerID = markerID
        previewMarkerID = markerID
        previewEndTime = previewBounds.endTime
        manualSelectionSuppressionUntil = Date().addingTimeInterval(max(previewBounds.endTime - previewBounds.startTime, 0.35) + 0.15)
        seekPlayback(to: previewBounds.startTime)
        player.play()
        isPlaybackActive = true
    }

    private func playRenderedPreview(_ renderedPreview: RenderedMarkerPreview, markerID: String) {
        cancelPreviewSurfaceTeardown()
        cancelPlaybackTransitionTask()
        guard previewPlayer == nil else {
            stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: true)
            playRenderedPreview(renderedPreview, markerID: markerID)
            return
        }
        guard let mainPlayer else { return }
        cleanupRenderedPreviewFile()
        activeRenderedPreviewURL = renderedPreview.outputURL
        activeRenderedPreviewShouldDelete = renderedPreview.deleteWhenFinished
        renderedPreviewSourceStartTime = renderedPreview.sourceStartTime
        selectedZoomMarkerID = markerID
        previewMarkerID = markerID
        previewEndTime = renderedPreview.sourceEndTime
        renderingPreviewMarkerID = nil
        manualSelectionSuppressionUntil = Date().addingTimeInterval(
            max(renderedPreview.sourceEndTime - renderedPreview.sourceStartTime, 0.35) + 0.15
        )
        showPlaybackTransitionPlateImmediately()
        mainPlayer.pause()
        currentPlaybackTime = renderedPreview.sourceStartTime
        let player = AVPlayer(playerItem: AVPlayerItem(url: renderedPreview.outputURL))
        player.actionAtItemEnd = .pause
        previewPlayer = player
        installPreviewPlaybackObserver()
        playbackPresentationMode = .playingRenderedPreview
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        isPlaybackActive = false
        playbackTransitionTask = Task { [weak self, weak player] in
            try? await Task.sleep(for: .seconds(self?.previewTransitionHoldDuration ?? 0.28))
            await MainActor.run {
                guard let self, let player else { return }
                if self.playbackTransitionPlateState != .hidden {
                    self.playbackTransitionPlateState = .fadingOut
                }
                player.play()
                self.isPlaybackActive = true
            }
            try? await Task.sleep(for: .seconds(self?.previewTransitionFadeOutDuration ?? 0.16))
            await MainActor.run {
                guard let self, self.playbackTransitionPlateState == .fadingOut else { return }
                self.playbackTransitionPlateState = .hidden
                self.playbackTransitionTask = nil
            }
        }
    }

    private func stopPreviewPlayback(seekMainTo sourceTime: Double?, retainSlate: Bool) {
        guard previewPlayer != nil || renderedPreviewSourceStartTime != nil else {
            return
        }

        cancelPlaybackTransitionTask()
        if retainSlate {
            showPlaybackTransitionPlate()
        }
        let playerToTearDown = previewPlayer
        previewPlayer?.pause()
        removePreviewPlaybackObserver()
        playbackPresentationMode = retainSlate
            ? .previewCompletedSlate
            : (isRenderingMarkerPreview ? .renderingPreview : .normal)
        guard let mainPlayer else {
            previewPlayer = nil
            renderedPreviewSourceStartTime = nil
            cleanupRenderedPreviewFile()
            return
        }
        if let sourceTime {
            let time = CMTime(seconds: max(sourceTime, 0), preferredTimescale: 600)
            mainPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            currentPlaybackTime = max(sourceTime, 0)
        }
        renderedPreviewSourceStartTime = nil
        isPlaybackActive = mainPlayer.timeControlStatus == .playing
        previewSurfaceTeardownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.previewTransitionFadeOutDuration ?? 0.14))
            await MainActor.run {
                guard let self else { return }
                if self.previewPlayer === playerToTearDown {
                    self.previewPlayer = nil
                    self.cleanupRenderedPreviewFile()
                }
                self.previewSurfaceTeardownTask = nil
            }
        }
        if retainSlate {
            playbackTransitionTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.previewTransitionFadeInDuration ?? 0.12))
                await MainActor.run {
                    guard let self, self.playbackTransitionPlateState == .fadingIn else { return }
                    self.playbackTransitionPlateState = .visible
                    self.playbackTransitionTask = nil
                }
            }
        } else {
            playbackTransitionPlateState = .hidden
        }
    }

    private func seekMainPlayback(to seconds: Double) {
        guard let mainPlayer else { return }
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        mainPlayer.pause()
        mainPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlaybackTime = max(seconds, 0)
        isPlaybackActive = false
    }

    private func cleanupRenderedPreviewFile() {
        if let activeRenderedPreviewURL, activeRenderedPreviewShouldDelete {
            try? FileManager.default.removeItem(at: activeRenderedPreviewURL)
        }
        activeRenderedPreviewURL = nil
        activeRenderedPreviewShouldDelete = false
    }

    private func cancelPreviewSurfaceTeardown() {
        previewSurfaceTeardownTask?.cancel()
        previewSurfaceTeardownTask = nil
    }

    private func cancelPlaybackTransitionTask() {
        playbackTransitionTask?.cancel()
        playbackTransitionTask = nil
    }

    private func showPlaybackTransitionPlate() {
        cancelPlaybackTransitionTask()
        playbackTransitionPlateState = .fadingIn
        playbackTransitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.previewTransitionFadeInDuration ?? 0.12))
            await MainActor.run {
                guard let self, self.playbackTransitionPlateState == .fadingIn else { return }
                self.playbackTransitionPlateState = .visible
            }
        }
    }

    private func showPlaybackTransitionPlateImmediately() {
        cancelPlaybackTransitionTask()
        playbackTransitionPlateState = .visible
    }

    private func schedulePlaybackTransitionPlateFadeOut() {
        cancelPlaybackTransitionTask()
        playbackTransitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.previewTransitionHoldDuration ?? 0.14))
            await MainActor.run {
                guard let self else { return }
                if self.playbackTransitionPlateState != .hidden {
                    self.playbackTransitionPlateState = .fadingOut
                }
            }
            try? await Task.sleep(for: .seconds(self?.previewTransitionFadeOutDuration ?? 0.16))
            await MainActor.run {
                guard let self, self.playbackTransitionPlateState == .fadingOut else { return }
                self.playbackTransitionPlateState = .hidden
                self.playbackTransitionTask = nil
            }
        }
    }

    private func installMainPlaybackObserver() {
        removeMainPlaybackObserver()
        guard let player = mainPlayer else { return }

        mainPlaybackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMainPlaybackTime()
            }
        }
    }

    private func removeMainPlaybackObserver() {
        guard let player = mainPlayer, let mainPlaybackTimeObserver else { return }
        player.removeTimeObserver(mainPlaybackTimeObserver)
        self.mainPlaybackTimeObserver = nil
    }

    private func installPreviewPlaybackObserver() {
        removePreviewPlaybackObserver()
        guard let player = previewPlayer else { return }

        previewPlaybackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePreviewPlaybackTime()
            }
        }
    }

    private func removePreviewPlaybackObserver() {
        guard let player = previewPlayer, let previewPlaybackTimeObserver else { return }
        player.removeTimeObserver(previewPlaybackTimeObserver)
        self.previewPlaybackTimeObserver = nil
    }

    private func updateMainPlaybackTime() {
        guard let player = mainPlayer else {
            return
        }

        let currentTime = player.currentTime().seconds
        guard currentTime.isFinite else { return }
        currentPlaybackTime = currentTime
        if playbackPresentationMode == .normal {
            isPlaybackActive = player.timeControlStatus == .playing
        }

        if isTimelineScrubbing {
            return
        }

        if isRenderingMarkerPreview, let renderingPreviewMarkerID {
            selectedZoomMarkerID = renderingPreviewMarkerID
            return
        }

        guard playbackPresentationMode == .normal else {
            return
        }

        updateSelectedMarkerForTime(currentTime)
    }

    private func updatePreviewPlaybackTime() {
        guard let player = previewPlayer else { return }
        let playerTime = player.currentTime().seconds
        guard playerTime.isFinite else { return }
        let currentTime = (renderedPreviewSourceStartTime ?? 0) + playerTime
        currentPlaybackTime = currentTime
        isPlaybackActive = player.timeControlStatus == .playing

        if let previewEndTime, let previewMarkerID {
            selectedZoomMarkerID = previewMarkerID
            if currentTime >= previewEndTime - 0.02 {
                player.pause()
                isPlaybackActive = false
                cancelPreviewMode()
                stopPreviewPlayback(seekMainTo: previewEndTime, retainSlate: true)
            }
            return
        }

        updateSelectedMarkerForTime(currentTime)
    }

    private func updateSelectedMarkerForTime(_ currentTime: Double) {
        guard let summary = recordingSummary, !summary.zoomMarkers.isEmpty else {
            return
        }

        if let manualSelectionSuppressionUntil, Date() < manualSelectionSuppressionUntil {
            return
        }

        let eligibleMarkers = summary.zoomMarkers.filter { $0.enabled }
        let markers = eligibleMarkers.isEmpty ? summary.zoomMarkers : eligibleMarkers
        let markerID = markers.last(where: { $0.sourceEventTimestamp <= currentTime })?.id

        if selectedZoomMarkerID != markerID {
            selectedZoomMarkerID = markerID
        }
    }
}
