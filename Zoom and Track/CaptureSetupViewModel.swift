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
    private var targetRefreshTask: Task<Void, Never>?
    private var metadataSaveTask: Task<Void, Never>?
    private var wasPlayingBeforeMarkerTimelineMove = false
    private var activeExportOperationID = UUID()
    private let timelineMarkerNudgeInterval = 0.1

    private let permissionsService = PermissionsService()
    private let screenCaptureService = ScreenCaptureService()
    private let mediaWriterService = MediaWriterService()
    private let projectBundleService = ProjectBundleService()
    private let inputEventCaptureService = InputEventCaptureService()
    private let markerPreviewRenderService = MarkerPreviewRenderService()
    private let markerPreviewCacheService = MarkerPreviewCacheService()
    private let exportRenderService = ExportRenderService()
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
        metadataSaveTask?.cancel()
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
        hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
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
        _ = permissionsService.requestScreenRecordingPermission()
        hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
        statusMessage = hasScreenRecordingPermission
            ? "Permission granted. Reload targets if needed."
            : "Grant Screen Recording permission in System Settings, then relaunch the app if capture still fails."
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
        guard canExportRecording, exportTask == nil else {
            NSLog("FlowTrack Capture ignored duplicate export request.")
            return
        }
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
        let exportOperationID = UUID()
        activeExportOperationID = exportOperationID

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await exportRenderService.exportRecording(
                    recordingURL: summary.recordingURL,
                    summary: summary,
                    outputURL: outputURL
                ) { [weak self] phase, progress in
                    guard let self else { return }
                    guard self.activeExportOperationID == exportOperationID else { return }
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
                guard activeExportOperationID == exportOperationID else { return }
                exportedRecordingURL = result.outputURL
                exportProgress = 1
                exportState = .completed
                exportStatusMessage = "Export complete."
                NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
            } catch is CancellationError {
                guard activeExportOperationID == exportOperationID else { return }
                exportState = .cancelled
                exportStatusMessage = "Export cancelled."
            } catch {
                guard activeExportOperationID == exportOperationID else { return }
                exportState = .failed(error.localizedDescription)
                exportStatusMessage = "Export failed."
            }
            if activeExportOperationID == exportOperationID {
                exportTask = nil
            }
        }
    }

    func cancelExport() {
        guard exportTask != nil || exportState.isInProgress else { return }
        exportStatusMessage = "Cancelling export…"
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

    private func refreshCaptureTargets(silent: Bool) async throws {
        let targets = try await screenCaptureService.fetchTargets()
        displays = targets.displays
        windows = targets.windows

        if let selectedTargetID, (displays + windows).contains(where: { $0.id == selectedTargetID }) == false {
            self.selectedTargetID = nil
        }

        if !silent {
            statusMessage = hasScreenRecordingPermission
                ? "Choose one display or one window."
                : "Screen Recording permission is required."
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
            let libraryRoot = try projectBundleService.libraryRootURL()
            let bundleURL = libraryRoot.appendingPathComponent(item.bundleRelativePath, isDirectory: true)
            openCapture(at: bundleURL)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func revealLibraryCapture(_ item: CaptureLibraryItem) {
        do {
            let libraryRoot = try projectBundleService.libraryRootURL()
            let bundleURL = libraryRoot.appendingPathComponent(item.bundleRelativePath, isDirectory: true)
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
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return
        }
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
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return
        }
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
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return
        }
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
        guard canUsePlaybackTransport, let player = mainPlayer, !isTimelineScrubbing else { return }
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
        } else {
            selectedZoomMarkerID = nil
        }
        seekPlayback(to: seconds)
    }

    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?) {
        guard isTimelineScrubbing else { return }
        if let snappedMarkerID {
            selectedZoomMarkerID = snappedMarkerID
        } else {
            selectedZoomMarkerID = nil
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
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return
        }
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
        } else {
            selectedZoomMarkerID = nil
        }
        seekPlayback(to: seconds)
    }

    func beginTimelineMarkerMove(_ markerID: String) {
        guard canEditClickFocusMarkers, let player = mainPlayer else { return }
        cancelPendingMarkerPreviewRender()
        if playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview {
            playbackTransitionPlateState = .hidden
            playbackPresentationMode = .normal
        }
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        wasPlayingBeforeMarkerTimelineMove = player.timeControlStatus == .playing
        player.pause()
        isPlaybackActive = false
        selectedZoomMarkerID = markerID
        manualSelectionSuppressionUntil = Date().addingTimeInterval(0.5)
    }

    func previewTimelineMarkerMove(_ markerID: String, to seconds: Double) {
        moveMarker(markerID, to: seconds, persist: false, seekPlaybackHead: false)
    }

    func commitTimelineMarkerMove(_ markerID: String, to seconds: Double) {
        moveMarker(markerID, to: seconds, persist: true, seekPlaybackHead: true)
        manualSelectionSuppressionUntil = Date().addingTimeInterval(0.2)
        if wasPlayingBeforeMarkerTimelineMove {
            mainPlayer?.play()
            isPlaybackActive = true
        }
        wasPlayingBeforeMarkerTimelineMove = false
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
        updateSelectedMarker { marker in
            guard marker.isClickFocus else { return }
            marker.clickPulse = ClickPulseConfiguration(preset: preset)
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
            noZoomFallbackMode: defaultNoZoomFallbackMode
        )
        markers.append(marker)
        selectedZoomMarkerID = marker.id
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
        guard recordingSummary != nil else { return }
        metadataSaveTask?.cancel()
        metadataSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.saveCurrentCaptureMetadata()
        }
    }

    private func saveCurrentCaptureMetadata() async {
        guard let summary = recordingSummary else { return }
        let metadata = currentCaptureMetadata

        do {
            let updatedManifest = try projectBundleService.updateCaptureMetadata(
                in: summary.bundleURL,
                captureMetadata: metadata
            )
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
                zoomMarkers: summary.zoomMarkers
            )
            recordingSummary = updatedSummary
            captureTitle = updatedManifest.captureTitle
            collectionName = updatedManifest.collectionName
            projectName = updatedManifest.projectName
            captureType = updatedManifest.captureType
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
            let snapshot = try await projectBundleService.loadLibrarySnapshot()
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
        metadataSaveTask?.cancel()
        metadataSaveTask = nil
        activeExportOperationID = UUID()
        exportTask?.cancel()
        exportTask = nil
        exportRenderService.cancelExport()
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

    private func updateMarker(withID markerID: String, mutate: (inout ZoomPlanItem) -> Void) {
        guard let summary = recordingSummary,
              let index = summary.zoomMarkers.firstIndex(where: { $0.id == markerID }) else {
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
            let updatedSummary = summaryWithMarkers(markers, basedOn: summary)
            publishOnNextRunLoop { [weak self] in
                self?.recordingSummary = updatedSummary
            }
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
            zoomMarkers: markers
        )
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
    }

    private func cancelPendingMarkerPreviewRender() {
        markerPreviewRenderTask?.cancel()
        markerPreviewRenderTask = nil
        publishOnNextRunLoop { [weak self] in
            self?.isRenderingMarkerPreview = false
            self?.markerPreviewStatusMessage = nil
        }
        renderingPreviewMarkerID = nil
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
            selectedZoomMarkerID = nil
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
