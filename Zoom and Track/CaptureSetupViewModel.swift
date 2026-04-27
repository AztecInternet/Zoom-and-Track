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
    @Published var selectedZoomMarkerID: String?
    @Published var currentPlaybackTime: Double = 0
    @Published var isPlaybackActive = false
    @Published var isRenderingMarkerPreview = false
    @Published var markerPreviewStatusMessage: String?
    
    private var hasRestoredLastRecording = false
    private var activePlaybackScopeURL: URL?
    private var playbackTimeObserver: Any?
    private var manualSelectionSuppressionUntil: Date?
    private var previewMarkerID: String?
    private var previewEndTime: Double?
    private var wasPlayingBeforeTimelineScrub = false
    private var isTimelineScrubbing = false
    private var markerPreviewRenderTask: Task<Void, Never>?
    private var activeRenderedPreviewURL: URL?
    private var renderedPreviewSourceStartTime: Double?
    private var renderingPreviewMarkerID: String?

    private let permissionsService = PermissionsService()
    private let screenCaptureService = ScreenCaptureService()
    private let mediaWriterService = MediaWriterService()
    private let projectBundleService = ProjectBundleService()
    private let inputEventCaptureService = InputEventCaptureService()
    private let markerPreviewRenderService = MarkerPreviewRenderService()
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
        renderedPreviewSourceStartTime != nil
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

    func startMarkerPreview(_ markerID: String) {
        guard let summary = recordingSummary,
              let marker = summary.zoomMarkers.first(where: { $0.id == markerID }),
              player != nil else {
            return
        }

        cancelPendingMarkerPreviewRender()
        selectedZoomMarkerID = markerID
        renderingPreviewMarkerID = markerID
        isRenderingMarkerPreview = true
        markerPreviewStatusMessage = "Rendering preview…"
        manualSelectionSuppressionUntil = Date().addingTimeInterval(2.0)
        restorePrimaryPlaybackIfNeeded(seekTo: currentPlaybackTime, autoPlay: false)

        markerPreviewRenderTask = Task { [weak self] in
            guard let self else { return }

            do {
                let renderedPreview = try await markerPreviewRenderService.renderPreview(
                    recordingURL: summary.recordingURL,
                    summary: summary,
                    selectedMarker: marker
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.renderingPreviewMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = false
                    self.markerPreviewStatusMessage = nil
                    self.playRenderedPreview(renderedPreview, markerID: markerID)
                }
            } catch is CancellationError {
                await MainActor.run {
                    if self.renderingPreviewMarkerID == markerID {
                        self.isRenderingMarkerPreview = false
                        self.markerPreviewStatusMessage = nil
                        self.renderingPreviewMarkerID = nil
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.renderingPreviewMarkerID == markerID else { return }
                    self.isRenderingMarkerPreview = false
                    self.markerPreviewStatusMessage = nil
                    self.statusMessage = "Rendered preview failed. Using live preview."
                    self.startLiveMarkerPreview(markerID)
                }
            }
        }
    }

    func togglePlayback() {
        cancelPendingMarkerPreviewRender()
        cancelPreviewMode()
        guard let player else { return }
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
        restorePrimaryPlaybackIfNeeded(seekTo: currentPlaybackTime, autoPlay: false)
        cancelPreviewMode()
        seekPlayback(to: seconds)
    }

    func jumpPlaybackToStart() {
        cancelPendingMarkerPreviewRender()
        restorePrimaryPlaybackIfNeeded(seekTo: currentPlaybackTime, autoPlay: false)
        cancelPreviewMode()
        seekPlayback(to: 0)
    }

    func cancelPlaybackPreview() {
        cancelPendingMarkerPreviewRender()
        cancelPreviewMode()
    }

    func beginTimelineScrub() {
        guard let player, !isTimelineScrubbing else { return }
        cancelPendingMarkerPreviewRender()
        restorePrimaryPlaybackIfNeeded(seekTo: currentPlaybackTime, autoPlay: false)
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
            player?.play()
            isPlaybackActive = true
        }
    }

    func seekTimelineDirectly(to seconds: Double, snappedMarkerID: String?) {
        cancelPendingMarkerPreviewRender()
        restorePrimaryPlaybackIfNeeded(seekTo: currentPlaybackTime, autoPlay: false)
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
        player = AVPlayer(playerItem: AVPlayerItem(url: summary.recordingURL))
        selectedZoomMarkerID = nil
        currentPlaybackTime = 0
        isPlaybackActive = false
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        previewMarkerID = nil
        previewEndTime = nil
        installPlaybackObserver()
        updateSelectedMarkerForCurrentPlaybackTime()
    }

    private func releasePlaybackState() {
        cancelPendingMarkerPreviewRender()
        removePlaybackObserver()
        player?.pause()
        player = nil
        recordingSummary = nil
        selectedZoomMarkerID = nil
        currentPlaybackTime = 0
        isPlaybackActive = false
        isRenderingMarkerPreview = false
        markerPreviewStatusMessage = nil
        previewMarkerID = nil
        previewEndTime = nil
        cleanupRenderedPreviewFile()
        projectBundleService.endPlaybackAccess(activePlaybackScopeURL)
        activePlaybackScopeURL = nil
    }

    private func seekPlayback(to seconds: Double) {
        guard let player else { return }
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
        guard let player else { return }
        let previewBounds = previewBounds(for: marker)
        cancelPreviewMode()
        restorePrimaryPlaybackIfNeeded(seekTo: currentPlaybackTime, autoPlay: false)
        selectedZoomMarkerID = markerID
        previewMarkerID = markerID
        previewEndTime = previewBounds.endTime
        manualSelectionSuppressionUntil = Date().addingTimeInterval(max(previewBounds.endTime - previewBounds.startTime, 0.35) + 0.15)
        seekPlayback(to: previewBounds.startTime)
        player.play()
        isPlaybackActive = true
    }

    private func playRenderedPreview(_ renderedPreview: RenderedMarkerPreview, markerID: String) {
        guard let player else { return }
        cleanupRenderedPreviewFile()
        activeRenderedPreviewURL = renderedPreview.outputURL
        renderedPreviewSourceStartTime = renderedPreview.sourceStartTime
        selectedZoomMarkerID = markerID
        previewMarkerID = markerID
        previewEndTime = renderedPreview.sourceEndTime
        renderingPreviewMarkerID = nil
        manualSelectionSuppressionUntil = Date().addingTimeInterval(
            max(renderedPreview.sourceEndTime - renderedPreview.sourceStartTime, 0.35) + 0.15
        )
        player.replaceCurrentItem(with: AVPlayerItem(url: renderedPreview.outputURL))
        currentPlaybackTime = renderedPreview.sourceStartTime
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isPlaybackActive = true
    }

    private func restorePrimaryPlaybackIfNeeded(seekTo sourceTime: Double?, autoPlay: Bool) {
        guard renderedPreviewSourceStartTime != nil,
              let summary = recordingSummary,
              let player else {
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: summary.recordingURL))
        renderedPreviewSourceStartTime = nil
        cleanupRenderedPreviewFile()
        if let sourceTime {
            let time = CMTime(seconds: max(sourceTime, 0), preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            currentPlaybackTime = max(sourceTime, 0)
        }
        if autoPlay {
            player.play()
            isPlaybackActive = true
        } else {
            player.pause()
            isPlaybackActive = false
        }
    }

    private func cleanupRenderedPreviewFile() {
        if let activeRenderedPreviewURL {
            try? FileManager.default.removeItem(at: activeRenderedPreviewURL)
        }
        activeRenderedPreviewURL = nil
    }

    private func installPlaybackObserver() {
        removePlaybackObserver()
        guard let player else { return }

        playbackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSelectedMarkerForCurrentPlaybackTime()
            }
        }
    }

    private func removePlaybackObserver() {
        guard let player, let playbackTimeObserver else { return }
        player.removeTimeObserver(playbackTimeObserver)
        self.playbackTimeObserver = nil
    }

    private func updateSelectedMarkerForCurrentPlaybackTime() {
        guard let player else {
            return
        }

        let playerTime = player.currentTime().seconds
        guard playerTime.isFinite else { return }
        let currentTime = (renderedPreviewSourceStartTime ?? 0) + playerTime
        currentPlaybackTime = currentTime
        isPlaybackActive = player.timeControlStatus == .playing

        if isTimelineScrubbing {
            return
        }

        if isRenderingMarkerPreview, let renderingPreviewMarkerID {
            selectedZoomMarkerID = renderingPreviewMarkerID
            return
        }

        if let previewEndTime, let previewMarkerID {
            selectedZoomMarkerID = previewMarkerID
            if currentTime >= previewEndTime - 0.02 {
                player.pause()
                isPlaybackActive = false
                restorePrimaryPlaybackIfNeeded(seekTo: previewEndTime, autoPlay: false)
                cancelPreviewMode()
            }
            return
        }

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
