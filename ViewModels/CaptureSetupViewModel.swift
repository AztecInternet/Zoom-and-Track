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
    @Published var collectionName: String = "Default Collection" {
        didSet { persistLastUsedCaptureMetadata() }
    }
    @Published var projectName: String = "General Project" {
        didSet { persistLastUsedCaptureMetadata() }
    }
    @Published var captureType: CaptureType = .tutorial {
        didSet { persistLastUsedCaptureMetadata() }
    }
    @Published var captureTitle: String = ""
    @Published private(set) var libraryItems: [CaptureLibraryItem] = []
    @Published private(set) var libraryStatusMessage: String?
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
    @Published var selectedEffectMarkerID: String?
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
    @Published var defaultNoZoomFallbackMode: NoZoomFallbackMode = .pan
    
    private var hasRestoredLastRecording = false
    private var activePlaybackScopeURL: URL?
    private var mainPlaybackTimeObserver: Any?
    private var previewPlaybackTimeObserver: Any?
    private var manualSelectionSuppressionUntil: Date?
    private var previewMarkerID: String?
    private var previewEndTime: Double?
    private var previewEffectMarkerID: String?
    private var previewEffectEndTime: Double?
    private var wasPlayingBeforeTimelineScrub = false
    private var isTimelineScrubbing = false
    private var markerPreviewRenderTask: Task<Void, Never>?
    private var previewSurfaceTeardownTask: Task<Void, Never>?
    private var playbackTransitionTask: Task<Void, Never>?
    private var activeRenderedPreviewURL: URL?
    private var activeRenderedPreviewShouldDelete = false
    private var renderedPreviewSourceStartTime: Double?
    private var renderingPreviewMarkerID: String?
    private var renderingPreviewEffectMarkerID: String?
    private var targetRefreshTask: Task<Void, Never>?
    private let timelineMarkerNudgeInterval = 0.1

    private let permissionsService = PermissionsService()
    private let screenCaptureService = ScreenCaptureService()
    private let mediaWriterService = MediaWriterService()
    private let projectBundleService = ProjectBundleService()
    private lazy var libraryManager = LibraryManager(projectBundleService: projectBundleService)
    private lazy var captureTargetManager = CaptureTargetManager(
        permissionsService: permissionsService,
        screenCaptureService: screenCaptureService
    )
    nonisolated(unsafe) private let captureMetadataManager: CaptureMetadataManager
    private let playbackTransportManager = PlaybackTransportManager()
    private let timelineScrubManager = TimelineScrubManager()
    private let inputEventCaptureService = InputEventCaptureService()
    private let markerPreviewRenderService = MarkerPreviewRenderService()
    private let markerPreviewCacheService = MarkerPreviewCacheService()
    private let exportManager = ExportManager()
    private let previewTransitionFadeInDuration: TimeInterval = 0.12
    private let previewTransitionHoldDuration: TimeInterval = 1.0
    private let previewTransitionFadeOutDuration: TimeInterval = 0.16
    private let lastCollectionNameKey = "LastCollectionName"
    private let lastProjectNameKey = "LastProjectName"
    private let lastCaptureTypeKey = "LastCaptureType"
    private let defaultNoZoomFallbackModeKey = "DefaultNoZoomFallbackMode"
    private lazy var recordingCoordinator = RecordingCoordinator(
        screenCaptureService: screenCaptureService,
        mediaWriterService: mediaWriterService,
        projectBundleService: projectBundleService,
        inputEventCaptureService: inputEventCaptureService
    )

    init() {
        self.captureMetadataManager = CaptureMetadataManager(projectBundleService: projectBundleService)
        restoreLastUsedCaptureMetadata()
        recordingCoordinator.onStateChange = { [weak self] state, message in
            guard let self else { return }
            sessionState = state
            statusMessage = message
            isBusy = state == .loadingTargets || state == .preparing || state == .stopping
            switch state {
            case .idle, .finished, .failed:
                activeRecordingTargetName = nil
                recordingStartedAt = nil
            case .loadingTargets, .preparing, .recording, .stopping:
                break
            }
        }
        recordingCoordinator.onSummaryAvailable = { [weak self] summary in
            self?.applyPlaybackSummary(summary)
        }
        recordingCoordinator.onPlaybackLoadFailure = { [weak self] message in
            self?.releasePlaybackState()
            self?.statusMessage = message
        }
        applyOutputDirectoryResolution()
        startAutomaticTargetRefresh()
    }

    deinit {
        targetRefreshTask?.cancel()
        captureMetadataManager.cancelPendingSave()
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

    var selectedEffectMarker: EffectPlanItem? {
        recordingSummary?.effectMarkers.first { $0.id == selectedEffectMarkerID }
    }

    var activePreviewMarkerID: String? {
        previewMarkerID
    }

    var isRenderedPreviewActive: Bool {
        playbackPresentationMode == .playingRenderedPreview && previewPlayer != nil
    }

    var canExportRecording: Bool {
        recordingSummary != nil && !exportState.isInProgress && sessionState != .preparing && sessionState != .recording && sessionState != .stopping
    }

    var isExportSheetPresented: Bool {
        exportState != .idle
    }

    var canTriggerMarkerPreview: Bool {
        recordingSummary != nil &&
        mainPlayer != nil &&
        !exportState.isInProgress &&
        sessionState != .preparing &&
        sessionState != .recording &&
        sessionState != .stopping
    }

    var canEditClickFocusMarkers: Bool {
        recordingSummary != nil &&
        !exportState.isInProgress &&
        sessionState != .preparing &&
        sessionState != .recording &&
        sessionState != .stopping
    }

    var canUsePlaybackTransport: Bool {
        mainPlayer != nil &&
        !isRenderingMarkerPreview &&
        !exportState.isInProgress &&
        sessionState != .preparing &&
        sessionState != .recording &&
        sessionState != .stopping
    }

    func load() async {
        markerPreviewCacheService.pruneStaleFiles()
        recordingCoordinator.onStateChange?(.loadingTargets, "Loading capture targets…")

        do {
            try await refreshCaptureTargets(silent: false)

            sessionState = .idle
            statusMessage = hasScreenRecordingPermission
                ? "Choose one display or one window."
                : "Screen Recording permission is required."
            isBusy = false
            applyOutputDirectoryResolutionIfNeeded()
            await restoreLastRecordingIfNeeded()
            await refreshLibrary()
        } catch {
            sessionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            isBusy = false
        }
    }

    func activateCaptureTarget(_ target: ShareableCaptureTarget) {
        guard target.kind == .window else { return }

        if let ownerProcessID = target.ownerProcessID,
           let app = NSRunningApplication(processIdentifier: ownerProcessID) {
            app.activate(options: [.activateAllWindows])
            return
        }

        if let ownerBundleIdentifier = target.ownerBundleIdentifier {
            let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: ownerBundleIdentifier)
            if let app = matchingApps.first {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
    }

    func requestPermission() async {
        let result = captureTargetManager.requestScreenRecordingPermission()
        hasScreenRecordingPermission = result.hasScreenRecordingPermission
        statusMessage = result.statusMessage
    }

    func startRecording() async {
        guard !isBusy, sessionState != .recording else {
            NSLog("FlowTrack Capture ignored duplicate start recording request in state=%{public}@", String(describing: sessionState))
            return
        }
        guard hasScreenRecordingPermission else {
            statusMessage = "Screen Recording permission is required before recording can start."
            return
        }
        guard let selectedTarget else {
            statusMessage = "Select one display or one window before recording."
            return
        }
        let outputResolution = projectBundleService.resolveSelectedOutputDirectory()
        if case .invalid(let message) = outputResolution {
            selectedOutputFolderPath = nil
            statusMessage = message
            return
        }
        releasePlaybackState()
        activeRecordingTargetName = selectedTarget.displayTitle
        recordingStartedAt = Date()
        await recordingCoordinator.startRecording(
            target: selectedTarget,
            outputDirectory: projectBundleService.resolvedSelectedOutputDirectory(),
            captureMetadata: currentCaptureMetadata
        )
    }

    func stopRecording() async {
        guard canStopRecording else {
            NSLog("FlowTrack Capture ignored stop recording request because recording is not active.")
            return
        }
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
        openCapture(at: bundleURL)
    }

    func exportRecording() {
        guard let summary = recordingSummary else {
            statusMessage = "Load a capture before exporting."
            return
        }
        guard canExportRecording, !exportManager.hasActiveExport else {
            NSLog("FlowTrack Capture ignored duplicate export request.")
            return
        }
        guard let outputURL = exportManager.chooseExportDestination(defaultName: summary.bundleName) else { return }

        cancelPendingMarkerPreviewRender()
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        playbackTransitionPlateState = .hidden
        playbackPresentationMode = .normal

        exportState = .preparing
        exportProgress = 0
        exportStatusMessage = "Preparing export…"
        exportedRecordingURL = nil
        exportManager.exportRecording(
            recordingURL: summary.recordingURL,
            summary: summary,
            outputURL: outputURL,
            onPhaseUpdate: { [weak self] state, progress, statusMessage in
                guard let self else { return }
                self.exportProgress = progress
                self.exportState = state
                self.exportStatusMessage = statusMessage
            },
            onCompletion: { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .completed(let outputURL):
                    self.exportedRecordingURL = outputURL
                    self.exportProgress = 1
                    self.exportState = .completed
                    self.exportStatusMessage = "Export complete."
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                case .cancelled:
                    self.exportState = .cancelled
                    self.exportStatusMessage = "Export cancelled."
                case .failed(let error):
                    self.exportState = .failed(error.localizedDescription)
                    self.exportStatusMessage = "Export failed."
                }
            }
        )
    }

    func cancelExport() {
        guard exportManager.hasActiveExport || exportState.isInProgress else { return }
        exportStatusMessage = "Cancelling export…"
        exportManager.cancelExport()
    }

    func dismissExportSheet() {
        guard !exportState.isInProgress else { return }
        exportState = .idle
        exportProgress = 0
        exportStatusMessage = nil
        exportedRecordingURL = nil
    }

    private func refreshCaptureTargets(silent: Bool) async throws {
        let refreshedSelectionID = selectedTargetID
        let result = try await captureTargetManager.loadTargets(
            selectedTargetID: refreshedSelectionID,
            silent: silent
        )
        displays = result.displays
        windows = result.windows
        if refreshedSelectionID != nil,
           result.selectedTargetID == nil,
           selectedTargetID == refreshedSelectionID {
            selectedTargetID = nil
        }
        hasScreenRecordingPermission = result.hasScreenRecordingPermission
        if let statusMessage = result.statusMessage {
            self.statusMessage = statusMessage
        }
    }

    private func startAutomaticTargetRefresh() {
        targetRefreshTask?.cancel()
        targetRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                guard sessionState == .idle else { continue }
                do {
                    try await refreshCaptureTargets(silent: true)
                } catch {
                    continue
                }
            }
        }
    }

    func revealExportInFinder() {
        guard let exportedRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportedRecordingURL])
    }

    func openLibraryCapture(_ item: CaptureLibraryItem) {
        guard item.canOpenInEditor else {
            statusMessage = item.statusMessage ?? "This capture cannot be opened until its missing files are restored."
            return
        }
        do {
            let bundleURL = try libraryManager.bundleURL(for: item)
            openCapture(at: bundleURL)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func revealLibraryCapture(_ item: CaptureLibraryItem) {
        do {
            let bundleURL = try libraryManager.bundleURL(for: item)
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startMarkerPreview(_ markerID: String) {
        guard canTriggerMarkerPreview else {
            return
        }
        guard let summary = recordingSummary,
              let marker = summary.zoomMarkers.first(where: { $0.id == markerID }),
              mainPlayer != nil else {
            return
        }
        guard marker.enabled else {
            selectedZoomMarkerID = markerID
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
        guard let plan = playbackTransportManager.togglePlan(
            canUsePlaybackTransport: canUsePlaybackTransport,
            isRenderedPreviewActive: isRenderedPreviewActive,
            playbackPresentationMode: playbackPresentationMode,
            isMainPlayerPlaying: mainPlayer?.timeControlStatus == .playing,
            currentPlaybackTime: currentPlaybackTime
        ) else { return }
        cancelPendingMarkerPreviewRender()
        if plan.shouldResetPreviewPresentation {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if plan.shouldStopPreviewPlayback {
            stopPreviewPlayback(seekMainTo: plan.stopPreviewSeekTime, retainSlate: plan.retainSlate)
        }
        if plan.shouldCancelPreviewMode {
            cancelPreviewMode()
        }
        guard let player = mainPlayer else { return }
        switch plan.playerCommand {
        case .pause:
            player.pause()
            isPlaybackActive = false
        case .play:
            player.play()
            isPlaybackActive = true
        case .none:
            break
        }
    }

    func seekPlaybackInteractively(to seconds: Double) {
        guard let plan = playbackTransportManager.interactiveSeekPlan(
            canUsePlaybackTransport: canUsePlaybackTransport,
            isRenderedPreviewActive: isRenderedPreviewActive,
            playbackPresentationMode: playbackPresentationMode,
            currentPlaybackTime: currentPlaybackTime,
            targetTime: seconds
        ) else { return }
        cancelPendingMarkerPreviewRender()
        if plan.shouldResetPreviewPresentation {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if plan.shouldStopPreviewPlayback {
            stopPreviewPlayback(seekMainTo: plan.stopPreviewSeekTime, retainSlate: plan.retainSlate)
        }
        if plan.shouldCancelPreviewMode {
            cancelPreviewMode()
        }
        if let seekTime = plan.seekTime {
            seekPlayback(to: seekTime)
        }
    }

    func jumpPlaybackToStart() {
        guard let plan = playbackTransportManager.jumpToStartPlan(
            canUsePlaybackTransport: canUsePlaybackTransport,
            isRenderedPreviewActive: isRenderedPreviewActive,
            playbackPresentationMode: playbackPresentationMode,
            currentPlaybackTime: currentPlaybackTime
        ) else { return }
        cancelPendingMarkerPreviewRender()
        if plan.shouldResetPreviewPresentation {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if plan.shouldStopPreviewPlayback {
            stopPreviewPlayback(seekMainTo: plan.stopPreviewSeekTime, retainSlate: plan.retainSlate)
        }
        if plan.shouldCancelPreviewMode {
            cancelPreviewMode()
        }
        if let seekTime = plan.seekTime {
            seekPlayback(to: seekTime)
        }
    }

    func cancelPlaybackPreview() {
        let plan = playbackTransportManager.cancelPreviewPlan(
            playbackPresentationMode: playbackPresentationMode,
            currentPlaybackTime: currentPlaybackTime
        )
        cancelPendingMarkerPreviewRender()
        if plan.shouldResetPreviewPresentation {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if plan.shouldStopPreviewPlayback {
            stopPreviewPlayback(seekMainTo: plan.stopPreviewSeekTime, retainSlate: plan.retainSlate)
        }
        if plan.shouldCancelPreviewMode {
            cancelPreviewMode()
        }
    }

    func beginTimelineScrub() {
        guard let plan = timelineScrubManager.beginScrubPlan(
            canUsePlaybackTransport: canUsePlaybackTransport,
            hasMainPlayer: mainPlayer != nil,
            isTimelineScrubbing: isTimelineScrubbing,
            playbackPresentationMode: playbackPresentationMode,
            currentPlaybackTime: currentPlaybackTime,
            isMainPlayerPlaying: mainPlayer?.timeControlStatus == .playing
        ) else { return }
        cancelPendingMarkerPreviewRender()
        if plan.shouldResetPreviewPresentation {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if plan.shouldStopPreviewPlayback {
            stopPreviewPlayback(seekMainTo: plan.stopPreviewSeekTime, retainSlate: plan.retainSlate)
        }
        if plan.shouldCancelPreviewMode {
            cancelPreviewMode()
        }
        wasPlayingBeforeTimelineScrub = plan.wasPlayingBeforeTimelineScrub
        if plan.shouldPause {
            mainPlayer?.pause()
        }
        if plan.shouldSetPlaybackInactive {
            isPlaybackActive = false
        }
        isTimelineScrubbing = plan.isTimelineScrubbing
        manualSelectionSuppressionUntil = Date().addingTimeInterval(plan.suppressionInterval)
    }

    func updateTimelineScrub(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
        guard let plan = timelineScrubManager.updateScrubPlan(
            isTimelineScrubbing: isTimelineScrubbing,
            targetTime: seconds,
            snappedMarkerID: snappedMarkerID,
            snappedEffectMarkerID: snappedEffectMarkerID
        ) else { return }
        selectedZoomMarkerID = plan.selectedZoomMarkerID
        selectedEffectMarkerID = plan.selectedEffectMarkerID
        seekPlayback(to: plan.targetTime)
    }

    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
        guard let plan = timelineScrubManager.endScrubPlan(
            isTimelineScrubbing: isTimelineScrubbing,
            targetTime: seconds,
            snappedMarkerID: snappedMarkerID,
            snappedEffectMarkerID: snappedEffectMarkerID,
            wasPlayingBeforeTimelineScrub: wasPlayingBeforeTimelineScrub
        ) else { return }
        selectedZoomMarkerID = plan.selectedZoomMarkerID
        selectedEffectMarkerID = plan.selectedEffectMarkerID
        seekPlayback(to: plan.targetTime)
        isTimelineScrubbing = plan.isTimelineScrubbing
        manualSelectionSuppressionUntil = Date().addingTimeInterval(plan.suppressionInterval)
        if plan.shouldResumePlayback {
            mainPlayer?.play()
            isPlaybackActive = true
        }
    }

    func seekTimelineDirectly(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
        guard let plan = timelineScrubManager.directSeekPlan(
            canUsePlaybackTransport: canUsePlaybackTransport,
            isRenderedPreviewActive: isRenderedPreviewActive,
            playbackPresentationMode: playbackPresentationMode,
            currentPlaybackTime: currentPlaybackTime,
            targetTime: seconds,
            snappedMarkerID: snappedMarkerID,
            snappedEffectMarkerID: snappedEffectMarkerID
        ) else { return }
        cancelPendingMarkerPreviewRender()
        if plan.shouldResetPreviewPresentation {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        if plan.shouldStopPreviewPlayback {
            stopPreviewPlayback(seekMainTo: plan.stopPreviewSeekTime, retainSlate: plan.retainSlate)
        }
        if plan.shouldCancelPreviewMode {
            cancelPreviewMode()
        }
        selectedZoomMarkerID = plan.selectedZoomMarkerID
        selectedEffectMarkerID = plan.selectedEffectMarkerID
        if let suppressionInterval = plan.suppressionInterval {
            manualSelectionSuppressionUntil = Date().addingTimeInterval(suppressionInterval)
        }
        seekPlayback(to: plan.targetTime)
    }

    func nudgeSelectedTimelineMarker(by delta: Double) {
        guard canEditClickFocusMarkers, let markerID = selectedZoomMarkerID else { return }
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        mainPlayer?.pause()
        publishOnNextRunLoop { [weak self] in
            self?.isPlaybackActive = false
        }
        manualSelectionSuppressionUntil = Date().addingTimeInterval(0.2)
        moveMarker(
            markerID,
            to: selectedMarkerTimestamp(for: markerID) + (delta * timelineMarkerNudgeInterval),
            persist: true,
            seekPlaybackHead: true
        )
    }

    func nudgeSelectedEffectTimelineMarker(by delta: Double) {
        guard let summary = recordingSummary,
              let markerID = selectedEffectMarkerID,
              let index = summary.effectMarkers.firstIndex(where: { $0.id == markerID }) else { return }

        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        mainPlayer?.pause()
        publishOnNextRunLoop { [weak self] in
            self?.isPlaybackActive = false
        }

        let maxDuration = max(summary.duration ?? 0, 0)
        let currentMarker = summary.effectMarkers[index]
        let timelineOffsetToStart = currentMarker.startTime - currentMarker.sourceEventTimestamp
        let timelineOffsetToEnd = currentMarker.endTime - currentMarker.sourceEventTimestamp
        let targetTimestamp = min(
            max(currentMarker.sourceEventTimestamp + (delta * timelineMarkerNudgeInterval), 0),
            maxDuration
        )

        var effectMarkers = summary.effectMarkers
        effectMarkers[index].sourceEventTimestamp = targetTimestamp
        effectMarkers[index].startTime = max(0, targetTimestamp + timelineOffsetToStart)
        effectMarkers[index].endTime = max(effectMarkers[index].startTime + 0.05, min(maxDuration, targetTimestamp + timelineOffsetToEnd))

        manualSelectionSuppressionUntil = Date().addingTimeInterval(0.2)
        saveEffectMarkers(effectMarkers, basedOn: summary)
        seekPlayback(to: effectMarkers[index].sourceEventTimestamp)
    }

    func setSelectedMarkerEnabled(_ enabled: Bool) {
        updateSelectedMarker { marker in
            marker.enabled = enabled
        }
    }

    func setMarkerEnabled(_ enabled: Bool, for markerID: String) {
        updateMarker(withID: markerID) { marker in
            marker.enabled = enabled
        }
    }

    func toggleMarkerEnabled(_ markerID: String) {
        updateMarker(withID: markerID) { marker in
            marker.enabled.toggle()
        }
    }

    func setMarkerName(_ markerName: String?, for markerID: String) {
        updateMarker(withID: markerID) { marker in
            let trimmed = markerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            marker.markerName = trimmed.isEmpty ? nil : trimmed
        }
    }

    func setSelectedMarkerZoomScale(_ zoomScale: Double) {
        updateSelectedMarker { marker in
            marker.zoomScale = zoomScale
        }
    }

    func setSelectedMarkerLeadInTime(_ leadInTime: Double) {
        updateSelectedMarker { marker in
            marker.leadInTime = min(max(leadInTime, 0), 20.0)
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
            if zoomType == .noZoom {
                marker.noZoomFallbackMode = defaultNoZoomFallbackMode
            }
            syncMarkerTiming(&marker)
        }
    }

    func setSelectedMarkerBounceAmount(_ bounceAmount: Double) {
        updateSelectedMarker { marker in
            marker.bounceAmount = min(max(bounceAmount, 0), 1)
        }
    }

    func setSelectedMarkerNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
        updateSelectedMarker { marker in
            marker.noZoomFallbackMode = fallbackMode
        }
    }

    func setSelectedMarkerNoZoomOverflowRegion(_ region: NoZoomOverflowRegion?) {
        updateSelectedMarker { marker in
            marker.noZoomOverflowRegion = region
        }
    }

    func clearSelectedMarkerNoZoomOverflowRegion() {
        setSelectedMarkerNoZoomOverflowRegion(nil)
    }

    func setSelectedEffectFocusRegion(_ region: EffectFocusRegion?) {
        guard let summary = recordingSummary,
              let selectedEffectMarkerID,
              let index = summary.effectMarkers.firstIndex(where: { $0.id == selectedEffectMarkerID }) else {
            return
        }

        var effectMarkers = summary.effectMarkers
        effectMarkers[index].focusRegion = region
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    func clearSelectedEffectFocusRegion() {
        setSelectedEffectFocusRegion(nil)
    }

    func selectEffectMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
        guard let summary = recordingSummary,
              let marker = summary.effectMarkers.first(where: { $0.id == markerID }) else {
            return
        }

        selectedEffectMarkerID = markerID
        if seekPlaybackHead {
            seekPlayback(to: marker.snapTime)
        } else {
            currentPlaybackTime = marker.snapTime
        }
    }

    func selectZoomMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
        guard let summary = recordingSummary,
              let marker = summary.zoomMarkers.first(where: { $0.id == markerID }) else {
            return
        }

        if isPlaybackActive {
            mainPlayer?.pause()
            isPlaybackActive = false
        }

        if seekPlaybackHead {
            seekTimelineDirectly(to: marker.sourceEventTimestamp, snappedMarkerID: markerID, snappedEffectMarkerID: nil)
        } else {
            selectedZoomMarkerID = markerID
            currentPlaybackTime = marker.sourceEventTimestamp
        }
    }

    func previewEffectMarker(_ markerID: String) {
        guard let summary = recordingSummary,
              let marker = summary.effectMarkers.first(where: { $0.id == markerID }),
              let player = mainPlayer else {
            return
        }

        cancelPendingMarkerPreviewRender()
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        playbackTransitionPlateState = .hidden
        playbackPresentationMode = .normal

        selectedEffectMarkerID = markerID
        previewEffectMarkerID = markerID
        previewEffectEndTime = marker.endTime
        manualSelectionSuppressionUntil = Date().addingTimeInterval(max(marker.endTime - marker.startTime, 0.35) + 0.15)
        seekPlayback(to: marker.startTime)
        player.play()
        isPlaybackActive = true
    }

    func startEffectMarkerPreview(_ markerID: String) {
        guard canTriggerMarkerPreview else {
            return
        }
        guard let summary = recordingSummary,
              let marker = summary.effectMarkers.first(where: { $0.id == markerID }),
              mainPlayer != nil else {
            return
        }
        guard marker.enabled else {
            selectedEffectMarkerID = markerID
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
        selectedEffectMarkerID = markerID
        renderingPreviewEffectMarkerID = markerID
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        playbackPresentationMode = .renderingPreview
        showPlaybackTransitionPlateImmediately()
        manualSelectionSuppressionUntil = Date().addingTimeInterval(2.0)
        seekMainPlayback(to: max(0, marker.startTime))

        markerPreviewRenderTask = Task { [weak self] in
            guard let self else { return }

            do {
                if let cachedPreview = try await markerPreviewCacheService.cachedEffectPreview(
                    for: summary.recordingURL,
                    summary: summary,
                    marker: marker
                ) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard self.renderingPreviewEffectMarkerID == markerID else { return }
                        self.isRenderingMarkerPreview = false
                        self.markerPreviewStatusMessage = nil
                        self.playRenderedEffectPreview(cachedPreview, markerID: markerID)
                    }
                    return
                }

                await MainActor.run {
                    guard self.renderingPreviewEffectMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = true
                    self.markerPreviewStatusMessage = "Rendering preview…"
                    self.playbackPresentationMode = .renderingPreview
                    self.showPlaybackTransitionPlateImmediately()
                }

                let renderedPreview = try await markerPreviewRenderService.renderEffectPreview(
                    recordingURL: summary.recordingURL,
                    summary: summary,
                    selectedMarker: marker
                )
                let cachedPreview = try await markerPreviewCacheService.storeEffectPreview(
                    renderedPreview,
                    for: summary.recordingURL,
                    summary: summary,
                    marker: marker
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.renderingPreviewEffectMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = false
                    self.markerPreviewStatusMessage = nil
                    self.playRenderedEffectPreview(cachedPreview, markerID: markerID)
                }
            } catch is CancellationError {
                await MainActor.run {
                    if self.renderingPreviewEffectMarkerID == markerID {
                        self.isRenderingMarkerPreview = false
                        self.markerPreviewStatusMessage = nil
                        self.renderingPreviewEffectMarkerID = nil
                        self.playbackPresentationMode = .normal
                        self.playbackTransitionPlateState = .hidden
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.renderingPreviewEffectMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = false
                    self.markerPreviewStatusMessage = nil
                    self.playbackPresentationMode = .normal
                    self.playbackTransitionPlateState = .hidden
                    self.statusMessage = "Rendered preview failed. Using live preview."
                    self.previewEffectMarker(markerID)
                }
            }
        }
    }

    func setSelectedEffectMarkerEnabled(_ enabled: Bool) {
        updateSelectedEffectMarker { marker in
            marker.enabled = enabled
        }
    }

    func toggleEffectMarkerEnabled(_ markerID: String) {
        updateEffectMarker(withID: markerID) { marker in
            marker.enabled.toggle()
        }
    }

    func setEffectMarkerName(_ markerName: String?, for markerID: String) {
        updateEffectMarker(withID: markerID) { marker in
            let trimmed = markerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            marker.markerName = trimmed.isEmpty ? nil : trimmed
        }
    }

    func setSelectedEffectStyle(_ style: EffectStyle) {
        updateSelectedEffectMarker { marker in
            marker.style = style
        }
    }

    func setSelectedEffectAmount(_ amount: Double) {
        updateSelectedEffectMarker { marker in
            marker.amount = min(max(amount, 0), 1)
        }
    }

    func setSelectedEffectBlurAmount(_ amount: Double) {
        updateSelectedEffectMarker { marker in
            let clampedAmount = min(max(amount, 0), 1)
            marker.blurAmount = clampedAmount
            if marker.style == .blur {
                marker.amount = clampedAmount
            }
        }
    }

    func setSelectedEffectDarkenAmount(_ amount: Double) {
        updateSelectedEffectMarker { marker in
            let clampedAmount = min(max(amount, 0), 1)
            marker.darkenAmount = clampedAmount
            if marker.style == .darken {
                marker.amount = clampedAmount
            }
        }
    }

    func setSelectedEffectTintAmount(_ amount: Double) {
        updateSelectedEffectMarker { marker in
            let clampedAmount = min(max(amount, 0), 1)
            marker.tintAmount = clampedAmount
            if marker.style == .tint {
                marker.amount = clampedAmount
            }
        }
    }

    func setSelectedEffectFadeInDuration(_ duration: Double) {
        updateSelectedEffectMarker { marker in
            marker.fadeInDuration = min(max(duration, 0.05), 3.0)
        }
    }

    func setSelectedEffectFadeOutDuration(_ duration: Double) {
        updateSelectedEffectMarker { marker in
            marker.fadeOutDuration = min(max(duration, 0.05), 3.0)
        }
    }

    func setSelectedEffectHoldDuration(_ duration: Double) {
        updateSelectedEffectMarker { marker in
            marker.endTime = max(marker.sourceEventTimestamp + min(max(duration, 0.05), 10.0), marker.startTime + 0.05)
        }
    }

    func setSelectedEffectCornerRadius(_ radius: Double) {
        updateSelectedEffectMarker { marker in
            marker.cornerRadius = min(max(radius, 0), 80)
        }
    }

    func setSelectedEffectFeather(_ feather: Double) {
        updateSelectedEffectMarker { marker in
            marker.feather = min(max(feather, 0), 60)
        }
    }

    func setSelectedEffectTintColor(_ tintColor: EffectTintColor) {
        updateSelectedEffectMarker { marker in
            marker.tintColor = tintColor
        }
    }

    func addEffectMarker(at timestamp: Double? = nil) {
        guard let summary = recordingSummary else { return }

        let eventTimestamp = min(
            max(timestamp ?? currentPlaybackTime, 0),
            max(summary.duration ?? currentPlaybackTime, currentPlaybackTime)
        )
        let maxDuration = max(summary.duration ?? (eventTimestamp + 1.0), eventTimestamp)

        var effectMarkers = summary.effectMarkers
        let marker = EffectPlanItem(
            id: nextEffectMarkerID(from: effectMarkers),
            markerName: nil,
            sourceEventTimestamp: eventTimestamp,
            startTime: max(0, eventTimestamp - 0.35),
            endTime: min(eventTimestamp + 1.0, maxDuration),
            fadeInDuration: 0.18,
            fadeOutDuration: 0.24,
            enabled: true,
            displayOrder: nextEffectDisplayOrder(from: effectMarkers),
            style: .blurDarken,
            amount: 0.55,
            blurAmount: 0.55,
            darkenAmount: 0.55,
            tintAmount: 0.55,
            cornerRadius: 18,
            feather: 0,
            tintColor: .defaultTint,
            focusRegion: nil
        )
        effectMarkers.append(marker)
        selectedEffectMarkerID = marker.id
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    func deleteSelectedEffectMarker() {
        guard let summary = recordingSummary, let selectedEffectMarkerID else { return }
        var effectMarkers = summary.effectMarkers
        effectMarkers.removeAll { $0.id == selectedEffectMarkerID }
        self.selectedEffectMarkerID = nil
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    func reorderEffectMarkerList(to orderedMarkerIDs: [String]) {
        guard let summary = recordingSummary else { return }

        var effectMarkers = summary.effectMarkers
        let orderedLookup = Dictionary(uniqueKeysWithValues: orderedMarkerIDs.enumerated().map { ($1, $0) })
        var didChange = false

        for index in effectMarkers.indices {
            guard let displayOrder = orderedLookup[effectMarkers[index].id],
                  effectMarkers[index].displayOrder != displayOrder else {
                continue
            }
            effectMarkers[index].displayOrder = displayOrder
            didChange = true
        }

        guard didChange else { return }
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    func setDefaultNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
        defaultNoZoomFallbackMode = fallbackMode
        UserDefaults.standard.set(fallbackMode.rawValue, forKey: defaultNoZoomFallbackModeKey)
    }

    func setSelectedMarkerClickPulseEnabled(_ enabled: Bool) {
        let markerID = selectedZoomMarkerID
        updateSelectedMarker { marker in
            guard marker.isClickFocus else { return }
            marker.clickPulse = enabled ? (marker.clickPulse ?? .defaultConfiguration) : nil
        }
        if enabled, let markerID {
            startMarkerPreview(markerID)
        }
    }

    func setSelectedMarkerClickPulsePreset(_ preset: ClickPulsePreset) {
        let markerID = selectedZoomMarkerID
        updateSelectedMarker { marker in
            guard marker.isClickFocus else { return }
            marker.clickPulse = ClickPulseConfiguration(preset: preset)
        }
        if let markerID {
            startMarkerPreview(markerID)
        }
    }

    func setCurrentCaptureTitle(_ title: String) {
        captureTitle = title
        scheduleMetadataSave()
    }

    func setCurrentCaptureCollectionName(_ collectionName: String) {
        self.collectionName = collectionName
        scheduleMetadataSave()
    }

    func setCurrentCaptureProjectName(_ projectName: String) {
        self.projectName = projectName
        scheduleMetadataSave()
    }

    func setCurrentCaptureType(_ captureType: CaptureType) {
        self.captureType = captureType
        scheduleMetadataSave()
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
        duplicate.displayOrder = nextMarkerDisplayOrder(from: markers)
        markers.append(duplicate)
        selectedZoomMarkerID = duplicate.id
        saveZoomMarkers(markers, basedOn: summary)
    }

    func addClickFocusMarker(at sourcePoint: CGPoint, timestamp: Double? = nil) {
        guard let summary = recordingSummary else { return }

        let safeWidth = max(summary.contentCoordinateSize.width, 1)
        let safeHeight = max(summary.contentCoordinateSize.height, 1)
        let clampedPoint = CGPoint(
            x: min(max(sourcePoint.x, 0), safeWidth),
            y: min(max(sourcePoint.y, 0), safeHeight)
        )
        let eventTimestamp = min(max(timestamp ?? currentPlaybackTime, 0), max(summary.duration ?? currentPlaybackTime, currentPlaybackTime))
        let leadInTime = 0.15
        let zoomInDuration = 0.30
        let holdDuration = 1.15
        let zoomOutDuration = 0.40
        let startTime = max(0, eventTimestamp - leadInTime - zoomInDuration)
        let holdUntil = eventTimestamp + holdDuration
        let endTime = holdUntil + zoomOutDuration

        var markers = summary.zoomMarkers
        let marker = ZoomPlanItem(
            id: nextZoomMarkerID(from: markers),
            type: "zoom",
            markerName: nil,
            markerKind: .clickFocus,
            sourceEventTimestamp: eventTimestamp,
            rawX: nil,
            rawY: nil,
            centerX: clampedPoint.x,
            centerY: clampedPoint.y,
            zoomScale: 1.8,
            startTime: startTime,
            holdUntil: holdUntil,
            endTime: endTime,
            leadInTime: leadInTime,
            zoomInDuration: zoomInDuration,
            holdDuration: holdDuration,
            zoomOutDuration: zoomOutDuration,
            enabled: true,
            duration: leadInTime + zoomInDuration + holdDuration + zoomOutDuration,
            easeStyle: .smooth,
            zoomType: .inOut,
            bounceAmount: 0.35,
            noZoomFallbackMode: defaultNoZoomFallbackMode,
            noZoomOverflowRegion: nil,
            displayOrder: nextMarkerDisplayOrder(from: markers)
        )
        markers.append(marker)
        selectedZoomMarkerID = marker.id
        saveZoomMarkers(markers, basedOn: summary)
    }

    func reorderMarkerList(to orderedMarkerIDs: [String]) {
        guard let summary = recordingSummary else { return }

        var markers = summary.zoomMarkers
        let orderedLookup = Dictionary(uniqueKeysWithValues: orderedMarkerIDs.enumerated().map { ($1, $0) })
        var didChange = false

        for index in markers.indices {
            guard let displayOrder = orderedLookup[markers[index].id], markers[index].displayOrder != displayOrder else {
                continue
            }
            markers[index].displayOrder = displayOrder
            didChange = true
        }

        guard didChange else { return }
        saveZoomMarkers(markers, basedOn: summary)
    }

    func moveSelectedMarker(to sourcePoint: CGPoint) {
        updateSelectedMarker { marker in
            marker.rawX = nil
            marker.rawY = nil
            marker.centerX = sourcePoint.x
            marker.centerY = sourcePoint.y
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

    private var currentCaptureMetadata: CaptureMetadata {
        CaptureMetadata(
            collectionName: collectionName,
            projectName: projectName,
            captureType: captureType,
            captureTitle: captureTitle
        )
    }

    private func restoreLastUsedCaptureMetadata() {
        let defaults = UserDefaults.standard
        collectionName = defaults.string(forKey: lastCollectionNameKey) ?? "Default Collection"
        projectName = defaults.string(forKey: lastProjectNameKey) ?? "General Project"
        if let rawValue = defaults.string(forKey: lastCaptureTypeKey),
           let restoredType = CaptureType(rawValue: rawValue) {
            captureType = restoredType
        }
        if let rawValue = defaults.string(forKey: defaultNoZoomFallbackModeKey),
           let restoredMode = NoZoomFallbackMode(rawValue: rawValue) {
            defaultNoZoomFallbackMode = restoredMode
        }
    }

    private func persistLastUsedCaptureMetadata() {
        let defaults = UserDefaults.standard
        defaults.set(currentCaptureMetadata.resolvedCollectionName, forKey: lastCollectionNameKey)
        defaults.set(currentCaptureMetadata.resolvedProjectName, forKey: lastProjectNameKey)
        defaults.set(captureType.rawValue, forKey: lastCaptureTypeKey)
    }

    private func scheduleMetadataSave() {
        guard let summary = recordingSummary else { return }
        let metadata = currentCaptureMetadata
        let bundleURL = summary.bundleURL
        captureMetadataManager.scheduleSave(
            bundleURL: bundleURL,
            metadata: metadata,
            onSaved: { [weak self] updatedManifest in
                await self?.applySavedCaptureMetadata(updatedManifest, bundleURL: bundleURL)
            },
            onError: { [weak self] error in
                self?.statusMessage = "Could not save capture info: \(error.localizedDescription)"
            }
        )
    }

    private func applySavedCaptureMetadata(_ updatedManifest: ProjectManifest, bundleURL: URL) async {
        guard let summary = recordingSummary, summary.bundleURL == bundleURL else { return }

        let updatedSummary = RecordingInspectionSummary(
            bundleURL: summary.bundleURL,
            bundleName: summary.bundleName,
            captureID: summary.captureID,
            collectionName: updatedManifest.collectionName,
            projectName: updatedManifest.projectName,
            captureType: updatedManifest.captureType,
            captureTitle: updatedManifest.captureTitle,
            createdAt: updatedManifest.createdAt,
            updatedAt: updatedManifest.updatedAt,
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
            zoomMarkers: summary.zoomMarkers,
            effectMarkers: summary.effectMarkers
        )
        recordingSummary = updatedSummary
        captureTitle = updatedManifest.captureTitle
        collectionName = updatedManifest.collectionName
        projectName = updatedManifest.projectName
        captureType = updatedManifest.captureType

        do {
            try projectBundleService.registerCaptureInLibrary(updatedSummary)
            await refreshLibrary()
        } catch {
            statusMessage = "Could not save capture info: \(error.localizedDescription)"
        }
    }

    private func openCapture(at bundleURL: URL) {
        Task {
            do {
                let summary = try await projectBundleService.loadRecordingInspection(from: bundleURL)
                _ = projectBundleService.persistLastRecordingBundle(bundleURL)
                try loadPlayback(summary)
                activeRecordingTargetName = nil
                recordingStartedAt = nil
                statusMessage = "Loaded \(summary.displayTitle)"
            } catch {
                releasePlaybackState()
                statusMessage = "Could not open capture: \(error.localizedDescription)"
            }
        }
    }

    func refreshLibrary() async {
        do {
            let snapshot = try await libraryManager.loadLibrarySnapshot()
            libraryItems = snapshot.items
            libraryStatusMessage = snapshot.statusMessage
        } catch {
            libraryItems = []
            libraryStatusMessage = "Library could not be loaded."
            statusMessage = error.localizedDescription
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
                    statusMessage = "Could not restore the last capture: \(error.localizedDescription)"
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
            try projectBundleService.registerCaptureInLibrary(summary)
            try loadPlayback(summary)
            Task {
                await refreshLibrary()
            }
        } catch {
            releasePlaybackState()
            statusMessage = "Could not load the finished capture into Edit: \(error.localizedDescription)"
        }
    }

    private func loadPlayback(_ summary: RecordingInspectionSummary) throws {
        releasePlaybackState()

        guard FileManager.default.fileExists(atPath: summary.recordingURL.path) else {
            throw NSError(
                domain: "CaptureSetupViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This capture is missing its recording.mov file."]
            )
        }

        let playbackScopeURL = try projectBundleService.beginPlaybackAccess(for: summary.bundleURL)
        if !FileManager.default.isReadableFile(atPath: summary.recordingURL.path) {
            projectBundleService.endPlaybackAccess(playbackScopeURL)
            throw NSError(
                domain: "CaptureSetupViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This capture could not be opened because the recording file is not readable."]
            )
        }

        activePlaybackScopeURL = playbackScopeURL

        recordingSummary = summary
        mainPlayer = AVPlayer(playerItem: AVPlayerItem(url: summary.recordingURL))
        previewPlayer = nil
        collectionName = summary.collectionName
        projectName = summary.projectName
        captureType = summary.captureType
        captureTitle = summary.captureTitle
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
        captureMetadataManager.cancelPendingSave()
        exportManager.reset()
        exportState = .idle
        exportProgress = 0
        exportStatusMessage = nil
        exportedRecordingURL = nil
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

    private func seekPlayback(to seconds: Double) {
        guard let player = mainPlayer else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        let clampedSeconds = max(seconds, 0)
        publishOnNextRunLoop { [weak self] in
            self?.currentPlaybackTime = clampedSeconds
        }
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

    private func updateSelectedEffectMarker(_ mutate: (inout EffectPlanItem) -> Void) {
        guard let summary = recordingSummary, let selectedEffectMarkerID,
              let index = summary.effectMarkers.firstIndex(where: { $0.id == selectedEffectMarkerID }) else {
            return
        }

        var effectMarkers = summary.effectMarkers
        mutate(&effectMarkers[index])
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    private func updateMarker(withID markerID: String, mutate: (inout ZoomPlanItem) -> Void) {
        guard let summary = recordingSummary,
              let index = summary.zoomMarkers.firstIndex(where: { $0.id == markerID }) else {
            return
        }

        var markers = summary.zoomMarkers
        mutate(&markers[index])
        saveZoomMarkers(markers, basedOn: summary)
    }

    private func updateEffectMarker(withID markerID: String, mutate: (inout EffectPlanItem) -> Void) {
        guard let summary = recordingSummary,
              let index = summary.effectMarkers.firstIndex(where: { $0.id == markerID }) else {
            return
        }

        var effectMarkers = summary.effectMarkers
        mutate(&effectMarkers[index])
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    private func saveZoomMarkers(_ markers: [ZoomPlanItem], basedOn summary: RecordingInspectionSummary) {
        do {
            let envelope = ZoomPlanEnvelope(
                schemaVersion: 1,
                source: "events.json",
                items: markers,
                effectItems: summary.effectMarkers
            )
            try projectBundleService.saveZoomPlan(envelope, in: summary.bundleURL)
            let updatedSummary = summaryWithMarkers(markers, basedOn: summary)
            recordingSummary = updatedSummary
        } catch {
            statusMessage = "Could not save zoomPlan.json: \(error.localizedDescription)"
        }
    }

    private func moveMarker(_ markerID: String, to seconds: Double, persist: Bool, seekPlaybackHead: Bool) {
        guard let summary = recordingSummary,
              let index = summary.zoomMarkers.firstIndex(where: { $0.id == markerID }) else {
            return
        }

        var markers = summary.zoomMarkers
        let maxDuration = max(summary.duration ?? 0, 0)
        markers[index].sourceEventTimestamp = min(max(seconds, 0), maxDuration)
        syncMarkerTiming(&markers[index])
        publishOnNextRunLoop { [weak self] in
            self?.selectedZoomMarkerID = markerID
        }

        if persist {
            saveZoomMarkers(markers, basedOn: summary)
        } else {
            let updatedSummary = summaryWithMarkers(markers, basedOn: summary)
            publishOnNextRunLoop { [weak self] in
                self?.recordingSummary = updatedSummary
            }
        }

        if seekPlaybackHead {
            seekPlayback(to: markers[index].sourceEventTimestamp)
        } else {
            currentPlaybackTime = markers[index].sourceEventTimestamp
        }
    }

    private func selectedMarkerTimestamp(for markerID: String) -> Double {
        recordingSummary?.zoomMarkers.first(where: { $0.id == markerID })?.sourceEventTimestamp ?? currentPlaybackTime
    }

    private func nextMarkerDisplayOrder(from markers: [ZoomPlanItem]) -> Int {
        markers.enumerated().map { $0.element.displayOrder ?? $0.offset }.max().map { $0 + 1 } ?? 0
    }

    private func nextEffectDisplayOrder(from markers: [EffectPlanItem]) -> Int {
        markers.enumerated().map { $0.element.displayOrder ?? $0.offset }.max().map { $0 + 1 } ?? 0
    }

    private func summaryWithMarkers(_ markers: [ZoomPlanItem], basedOn summary: RecordingInspectionSummary) -> RecordingInspectionSummary {
        RecordingInspectionSummary(
            bundleURL: summary.bundleURL,
            bundleName: summary.bundleName,
            captureID: summary.captureID,
            collectionName: summary.collectionName,
            projectName: summary.projectName,
            captureType: summary.captureType,
            captureTitle: summary.captureTitle,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
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
            zoomMarkers: markers,
            effectMarkers: summary.effectMarkers
        )
    }

    private func saveEffectMarkers(_ effectMarkers: [EffectPlanItem], basedOn summary: RecordingInspectionSummary) {
        do {
            let envelope = ZoomPlanEnvelope(
                schemaVersion: 1,
                source: "events.json",
                items: summary.zoomMarkers,
                effectItems: effectMarkers
            )
            try projectBundleService.saveZoomPlan(envelope, in: summary.bundleURL)
            let updatedSummary = RecordingInspectionSummary(
                bundleURL: summary.bundleURL,
                bundleName: summary.bundleName,
                captureID: summary.captureID,
                collectionName: summary.collectionName,
                projectName: summary.projectName,
                captureType: summary.captureType,
                captureTitle: summary.captureTitle,
                createdAt: summary.createdAt,
                updatedAt: summary.updatedAt,
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
                zoomMarkers: summary.zoomMarkers,
                effectMarkers: effectMarkers
            )
            publishOnNextRunLoop { [weak self] in
                self?.recordingSummary = updatedSummary
            }
        } catch {
            statusMessage = "Could not save zoomPlan.json: \(error.localizedDescription)"
        }
    }

    private func nextEffectMarkerID(from markers: [EffectPlanItem]) -> String {
        let maxIndex = markers.compactMap { marker in
            Int(marker.id.replacingOccurrences(of: "effect-", with: ""))
        }.max() ?? 0
        return String(format: "effect-%04d", maxIndex + 1)
    }

    private func syncMarkerTiming(_ marker: inout ZoomPlanItem) {
        marker.leadInTime = min(max(marker.leadInTime, 0), 20.0)
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
        case .noZoom:
            marker.startTime = max(0, marker.sourceEventTimestamp - marker.leadInTime - marker.zoomInDuration)
            marker.holdUntil = marker.sourceEventTimestamp + marker.holdDuration
            marker.endTime = marker.holdUntil
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
        case .inOnly, .noZoom:
            return (startTime, max(marker.holdUntil, marker.sourceEventTimestamp))
        }
    }

    private func cancelPreviewMode() {
        previewMarkerID = nil
        previewEndTime = nil
        previewEffectMarkerID = nil
        previewEffectEndTime = nil
    }

    private func cancelPendingMarkerPreviewRender() {
        markerPreviewRenderTask?.cancel()
        markerPreviewRenderTask = nil
        publishOnNextRunLoop { [weak self] in
            self?.isRenderingMarkerPreview = false
            self?.markerPreviewStatusMessage = nil
        }
        renderingPreviewMarkerID = nil
        renderingPreviewEffectMarkerID = nil
    }

    private func publishOnNextRunLoop(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
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
            try? await Task.sleep(for: .seconds(self?.previewTransitionHoldDuration ?? 1.0))
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

    private func playRenderedEffectPreview(_ renderedPreview: RenderedMarkerPreview, markerID: String) {
        cancelPreviewSurfaceTeardown()
        cancelPlaybackTransitionTask()
        guard previewPlayer == nil else {
            stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: true)
            playRenderedEffectPreview(renderedPreview, markerID: markerID)
            return
        }
        guard let mainPlayer else { return }
        cleanupRenderedPreviewFile()
        activeRenderedPreviewURL = renderedPreview.outputURL
        activeRenderedPreviewShouldDelete = renderedPreview.deleteWhenFinished
        renderedPreviewSourceStartTime = renderedPreview.sourceStartTime
        selectedEffectMarkerID = markerID
        previewEffectMarkerID = markerID
        previewEffectEndTime = renderedPreview.sourceEndTime
        renderingPreviewEffectMarkerID = nil
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
            try? await Task.sleep(for: .seconds(self?.previewTransitionHoldDuration ?? 1.0))
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

        if isRenderingMarkerPreview, let renderingPreviewEffectMarkerID {
            selectedEffectMarkerID = renderingPreviewEffectMarkerID
            return
        }

        guard playbackPresentationMode == .normal else {
            return
        }

        if let previewEffectEndTime, let previewEffectMarkerID {
            selectedEffectMarkerID = previewEffectMarkerID
            if currentTime >= previewEffectEndTime - 0.02 {
                player.pause()
                isPlaybackActive = false
                cancelPreviewMode()
            }
            return
        }

        updateSelectedMarkerForTime(currentTime)
        updateSelectedEffectMarkerForTime(currentTime)
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

        if let previewEffectEndTime, let previewEffectMarkerID {
            selectedEffectMarkerID = previewEffectMarkerID
            if currentTime >= previewEffectEndTime - 0.02 {
                player.pause()
                isPlaybackActive = false
                cancelPreviewMode()
                stopPreviewPlayback(seekMainTo: previewEffectEndTime, retainSlate: true)
            }
            return
        }

        updateSelectedMarkerForTime(currentTime)
        updateSelectedEffectMarkerForTime(currentTime)
    }

    private func updateSelectedMarkerForTime(_ currentTime: Double) {
        guard let summary = recordingSummary, !summary.zoomMarkers.isEmpty else {
            selectedZoomMarkerID = nil
            return
        }

        if let manualSelectionSuppressionUntil, Date() < manualSelectionSuppressionUntil {
            return
        }

        let eligibleMarkers = summary.zoomMarkers.filter { $0.enabled }
        let markers = (eligibleMarkers.isEmpty ? summary.zoomMarkers : eligibleMarkers)
            .sorted { lhs, rhs in
                let leftTimeline = SharedMotionEngine.zoomTimeline(for: lhs)
                let rightTimeline = SharedMotionEngine.zoomTimeline(for: rhs)
                if leftTimeline.startTime == rightTimeline.startTime {
                    if lhs.sourceEventTimestamp == rhs.sourceEventTimestamp {
                        return lhs.id < rhs.id
                    }
                    return lhs.sourceEventTimestamp < rhs.sourceEventTimestamp
                }
                return leftTimeline.startTime < rightTimeline.startTime
            }
        let activeMarkerID = markers.last { marker in
            let timeline = SharedMotionEngine.zoomTimeline(for: marker)
            return currentTime >= timeline.startTime && currentTime <= timeline.endTime
        }?.id
        let markerID = activeMarkerID ?? markers.last(where: { $0.sourceEventTimestamp <= currentTime })?.id

        if selectedZoomMarkerID != markerID {
            selectedZoomMarkerID = markerID
        }
    }

    private func updateSelectedEffectMarkerForTime(_ currentTime: Double) {
        guard let summary = recordingSummary, !summary.effectMarkers.isEmpty else {
            selectedEffectMarkerID = nil
            return
        }

        if let manualSelectionSuppressionUntil, Date() < manualSelectionSuppressionUntil {
            return
        }

        let eligibleMarkers = summary.effectMarkers.filter { $0.enabled }
        let markers = (eligibleMarkers.isEmpty ? summary.effectMarkers : eligibleMarkers)
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    if lhs.sourceEventTimestamp == rhs.sourceEventTimestamp {
                        return lhs.id < rhs.id
                    }
                    return lhs.sourceEventTimestamp < rhs.sourceEventTimestamp
                }
                return lhs.startTime < rhs.startTime
            }

        guard let markerID = markers.last(where: { currentTime >= $0.startTime && currentTime <= $0.endTime })?.id else {
            selectedEffectMarkerID = nil
            return
        }

        if selectedEffectMarkerID != markerID {
            selectedEffectMarkerID = markerID
        }
    }
}
