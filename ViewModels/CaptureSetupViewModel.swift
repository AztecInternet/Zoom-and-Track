//
//  CaptureSetupViewModel.swift
//  Zoom and Track
//

import Combine
import AppKit
import AVKit
import Foundation

private struct SmartSetupAnalysisResult {
    let heuristicSuggestions: [SmartSetupSuggestion]
    let suggestions: [SmartSetupSuggestion]
    let frameDiagnostics: ActivityRegionFrameSamplingDiagnostics
    let ocrDiagnostics: SmartSuggestionOCRDiagnostics
    let visualChangeDiagnostics: SmartSuggestionVisualChangeDiagnostics
    let coreMLDiagnostics: SmartSuggestionCoreMLDiagnostics
    let regionMetadata: [String: SmartSuggestionOCRRegionMetadata]
}

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

    private struct SmartSuggestionContextDebugItem {
        let suggestionID: String
        let title: String
        let timeRange: String
        let uiContext: SmartSuggestionUIContext
        let uiContextConfidence: Double
        let supportingText: String?
        let supportingTextRole: SmartSuggestionOCRTextRole
        let supportingTextRoleReason: String?
        let contextSpecificWordingEligible: Bool
        let contextSpecificWordingApplied: Bool
        let fallbackReason: String?
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
    @Published var compositionLayout: CompositionLayout = .default
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
    @Published var selectedEffectMarkerID: String? {
        didSet {
            if selectedEffectMarkerID != oldValue {
                isShowingDistortionMapOverlay = false
            }
        }
    }
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
    @Published private(set) var distortionPresetLibrary: DistortionPresetLibrary = .empty
    @Published var selectedDistortionPresetLibraryID: String?
    @Published var distortionLoupeNormalizedPoint: CGPoint?
    @Published var distortionLoupeImage: NSImage?
    @Published var isRenderingDistortionLoupe = false
    @Published var isShowingDistortionMapOverlay = false
    @Published private(set) var pendingSmartSetupSuggestions: [SmartSetupSuggestion] = []
    @Published private(set) var selectedSmartSetupSuggestionID: String?
    @Published private(set) var smartSetupSelectionPulseToken = 0
    @Published private(set) var activeSmartSuggestionPreviewEndTime: Double?
    @Published private(set) var smartSetupStatusMessage: String?
    @Published private(set) var isRunningSmartSetup = false
    
    private var latestSmartSuggestionContextDebug: [SmartSuggestionContextDebugItem] = []
    private var smartSetupRunTask: Task<Void, Never>?
    private var smartSetupRunRevision = 0
    private var hasRestoredLastRecording = false
    private var activePlaybackScopeURL: URL?
    private var mainPlaybackTimeObserver: Any?
    private var previewPlaybackTimeObserver: Any?
    private var manualSelectionSuppressionUntil: Date?
    private var isEffectMarkerSelectionPinned = false
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
    private var distortionLoupeRenderTask: Task<Void, Never>?
    private var distortionLoupeRevision = 0
    private var distortionOverlayImageCache: [String: NSImage] = [:]
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
    private let captureMetadataManager: CaptureMetadataManager
    private let playbackTransportManager = PlaybackTransportManager()
    private let timelineScrubManager = TimelineScrubManager()
    private let inputEventCaptureService = InputEventCaptureService()
    private let markerPreviewRenderService = MarkerPreviewRenderService()
    private let markerPreviewCacheService = MarkerPreviewCacheService()
    private let creatorEffectDefaultsService = CreatorEffectDefaultsService()
    private let smartSuggestionAggregator = SmartSuggestionAggregator.defaultAggregator()
    private let smartSuggestionFrameSampler = SmartSuggestionFrameSamplerService()
    private let smartSuggestionVisionAnalysisService = SmartSuggestionVisionAnalysisService()
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
        loadDistortionPresetLibrary()
        startAutomaticTargetRefresh()
    }

    deinit {
        targetRefreshTask?.cancel()
        Task { @MainActor [captureMetadataManager] in
            captureMetadataManager.cancelPendingSave()
        }
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

    var isSelectedEffectDistortion: Bool {
        guard let selectedEffectMarker else { return false }
        return selectedEffectMarker.style == .distortion || selectedEffectMarker.style == .heatHazeEdge
    }

    var canShowSelectedDistortionMapOverlay: Bool {
        guard let selectedEffectMarker,
              selectedEffectMarker.style == .distortion,
              case .importedMap(let mapID) = selectedEffectMarker.distortion?.mapSource,
              !mapID.isEmpty else {
            return false
        }
        return (try? projectBundleService.distortionImportedMapURL(for: mapID, in: distortionPresetLibrary)) != nil
    }

    var selectedEffectDistortionOverlayImage: NSImage? {
        guard let selectedEffectMarker,
              selectedEffectMarker.style == .distortion,
              case .importedMap(let mapID) = selectedEffectMarker.distortion?.mapSource else {
            return nil
        }
        return distortionOverlayImage(forMapID: mapID)
    }

    var availableDistortionPresetDescriptors: [DistortionPresetDescriptor] {
        DistortionPresetDescriptor.builtInDescriptors + distortionPresetLibrary.presets.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var selectedDistortionPresetDescriptor: DistortionPresetDescriptor? {
        let preferredID = selectedDistortionPresetLibraryID
        if let preferredID,
           let descriptor = availableDistortionPresetDescriptors.first(where: { $0.id == preferredID }) {
            return descriptor
        }
        return availableDistortionPresetDescriptors.first
    }

    var distortionImportedMapAssets: [DistortionImportedMapAsset] {
        distortionPresetLibrary.importedMaps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var selectedCustomDistortionPresetDescriptor: DistortionPresetDescriptor? {
        guard let selectedDistortionPresetLibraryID else { return nil }
        return distortionPresetLibrary.presets.first(where: { $0.id == selectedDistortionPresetLibraryID })
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
            captureMetadata: currentCaptureMetadata,
            compositionLayout: compositionLayout
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

    func selectDistortionPresetLibraryPreset(_ presetID: String) {
        selectedDistortionPresetLibraryID = presetID
    }

    func createDistortionPresetFromImportedMap() {
        guard let sourceURL = projectBundleService.chooseDistortionMapImage() else { return }

        do {
            let asset = try projectBundleService.importDistortionMap(
                from: sourceURL,
                suggestedName: sourceURL.deletingPathExtension().lastPathComponent
            )
            distortionPresetLibrary.importedMaps.removeAll { $0.id == asset.id }
            distortionPresetLibrary.importedMaps.append(asset)

            let template = DistortionPresetDescriptor.builtInDescriptors[0]
            let baseName = asset.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Custom Distortion"
                : asset.displayName
            let newPreset = DistortionPresetDescriptor(
                id: UUID().uuidString.lowercased(),
                displayName: uniqueDistortionPresetName(basedOn: baseName),
                kind: .user,
                preset: template.preset,
                mapSource: .importedMap(id: asset.id),
                defaultAmount: template.defaultAmount,
                defaultScale: template.defaultScale,
                defaultBackgroundBlend: template.defaultBackgroundBlend,
                defaultBackgroundBlur: template.defaultBackgroundBlur,
                previewVersion: template.previewVersion
            )
            distortionPresetLibrary.presets.append(newPreset)
            persistDistortionPresetLibrary(statusMessage: "Custom Distortion preset added.")
            selectedDistortionPresetLibraryID = newPreset.id
        } catch {
            statusMessage = "Could not import distortion map: \(error.localizedDescription)"
        }
    }

    func duplicateSelectedDistortionPreset() {
        guard let descriptor = selectedDistortionPresetDescriptor else { return }
        let duplicate = DistortionPresetDescriptor(
            id: UUID().uuidString.lowercased(),
            displayName: uniqueDistortionPresetName(basedOn: "\(descriptor.displayName) Copy"),
            kind: .user,
            preset: descriptor.preset,
            mapSource: descriptor.mapSource,
            defaultAmount: descriptor.defaultAmount,
            defaultScale: descriptor.defaultScale,
            defaultBackgroundBlend: descriptor.defaultBackgroundBlend,
            defaultBackgroundBlur: descriptor.defaultBackgroundBlur,
            previewVersion: descriptor.previewVersion
        )
        distortionPresetLibrary.presets.append(duplicate)
        persistDistortionPresetLibrary(statusMessage: "Distortion preset duplicated.")
        selectedDistortionPresetLibraryID = duplicate.id
    }

    func deleteSelectedDistortionPreset() {
        guard let selectedDistortionPresetLibraryID,
              let index = distortionPresetLibrary.presets.firstIndex(where: { $0.id == selectedDistortionPresetLibraryID }) else {
            return
        }
        distortionPresetLibrary.presets.remove(at: index)
        persistDistortionPresetLibrary(statusMessage: "Distortion preset deleted.")
        self.selectedDistortionPresetLibraryID = distortionPresetLibrary.presets.first?.id
    }

    func renameSelectedDistortionPreset(_ name: String) {
        guard let selectedDistortionPresetLibraryID,
              let index = distortionPresetLibrary.presets.firstIndex(where: { $0.id == selectedDistortionPresetLibraryID }) else {
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        distortionPresetLibrary.presets[index].displayName = trimmed
        persistDistortionPresetLibrary()
    }

    func setSelectedDistortionLibraryPresetEnginePreset(_ preset: DistortionPreset) {
        updateSelectedDistortionPresetLibraryDescriptor { descriptor in
            descriptor.preset = preset
            if case .preset = descriptor.mapSource {
                descriptor.mapSource = .preset(preset)
            }
        }
    }

    func setSelectedDistortionLibraryPresetMapSource(_ mapSource: DistortionMapSource) {
        updateSelectedDistortionPresetLibraryDescriptor { descriptor in
            descriptor.mapSource = mapSource
        }
    }

    func setSelectedDistortionLibraryPresetDefaultAmount(_ amount: Double) {
        updateSelectedDistortionPresetLibraryDescriptor { descriptor in
            descriptor.defaultAmount = min(max(amount, 0), 1)
        }
    }

    func setSelectedDistortionLibraryPresetDefaultScale(_ scale: Double) {
        updateSelectedDistortionPresetLibraryDescriptor { descriptor in
            descriptor.defaultScale = min(max(scale, 0), 1)
        }
    }

    func setSelectedDistortionLibraryPresetDefaultBackgroundBlend(_ blend: Double) {
        updateSelectedDistortionPresetLibraryDescriptor { descriptor in
            descriptor.defaultBackgroundBlend = min(max(blend, 0), 1)
        }
    }

    func setSelectedDistortionLibraryPresetDefaultBackgroundBlur(_ blur: Double) {
        updateSelectedDistortionPresetLibraryDescriptor { descriptor in
            descriptor.defaultBackgroundBlur = min(max(blur, 0), 1)
        }
    }

    func openRecording() {
        guard let bundleURL = projectBundleService.openRecordingBundle() else { return }
        openCapture(at: bundleURL)
    }

    func runSmartSetup() {
        guard let summary = recordingSummary else {
            smartSetupStatusMessage = "Load a capture before running Smart Suggestions."
            return
        }

        smartSetupRunTask?.cancel()
        smartSetupRunRevision &+= 1
        let runRevision = smartSetupRunRevision
        let bundleURL = summary.bundleURL
        let recordingURL = summary.recordingURL
        let duration = summary.duration ?? summary.lastEventTimestamp ?? 0
        let contentCoordinateSize = summary.contentCoordinateSize
        let existingZoomMarkers = summary.zoomMarkers
        let existingEffectMarkers = summary.effectMarkers

        isRunningSmartSetup = true
        smartSetupStatusMessage = "Checking screen activity..."

        smartSetupRunTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .utility) {
                    try await makeSmartSetupAnalysis(
                        bundleURL: bundleURL,
                        recordingURL: recordingURL,
                        duration: duration,
                        contentCoordinateSize: contentCoordinateSize,
                        existingZoomMarkers: existingZoomMarkers,
                        existingEffectMarkers: existingEffectMarkers
                    )
                }.value

                guard !Task.isCancelled else { return }
                self?.finishSmartSetupRun(result, revision: runRevision)
            } catch is CancellationError {
                self?.finishCancelledSmartSetupRun(revision: runRevision)
            } catch {
                self?.finishFailedSmartSetupRun(error, revision: runRevision)
            }
        }
    }

    private func finishSmartSetupRun(_ result: SmartSetupAnalysisResult, revision: Int) {
        guard revision == smartSetupRunRevision else { return }

        let contextDebugItems = smartSuggestionContextDebugItems(
            visibleSuggestions: result.suggestions,
            originalSuggestions: result.heuristicSuggestions,
            regionMetadata: result.regionMetadata
        )
        latestSmartSuggestionContextDebug = contextDebugItems
        printSmartSuggestionContextDebug(contextDebugItems)
        printSmartSuggestionOCRDebug(result.ocrDiagnostics)
        printSmartSuggestionVisualChangeDebug(result.visualChangeDiagnostics)
        printSmartSuggestionCoreMLDebug(result.coreMLDiagnostics)
        pendingSmartSetupSuggestions = result.suggestions
        selectedSmartSetupSuggestionID = result.suggestions.first?.suggestionID
        activeSmartSuggestionPreviewEndTime = nil
        isRunningSmartSetup = false
            let visionSummary = smartSuggestionVisionSummary(
                suggestionCount: result.suggestions.count,
                originalSuggestionCount: result.heuristicSuggestions.count,
                frameDiagnostics: result.frameDiagnostics,
                ocrDiagnostics: result.ocrDiagnostics
            )
        smartSetupStatusMessage = result.suggestions.isEmpty
            ? "Smart Suggestions did not find any useful suggestions. \(visionSummary)"
            : "\(result.suggestions.count) suggestion\(result.suggestions.count == 1 ? "" : "s") found. \(visionSummary) • Codex Test"
    }

    private func finishCancelledSmartSetupRun(revision: Int) {
        guard revision == smartSetupRunRevision else { return }
        isRunningSmartSetup = false
    }

    private func finishFailedSmartSetupRun(_ error: Error, revision: Int) {
        guard revision == smartSetupRunRevision else { return }
        pendingSmartSetupSuggestions = []
        selectedSmartSetupSuggestionID = nil
        activeSmartSuggestionPreviewEndTime = nil
        latestSmartSuggestionContextDebug = []
        isRunningSmartSetup = false
        smartSetupStatusMessage = "Smart Suggestions could not load recorded events: \(error.localizedDescription)"
    }

    private func smartSuggestionProviderSummary(for suggestions: [SmartSetupSuggestion]) -> String {
        let counts = Dictionary(grouping: suggestions, by: \.providerID)
            .mapValues(\.count)
        let rulesCount = counts["rules"] ?? 0
        let clickClustersCount = counts["click-clusters"] ?? 0
        let clicksCount = counts["clicks"] ?? 0
        let templateCount = counts["templates"] ?? 0
        return "Smart Suggestions: \(rulesCount) rules, \(clickClustersCount) click-cluster\(clickClustersCount == 1 ? "" : "s"), \(clicksCount) clicks, \(templateCount) template\(templateCount == 1 ? "" : "s")."
    }

    private func smartSuggestionFrameSamplingSummary(_ diagnostics: ActivityRegionFrameSamplingDiagnostics) -> String {
        let elapsedMilliseconds = Int((diagnostics.elapsedSeconds * 1_000).rounded())
        return "Activity Regions: \(diagnostics.regionCount), sampled frames: \(diagnostics.sampledFrameCount), failed: \(diagnostics.failedSampleCount), time: \(elapsedMilliseconds)ms."
    }

    private func smartSuggestionVisionSummary(
        suggestionCount: Int,
        originalSuggestionCount: Int,
        frameDiagnostics: ActivityRegionFrameSamplingDiagnostics,
        ocrDiagnostics: SmartSuggestionOCRDiagnostics
    ) -> String {
        var summary = ocrDiagnostics.analyzedFrameCount > 0
            ? "Screen content checked."
            : "Screen content check skipped."
        let reducedSuggestionCount = max(originalSuggestionCount - suggestionCount, 0)
        if reducedSuggestionCount > 0 {
            summary += " \(reducedSuggestionCount) weak suggestion\(reducedSuggestionCount == 1 ? "" : "s") reduced."
        }
        if frameDiagnostics.failedSampleCount > 0 || ocrDiagnostics.failedOCRCount > 0 {
            summary += " \(frameDiagnostics.failedSampleCount + ocrDiagnostics.failedOCRCount) screen check\(frameDiagnostics.failedSampleCount + ocrDiagnostics.failedOCRCount == 1 ? "" : "s") could not complete."
        }
        return summary
    }

    private func smartSuggestionUIContextSummary(
        _ contextDebugItems: [SmartSuggestionContextDebugItem]
    ) -> String {
        guard !contextDebugItems.isEmpty else { return "" }

        let counts = Dictionary(grouping: contextDebugItems, by: \.uiContext)
            .mapValues(\.count)
        let contextParts = SmartSuggestionUIContext.allCases.compactMap { context -> String? in
            guard let count = counts[context],
                  count > 0 else {
                return nil
            }
            return "\(context.displayName) \(count)"
        }

        guard !contextParts.isEmpty else { return "" }
        return "Context: \(contextParts.joined(separator: ", "))."
    }

    private func smartSuggestionContextDebugItems(
        visibleSuggestions: [SmartSetupSuggestion],
        originalSuggestions: [SmartSetupSuggestion],
        regionMetadata: [String: SmartSuggestionOCRRegionMetadata]
    ) -> [SmartSuggestionContextDebugItem] {
        let originalSuggestionsByID = Dictionary(
            uniqueKeysWithValues: originalSuggestions.map { ($0.suggestionID, $0) }
        )

        return visibleSuggestions.map { suggestion in
            let metadata = regionMetadata["suggestion-\(suggestion.suggestionID)"]
            let originalSuggestion = originalSuggestionsByID[suggestion.suggestionID]
            let eligible = metadata?.hasUsefulUIContext ?? false
            let applied = eligible
                && (
                    suggestion.userTitle != originalSuggestion?.userTitle
                    || suggestion.userReason != originalSuggestion?.userReason
                )

            return SmartSuggestionContextDebugItem(
                suggestionID: suggestion.suggestionID,
                title: suggestion.userTitle ?? smartSuggestionFallbackTitle(for: suggestion),
                timeRange: smartSuggestionDebugTimeRange(for: suggestion),
                uiContext: metadata?.uiContext ?? .unknown,
                uiContextConfidence: metadata?.uiContextConfidence ?? 0,
                supportingText: metadata?.supportingText,
                supportingTextRole: metadata?.supportingTextRole ?? .fallbackText,
                supportingTextRoleReason: metadata?.supportingTextRoleReason,
                contextSpecificWordingEligible: eligible,
                contextSpecificWordingApplied: applied,
                fallbackReason: smartSuggestionContextFallbackReason(
                    metadata: metadata,
                    eligible: eligible,
                    applied: applied
                )
            )
        }
    }

    private func smartSuggestionContextFallbackReason(
        metadata: SmartSuggestionOCRRegionMetadata?,
        eligible: Bool,
        applied: Bool
    ) -> String? {
        guard let metadata else { return "no OCR metadata for visible suggestion" }
        guard eligible else {
            if metadata.uiContext == .unknown {
                return "unknown context"
            }
            return "below threshold"
        }
        guard applied else { return "context matched existing wording" }
        return nil
    }

    private func printSmartSuggestionContextDebug(_ items: [SmartSuggestionContextDebugItem]) {
        guard !items.isEmpty else {
            print("[SmartSuggestionContext] no visible suggestions")
            return
        }

        print("[SmartSuggestionContext] \(smartSuggestionUIContextSummary(items))")
        for item in items {
            let confidence = String(format: "%.2f", item.uiContextConfidence)
            let supportingText = item.supportingText ?? "none"
            let roleReason = item.supportingTextRoleReason.map { " | \($0)" } ?? ""
            let wording = item.contextSpecificWordingApplied
                ? "applied"
                : "fallback: \(item.fallbackReason ?? "not applied")"
            print("[SmartSuggestionContext] \(item.timeRange) | \(item.title) | \(item.uiContext.rawValue) | \(confidence) | supporting: \(supportingText) | labelRole: \(item.supportingTextRole.debugLabel)\(roleReason) | eligible: \(item.contextSpecificWordingEligible) | \(wording)")
        }
    }

    private func printSmartSuggestionOCRDebug(_ diagnostics: SmartSuggestionOCRDiagnostics) {
        let previewText = diagnostics.previewStrings.isEmpty
            ? "none"
            : diagnostics.previewStrings.joined(separator: " | ")
        print("[SmartSuggestionOCR] frames: \(diagnostics.analyzedFrameCount), crop observations: \(diagnostics.cropTextObservationCount), full-frame fallback observations: \(diagnostics.fullFrameFallbackTextObservationCount), failed: \(diagnostics.failedOCRCount), preview: \(previewText)")
    }

    private func printSmartSuggestionVisualChangeDebug(_ diagnostics: SmartSuggestionVisualChangeDiagnostics) {
        print("[SmartSuggestionVisualChange] regions: \(diagnostics.analyzedRegionCount), frame pairs: \(diagnostics.comparedFramePairCount), visible changes: \(diagnostics.visibleChangeRegionCount), large transitions: \(diagnostics.largeTransitionRegionCount)")
        guard !diagnostics.previewLines.isEmpty else {
            print("[SmartSuggestionVisualChange] no region diagnostics")
            return
        }

        for line in diagnostics.previewLines {
            print("[SmartSuggestionVisualChange] \(line)")
        }
    }

    private func printSmartSuggestionCoreMLDebug(_ diagnostics: SmartSuggestionCoreMLDiagnostics) {
        let modelName = diagnostics.modelName ?? "none"
        if diagnostics.isAvailable {
            print("[SmartSuggestionCoreML] available=true model=\(modelName) observations=\(diagnostics.observationCount) regions=\(diagnostics.analyzedRegionCount) frames=\(diagnostics.analyzedFrameCount)")
        } else {
            print("[SmartSuggestionCoreML] available=false model=none regions=\(diagnostics.analyzedRegionCount) frames=\(diagnostics.analyzedFrameCount)")
        }
    }

    private func smartSuggestionDebugTimeRange(for suggestion: SmartSetupSuggestion) -> String {
        if let sourceTimeRange = suggestion.sourceTimeRange {
            return "\(smartSuggestionDebugTimeString(sourceTimeRange.startTime))–\(smartSuggestionDebugTimeString(sourceTimeRange.endTime))"
        }

        if let sourceEventTimestamp = suggestion.sourceEvents.first?.timestamp {
            return smartSuggestionDebugTimeString(sourceEventTimestamp)
        }

        return smartSuggestionDebugTimeString(smartSuggestionProposalTime(for: suggestion))
    }

    private func smartSuggestionDebugTimeString(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let wholeSeconds = Int(clampedSeconds)
        let tenths = Int((clampedSeconds - Double(wholeSeconds)) * 10.0)
        let minutes = wholeSeconds / 60
        let secondsRemainder = wholeSeconds % 60
        return String(format: "%02d:%02d.%d", minutes, secondsRemainder, tenths)
    }

    private func smartSuggestionProposalTime(for suggestion: SmartSetupSuggestion) -> Double {
        switch suggestion.proposal {
        case .zoom(let proposal):
            return proposal.sourceEventTimestamp
        case .zoomAdjustment(let proposal):
            return proposal.startTime
        case .effect(let proposal):
            return proposal.sourceEventTimestamp
        case .regionTighten(let proposal):
            return proposal.sourceTime
        }
    }

    private func smartSuggestionFallbackTitle(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return "Keep this interaction in focus"
        case .zoom:
            return "Guide attention to this moment"
        case .effect:
            return "Consider a subtle focus effect"
        case .regionTighten:
            return "Review this focus area"
        }
    }

    func acceptSmartSetupSuggestion(_ suggestionID: String) {
        guard recordingSummary != nil,
              let suggestion = pendingSmartSetupSuggestions.first(where: { $0.suggestionID == suggestionID }) else {
            return
        }

        switch suggestion.proposal {
        case .zoom, .zoomAdjustment:
            smartSetupStatusMessage = "Zoom suggestions are review-only until Smart Adjust can apply changes to existing markers."
        case .effect:
            smartSetupStatusMessage = "Effect suggestions are review-only for now. Check them before adding effects manually."
        case .regionTighten:
            smartSetupStatusMessage = "Region suggestions are review-only until Visual Assist is added."
        }
    }

    func selectSmartSetupSuggestion(_ suggestionID: String, previewRange: Bool = true) {
        guard let suggestion = pendingSmartSetupSuggestions.first(where: { $0.suggestionID == suggestionID }) else { return }
        selectedSmartSetupSuggestionID = suggestionID
        smartSetupSelectionPulseToken &+= 1
        if previewRange {
            previewSmartSetupSuggestion(suggestion)
        }
    }

    func clearSelectedSmartSetupSuggestion() {
        selectedSmartSetupSuggestionID = nil
        cancelSmartSuggestionPreview()
    }

    func dismissSmartSetupSuggestion(_ suggestionID: String) {
        pendingSmartSetupSuggestions.removeAll { $0.suggestionID == suggestionID }
        if selectedSmartSetupSuggestionID == suggestionID {
            selectedSmartSetupSuggestionID = nil
            cancelSmartSuggestionPreview()
        }
        if pendingSmartSetupSuggestions.isEmpty {
            smartSetupStatusMessage = "All Smart Suggestions dismissed."
        }
    }

    func clearSmartSetupSuggestions() {
        pendingSmartSetupSuggestions = []
        selectedSmartSetupSuggestionID = nil
        cancelSmartSuggestionPreview()
        smartSetupStatusMessage = nil
    }

    private func previewSmartSetupSuggestion(_ suggestion: SmartSetupSuggestion) {
        guard let player = mainPlayer else { return }
        let range = smartSetupPreviewRange(for: suggestion)
        guard range.endTime > range.startTime else { return }

        cancelPendingMarkerPreviewRender()
        stopPreviewPlayback(seekMainTo: currentPlaybackTime, retainSlate: false)
        cancelPreviewMode()
        playbackTransitionPlateState = .hidden
        playbackPresentationMode = .normal
        activeSmartSuggestionPreviewEndTime = range.endTime
        manualSelectionSuppressionUntil = Date().addingTimeInterval(max(range.endTime - range.startTime, 0.35) + 0.15)
        seekPlayback(to: range.startTime)
        player.play()
        isPlaybackActive = true
    }

    private func cancelSmartSuggestionPreview() {
        if activeSmartSuggestionPreviewEndTime != nil {
            mainPlayer?.pause()
            isPlaybackActive = false
        }
        activeSmartSuggestionPreviewEndTime = nil
    }

    private func smartSetupPreviewRange(for suggestion: SmartSetupSuggestion) -> (startTime: Double, endTime: Double) {
        let duration = max(recordingSummary?.duration ?? recordingSummary?.lastEventTimestamp ?? 0, 0)
        let range = suggestion.reviewPlaybackRange(recordingDuration: duration)
        return (range.startTime, range.endTime)
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
        isEffectMarkerSelectionPinned = snappedEffectMarkerID != nil && plan.selectedEffectMarkerID != nil
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
        isEffectMarkerSelectionPinned = snappedEffectMarkerID != nil && plan.selectedEffectMarkerID != nil
        seekPlayback(to: plan.targetTime)
        isTimelineScrubbing = plan.isTimelineScrubbing
        manualSelectionSuppressionUntil = Date().addingTimeInterval(plan.suppressionInterval)
        if plan.shouldResumePlayback {
            mainPlayer?.play()
            isPlaybackActive = true
        }
    }

    func seekTimelineDirectly(
        to seconds: Double,
        snappedMarkerID: String?,
        snappedEffectMarkerID: String? = nil,
        suppressAutoSelectionWhenUnsnapped: Bool = false
    ) {
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
        isEffectMarkerSelectionPinned = snappedEffectMarkerID != nil && plan.selectedEffectMarkerID != nil
        if let suppressionInterval = plan.suppressionInterval {
            manualSelectionSuppressionUntil = Date().addingTimeInterval(suppressionInterval)
        } else if suppressAutoSelectionWhenUnsnapped,
                  snappedMarkerID == nil,
                  snappedEffectMarkerID == nil {
            manualSelectionSuppressionUntil = Date().addingTimeInterval(0.35)
        }
        seekPlayback(to: plan.targetTime)
    }

    func nudgeSelectedTimelineMarker(by delta: Double, stepDuration: Double? = nil) {
        guard canEditClickFocusMarkers, let markerID = selectedZoomMarkerID else { return }
        let nudgeInterval = stepDuration ?? timelineMarkerNudgeInterval
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
            to: selectedMarkerTimestamp(for: markerID) + (delta * nudgeInterval),
            persist: true,
            seekPlaybackHead: true
        )
    }

    func updateSelectedTimelineMarkerDrag(to seconds: Double) {
        guard canEditClickFocusMarkers, let markerID = selectedZoomMarkerID else { return }
        moveMarker(markerID, to: seconds, persist: false, seekPlaybackHead: false)
    }

    func commitSelectedTimelineMarkerDrag(to seconds: Double) {
        guard canEditClickFocusMarkers, let markerID = selectedZoomMarkerID else { return }
        moveMarker(markerID, to: seconds, persist: true, seekPlaybackHead: true)
    }

    func nudgeSelectedEffectTimelineMarker(by delta: Double, stepDuration: Double? = nil) {
        guard let summary = recordingSummary,
              let markerID = selectedEffectMarkerID,
              let index = summary.effectMarkers.firstIndex(where: { $0.id == markerID }) else { return }
        let nudgeInterval = stepDuration ?? timelineMarkerNudgeInterval

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
            max(currentMarker.sourceEventTimestamp + (delta * nudgeInterval), 0),
            maxDuration
        )

        var effectMarkers = summary.effectMarkers
        effectMarkers[index].sourceEventTimestamp = targetTimestamp
        effectMarkers[index].startTime = max(0, targetTimestamp + timelineOffsetToStart)
        effectMarkers[index].endTime = max(effectMarkers[index].startTime + 0.05, min(maxDuration, targetTimestamp + timelineOffsetToEnd))
        effectMarkers[index].refreshAutomaticMarkerName()

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
            if trimmed.isEmpty || trimmed == marker.automaticMarkerName {
                marker.markerNameSource = .automatic
                marker.refreshAutomaticMarkerName()
            } else {
                marker.markerName = trimmed
                marker.markerNameSource = .manual
            }
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
        isEffectMarkerSelectionPinned = true
        distortionLoupeNormalizedPoint = nil
        syncDistortionMapOverlayVisibility()
        if isPlaybackActive {
            mainPlayer?.pause()
            isPlaybackActive = false
        }
        if seekPlaybackHead {
            seekPlayback(to: marker.snapTime)
        } else {
            currentPlaybackTime = marker.snapTime
        }
        scheduleDistortionLoupeRefresh()
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
        isEffectMarkerSelectionPinned = true
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
            isEffectMarkerSelectionPinned = true
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
        isEffectMarkerSelectionPinned = true
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
            if trimmed.isEmpty || trimmed == marker.automaticMarkerName {
                marker.markerNameSource = .automatic
                marker.refreshAutomaticMarkerName()
            } else {
                marker.markerName = trimmed
                marker.markerNameSource = .manual
            }
        }
    }

    func setSelectedEffectStyle(_ style: EffectStyle) {
        updateSelectedEffectMarker { marker in
            marker.style = style
            if style == .distortion {
                marker.distortion = marker.distortion ?? .defaultConfiguration
            }
        }
        if style == .distortion {
            distortionLoupeNormalizedPoint = nil
            scheduleDistortionLoupeRefresh()
        } else {
            clearDistortionLoupe()
        }
        syncDistortionMapOverlayVisibility()
    }

    func setSelectedEffectAmount(_ amount: Double) {
        updateSelectedEffectMarker { marker in
            marker.amount = min(max(amount, 0), 1)
        }
    }

    func setDistortionLoupePoint(_ point: CGPoint) {
        distortionLoupeNormalizedPoint = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        scheduleDistortionLoupeRefresh()
    }

    func resetDistortionLoupePointToDefault() {
        distortionLoupeNormalizedPoint = nil
        scheduleDistortionLoupeRefresh()
    }

    func setSelectedEffectDistortionPreset(_ preset: DistortionPreset) {
        guard let descriptor = DistortionPresetDescriptor.builtInDescriptors.first(where: { $0.preset == preset }) else {
            return
        }
        applyDistortionPresetDescriptorToSelectedEffect(descriptor)
    }

    func setSelectedEffectDistortionPresetSelectionID(_ presetID: String) {
        guard let descriptor = availableDistortionPresetDescriptors.first(where: { $0.id == presetID }) else {
            return
        }
        applyDistortionPresetDescriptorToSelectedEffect(descriptor)
    }

    func setSelectedEffectDistortionScale(_ scale: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.scale = min(max(scale, 0), 1)
        }
    }

    func setSelectedEffectDistortionBackgroundBlend(_ blend: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.backgroundBlend = min(max(blend, 0), 1)
        }
    }

    func setSelectedEffectDistortionBackgroundBlur(_ blur: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.backgroundBlur = min(max(blur, 0), 1)
        }
    }

    func setSelectedEffectDistortionColorGlowStrength(_ strength: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.colorEffectGlowStrength = min(max(strength, 0), 1)
        }
    }

    func setSelectedEffectDistortionColorGlowRadius(_ radius: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.colorEffectGlowRadius = min(max(radius, 0), 1)
        }
    }

    func setSelectedEffectDistortionColorAnimationIntensity(_ intensity: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.colorEffectAnimationIntensity = min(max(intensity, 0), 1)
        }
    }

    func setSelectedEffectDistortionColorCoreOpacity(_ opacity: Double) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.colorEffectCoreOpacity = min(max(opacity, 0), 1)
        }
    }

    func setSelectedEffectDistortionColorEffectPalette(_ palette: DistortionColorEffectPalette) {
        updateSelectedEffectMarker { marker in
            if marker.distortion == nil {
                marker.distortion = .defaultConfiguration
            }
            marker.distortion?.colorEffectPalette = palette
        }
    }

    func saveSelectedDistortionAsCreatorDefault() {
        saveCurrentEffectStyleAsCreatorDefault()
    }

    func applyCreatorDistortionDefaultsToSelectedEffect() {
        applyCreatorDefaultsToSelectedEffectStyle()
    }

    func saveCurrentEffectStyleAsCreatorDefault() {
        guard let marker = selectedEffectMarker,
              [.blur, .darken, .tint, .distortion].contains(marker.style) else {
            return
        }

        var defaults = creatorEffectDefaultsService.loadCreatorEffectDefaults()
        switch marker.style {
        case .blur:
            defaults.blur = BlurEffectDefault(blurAmount: min(max(marker.blurAmount, 0), 1))
        case .darken:
            defaults.darken = DarkenEffectDefault(darkenAmount: min(max(marker.darkenAmount, 0), 1))
        case .tint:
            defaults.tint = TintEffectDefault(
                tintAmount: min(max(marker.tintAmount, 0), 1),
                tintColor: marker.tintColor
            )
        case .distortion:
            guard let distortion = marker.distortion else { return }
            defaults.distortion = DistortionEffectDefault(
                amount: min(max(marker.amount, 0), 1),
                configuration: distortion
            )
        case .blurDarken, .heatHazeEdge:
            return
        }
        try? creatorEffectDefaultsService.saveCreatorEffectDefaults(defaults)
    }

    func applyCreatorDefaultsToSelectedEffectStyle() {
        let defaults = creatorEffectDefaultsService.loadCreatorEffectDefaults()
        updateSelectedEffectMarker { marker in
            switch marker.style {
            case .blur:
                let blurAmount = min(max(defaults.blur.blurAmount, 0), 1)
                marker.blurAmount = blurAmount
                marker.amount = blurAmount
            case .darken:
                let darkenAmount = min(max(defaults.darken.darkenAmount, 0), 1)
                marker.darkenAmount = darkenAmount
                marker.amount = darkenAmount
            case .tint:
                let tintAmount = min(max(defaults.tint.tintAmount, 0), 1)
                marker.tintAmount = tintAmount
                marker.amount = tintAmount
                marker.tintColor = defaults.tint.tintColor
            case .distortion:
                marker.amount = min(max(defaults.distortion.amount, 0), 1)
                marker.distortion = defaults.distortion.configuration
            case .blurDarken, .heatHazeEdge:
                return
            }
        }
        syncDistortionMapOverlayVisibility()
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
            marker.startTime = marker.holdStartTime - min(max(duration, 0), 3.0)
        }
    }

    func setSelectedEffectFadeOutDuration(_ duration: Double) {
        updateSelectedEffectMarker { marker in
            marker.endTime = marker.holdEndTime + min(max(duration, 0), 3.0)
        }
    }

    func setSelectedEffectHoldStartTime(_ time: Double) {
        let maxDuration = recordingSummary?.duration
        updateSelectedEffectMarker { marker in
            let existingFadeInDuration = marker.fadeInDuration
            let maxHoldStart = min(marker.holdEndTime, maxDuration ?? marker.holdEndTime)
            let clampedHoldStart = min(max(time, existingFadeInDuration), maxHoldStart)
            marker.holdStartTime = clampedHoldStart
            marker.startTime = clampedHoldStart - existingFadeInDuration
        }
    }

    func setSelectedEffectHoldEndTime(_ time: Double) {
        let maxDuration = max(recordingSummary?.duration ?? 0, 0)
        updateSelectedEffectMarker { marker in
            let existingFadeOutDuration = marker.fadeOutDuration
            let maxHoldEnd = max(marker.holdStartTime, maxDuration - existingFadeOutDuration)
            let clampedHoldEnd = min(max(time, marker.holdStartTime), maxHoldEnd)
            marker.holdEndTime = clampedHoldEnd
            marker.endTime = clampedHoldEnd + existingFadeOutDuration
        }
    }

    func setSelectedEffectHoldDuration(_ duration: Double) {
        updateSelectedEffectMarker { marker in
            marker.holdEndTime = marker.holdStartTime + min(max(duration, 0.05), 10.0)
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
        var marker = EffectPlanItem(
            id: nextEffectMarkerID(from: effectMarkers),
            markerName: nil,
            markerNameSource: .automatic,
            sourceEventTimestamp: eventTimestamp,
            startTime: max(0, eventTimestamp - 0.35),
            holdStartTime: max(0, eventTimestamp - 0.35) + 0.18,
            holdEndTime: min(eventTimestamp + 1.0, maxDuration) - 0.24,
            endTime: min(eventTimestamp + 1.0, maxDuration),
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
        syncEffectTiming(&marker, maxDuration: summary.duration)
        effectMarkers.append(marker)
        selectedEffectMarkerID = marker.id
        isEffectMarkerSelectionPinned = true
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    func deleteSelectedEffectMarker() {
        guard let summary = recordingSummary, let selectedEffectMarkerID else { return }
        var effectMarkers = summary.effectMarkers
        effectMarkers.removeAll { $0.id == selectedEffectMarkerID }
        self.selectedEffectMarkerID = nil
        isEffectMarkerSelectionPinned = false
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

    func setCompositionAspectRatio(_ aspectRatio: OutputAspectRatio) {
        compositionLayout = CompositionLayout(
            outputAspectRatio: aspectRatio,
            sourceScale: compositionLayout.sourceScale,
            sourceOffsetX: compositionLayout.sourceOffsetX,
            sourceOffsetY: compositionLayout.sourceOffsetY
        )
    }

    func setCompositionSourceScale(_ scale: Double) {
        compositionLayout = CompositionLayout(
            outputAspectRatio: compositionLayout.outputAspectRatio,
            sourceScale: scale,
            sourceOffsetX: compositionLayout.sourceOffsetX,
            sourceOffsetY: compositionLayout.sourceOffsetY
        )
    }

    func setCompositionSourceOffset(x: Double, y: Double) {
        compositionLayout = CompositionLayout(
            outputAspectRatio: compositionLayout.outputAspectRatio,
            sourceScale: compositionLayout.sourceScale,
            sourceOffsetX: x,
            sourceOffsetY: y
        )
    }

    func resetCompositionSourceTransform() {
        compositionLayout = CompositionLayout(outputAspectRatio: compositionLayout.outputAspectRatio)
    }

    func resetCompositionLayout() {
        compositionLayout = .default
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
            markerNameSource: .automatic,
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

    private func loadDistortionPresetLibrary() {
        do {
            distortionPresetLibrary = try projectBundleService.loadDistortionPresetLibrary()
        } catch {
            distortionPresetLibrary = .empty
            statusMessage = "Distortion preset library could not be loaded."
        }

        if selectedDistortionPresetLibraryID == nil {
            selectedDistortionPresetLibraryID = availableDistortionPresetDescriptors.first?.id
        }
    }

    private func persistDistortionPresetLibrary(statusMessage: String? = nil) {
        do {
            try projectBundleService.saveDistortionPresetLibrary(distortionPresetLibrary)
            if let statusMessage {
                self.statusMessage = statusMessage
            }
        } catch {
            self.statusMessage = "Could not save Distortion preset library: \(error.localizedDescription)"
        }
    }

    private func updateSelectedDistortionPresetLibraryDescriptor(
        _ mutate: (inout DistortionPresetDescriptor) -> Void
    ) {
        guard let selectedDistortionPresetLibraryID,
              let index = distortionPresetLibrary.presets.firstIndex(where: { $0.id == selectedDistortionPresetLibraryID }) else {
            return
        }
        mutate(&distortionPresetLibrary.presets[index])
        persistDistortionPresetLibrary()
    }

    private func uniqueDistortionPresetName(basedOn baseName: String) -> String {
        let existingNames = Set(availableDistortionPresetDescriptors.map { $0.displayName.lowercased() })
        if !existingNames.contains(baseName.lowercased()) {
            return baseName
        }

        var counter = 2
        while existingNames.contains("\(baseName) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(baseName) \(counter)"
    }

    func distortionPresetSelectionID(for marker: EffectPlanItem) -> String {
        if let reference = marker.distortion?.presetReference {
            switch reference {
            case .builtIn(let preset):
                return DistortionPresetDescriptor.builtInDescriptors.first(where: { $0.preset == preset })?.id ?? "builtin-\(preset.rawValue)"
            case .libraryPreset(let id):
                return id
            }
        }

        if let preset = marker.distortion?.preset {
            return DistortionPresetDescriptor.builtInDescriptors.first(where: { $0.preset == preset })?.id ?? "builtin-\(preset.rawValue)"
        }

        return DistortionPresetDescriptor.builtInDescriptors[0].id
    }

    private func applyDistortionPresetDescriptorToSelectedEffect(_ descriptor: DistortionPresetDescriptor) {
        let importedMapHash: String?
        switch descriptor.mapSource {
        case .preset:
            importedMapHash = nil
        case .importedMap(let id):
            importedMapHash = distortionPresetLibrary.importedMaps.first(where: { $0.id == id })?.contentHash
        }

        updateSelectedEffectMarker { marker in
            var distortion = marker.distortion ?? .defaultConfiguration
            marker.amount = min(max(descriptor.defaultAmount, 0), 1)
            distortion.presetReference = descriptor.reference
            distortion.preset = descriptor.preset
            distortion.mapSource = descriptor.mapSource
            distortion.scale = min(max(descriptor.defaultScale, 0), 1)
            distortion.backgroundBlend = min(max(descriptor.defaultBackgroundBlend, 0), 1)
            distortion.backgroundBlur = min(max(descriptor.defaultBackgroundBlur, 0), 1)
            distortion.importedMapHash = importedMapHash
            marker.distortion = distortion
        }
        syncDistortionMapOverlayVisibility()
    }

    func toggleDistortionMapOverlay() {
        guard canShowSelectedDistortionMapOverlay else {
            isShowingDistortionMapOverlay = false
            return
        }
        isShowingDistortionMapOverlay.toggle()
    }

    func hideDistortionMapOverlay() {
        isShowingDistortionMapOverlay = false
    }

    private func syncDistortionMapOverlayVisibility() {
        if !canShowSelectedDistortionMapOverlay {
            isShowingDistortionMapOverlay = false
        }
    }

    private func distortionOverlayImage(forMapID mapID: String) -> NSImage? {
        if let cached = distortionOverlayImageCache[mapID] {
            return cached
        }
        guard let mapURL = try? projectBundleService.distortionImportedMapURL(for: mapID, in: distortionPresetLibrary),
              let image = NSImage(contentsOf: mapURL) else {
            return nil
        }
        distortionOverlayImageCache[mapID] = image
        return image
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
        pendingSmartSetupSuggestions = []
        selectedSmartSetupSuggestionID = nil
        activeSmartSuggestionPreviewEndTime = nil
        smartSetupStatusMessage = nil
        isRunningSmartSetup = false
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
        pendingSmartSetupSuggestions = []
        selectedSmartSetupSuggestionID = nil
        activeSmartSuggestionPreviewEndTime = nil
        smartSetupStatusMessage = nil
        isRunningSmartSetup = false
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
            self?.scheduleDistortionLoupeRefreshIfNeeded()
        }
    }

    private func acceptSmartSetupEffectProposal(
        _ proposal: SmartSetupEffectMarkerProposal,
        suggestionID: String,
        summary: RecordingInspectionSummary
    ) {
        var effectMarkers = summary.effectMarkers
        var marker = EffectPlanItem(
            id: nextEffectMarkerID(from: effectMarkers),
            markerName: "Smart Suggestions Effect",
            sourceEventTimestamp: proposal.sourceEventTimestamp,
            startTime: proposal.startTime,
            holdStartTime: proposal.holdStartTime,
            holdEndTime: proposal.holdEndTime,
            endTime: proposal.endTime,
            enabled: true,
            displayOrder: nextEffectDisplayOrder(from: effectMarkers),
            style: proposal.style,
            amount: proposal.amount,
            blurAmount: proposal.blurAmount,
            darkenAmount: proposal.darkenAmount,
            tintAmount: proposal.tintAmount,
            cornerRadius: proposal.cornerRadius,
            feather: proposal.feather,
            tintColor: proposal.tintColor,
            focusRegion: proposal.focusRegion,
            distortion: proposal.distortion
        )
        syncEffectTiming(&marker, maxDuration: summary.duration)
        effectMarkers.append(marker)

        selectedEffectMarkerID = marker.id
        isEffectMarkerSelectionPinned = true
        if saveEffectMarkers(effectMarkers, basedOn: summary) {
            pendingSmartSetupSuggestions.removeAll { $0.suggestionID == suggestionID }
            smartSetupStatusMessage = "Accepted Smart Suggestions effect marker."
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
        syncEffectTiming(&effectMarkers[index], maxDuration: summary.duration)
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
        syncEffectTiming(&effectMarkers[index], maxDuration: summary.duration)
        saveEffectMarkers(effectMarkers, basedOn: summary)
    }

    @discardableResult
    private func saveZoomMarkers(_ markers: [ZoomPlanItem], basedOn summary: RecordingInspectionSummary) -> Bool {
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
            return true
        } catch {
            statusMessage = "Could not save zoomPlan.json: \(error.localizedDescription)"
            return false
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

    @discardableResult
    private func saveEffectMarkers(_ effectMarkers: [EffectPlanItem], basedOn summary: RecordingInspectionSummary) -> Bool {
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
                self?.scheduleDistortionLoupeRefreshIfNeeded()
            }
            return true
        } catch {
            statusMessage = "Could not save zoomPlan.json: \(error.localizedDescription)"
            return false
        }
    }

    private func nextEffectMarkerID(from markers: [EffectPlanItem]) -> String {
        let maxIndex = markers.compactMap { marker in
            Int(marker.id.replacingOccurrences(of: "effect-", with: ""))
        }.max() ?? 0
        return String(format: "effect-%04d", maxIndex + 1)
    }

    func scheduleDistortionLoupeRefresh() {
        clearDistortionLoupe()
    }

    private func scheduleDistortionLoupeRefreshIfNeeded() {
        clearDistortionLoupe()
    }

    func defaultDistortionLoupeNormalizedPoint(for marker: EffectPlanItem) -> CGPoint {
        guard let region = marker.focusRegion else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let offset = max(region.width * 0.12, 0.04)
        let rightCandidate = region.centerX + (region.width / 2) + offset
        if rightCandidate < 0.96 {
            return CGPoint(
                x: min(max(rightCandidate, 0), 1),
                y: min(max(region.centerY, 0), 1)
            )
        }

        let leftCandidate = region.centerX - (region.width / 2) - offset
        if leftCandidate > 0.04 {
            return CGPoint(
                x: min(max(leftCandidate, 0), 1),
                y: min(max(region.centerY, 0), 1)
            )
        }

        return CGPoint(
            x: min(max(region.centerX, 0), 1),
            y: min(max(region.centerY, 0), 1)
        )
    }

    private func clearDistortionLoupe() {
        distortionLoupeRenderTask?.cancel()
        distortionLoupeRenderTask = nil
        distortionLoupeImage = nil
        isRenderingDistortionLoupe = false
    }

    private func syncEffectTiming(_ marker: inout EffectPlanItem, maxDuration: Double?) {
        let clampedDuration = max(maxDuration ?? marker.endTime, 0)
        marker.startTime = min(max(marker.startTime, 0), clampedDuration)
        marker.endTime = min(max(marker.endTime, 0), clampedDuration)
        marker.holdStartTime = min(max(marker.holdStartTime, marker.startTime), marker.endTime)
        marker.holdEndTime = min(max(marker.holdEndTime, marker.holdStartTime), marker.endTime)
        marker.startTime = min(marker.startTime, marker.holdStartTime)
        marker.normalizeTiming()
        marker.refreshAutomaticMarkerName()
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
        marker.refreshAutomaticMarkerName()
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

        if let activeSmartSuggestionPreviewEndTime, currentTime >= activeSmartSuggestionPreviewEndTime - 0.02 {
            player.pause()
            isPlaybackActive = false
            self.activeSmartSuggestionPreviewEndTime = nil
            seekPlayback(to: activeSmartSuggestionPreviewEndTime)
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
            isEffectMarkerSelectionPinned = false
            return
        }

        if let manualSelectionSuppressionUntil, Date() < manualSelectionSuppressionUntil {
            return
        }

        if isEffectMarkerSelectionPinned,
           let selectedEffectMarkerID,
           summary.effectMarkers.contains(where: { $0.id == selectedEffectMarkerID }) {
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
            isEffectMarkerSelectionPinned = false
            return
        }

        if selectedEffectMarkerID != markerID {
            selectedEffectMarkerID = markerID
        }
        isEffectMarkerSelectionPinned = false
    }
}

private func makeSmartSetupAnalysis(
    bundleURL: URL,
    recordingURL: URL,
    duration: Double,
    contentCoordinateSize: CGSize,
    existingZoomMarkers: [ZoomPlanItem],
    existingEffectMarkers: [EffectPlanItem]
) async throws -> SmartSetupAnalysisResult {
    let events = try ProjectBundleService().loadRecordedEvents(from: bundleURL)
    try Task.checkCancellation()

    let context = SmartSuggestionContext(
        events: events,
        duration: duration,
        contentCoordinateSize: contentCoordinateSize,
        existingZoomMarkers: existingZoomMarkers,
        existingEffectMarkers: existingEffectMarkers
    )
    let heuristicSuggestions = SmartSuggestionAggregator.defaultAggregator().generateSuggestions(context: context)
    try Task.checkCancellation()

    let activityRegions = ActivityRegionBuilder.activityRegions(
        from: heuristicSuggestions,
        events: events,
        duration: context.duration,
        contentCoordinateSize: context.contentCoordinateSize
    )
    let frameSamplingResult = await SmartSuggestionFrameSamplerService().sampleFrames(
        recordingURL: recordingURL,
        duration: context.duration,
        regions: activityRegions
    )
    try Task.checkCancellation()

    let coreMLAnalysisResult = await SmartSuggestionCoreMLAnalysisService().analyzeUI(
        in: frameSamplingResult.samples,
        regions: activityRegions
    )
    try Task.checkCancellation()

    let visualChangeResult = SmartSuggestionVisualChangeService().analyzeChanges(
        in: frameSamplingResult.samples,
        regions: activityRegions,
        contentCoordinateSize: context.contentCoordinateSize
    )
    try Task.checkCancellation()

    let visionAnalysisService = SmartSuggestionVisionAnalysisService()
    let ocrAnalysisResult = await visionAnalysisService.analyzeText(
        in: frameSamplingResult.samples,
        regions: activityRegions
    )
    try Task.checkCancellation()

    let regionMetadata = visionAnalysisService.regionMetadata(
        for: activityRegions,
        analysisResult: ocrAnalysisResult,
        contentCoordinateSize: context.contentCoordinateSize,
        visualChangeMetadataByID: visualChangeResult.metadataByRegionID
    )
    let suggestions = visionAnalysisService.visionTunedSuggestions(
        from: heuristicSuggestions,
        regionMetadataByID: regionMetadata,
        visualChangeMetadataByID: visualChangeResult.metadataByRegionID
    )

    return SmartSetupAnalysisResult(
        heuristicSuggestions: heuristicSuggestions,
        suggestions: suggestions,
        frameDiagnostics: frameSamplingResult.diagnostics,
        ocrDiagnostics: ocrAnalysisResult.diagnostics,
        visualChangeDiagnostics: visualChangeResult.diagnostics,
        coreMLDiagnostics: coreMLAnalysisResult.diagnostics,
        regionMetadata: regionMetadata
    )
}
