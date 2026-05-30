# Managers Map

Generated: 2026-05-30 07:27:08

## Files

### Managers/CaptureMetadataManager.swift
- Lines: 43
- Imports:
- import Foundation
- Functions / Vars:
- Line 9:    private let projectBundleService: ProjectBundleService
- Line 10:    private var metadataSaveTask: Task<Void, Never>?
- Line 16:    func scheduleSave(
- Line 28:                let updatedManifest = try projectBundleService.updateCaptureMetadata(
- Line 39:    func cancelPendingSave() {

### Managers/CaptureTargetManager.swift
- Lines: 69
- Imports:
- import Foundation
- Types:
- Line 8:struct CaptureTargetRefreshResult {
- Line 16:struct CapturePermissionResult {
- Line 21:struct CaptureTargetManager {
- Functions / Vars:
- Line 9:    let displays: [ShareableCaptureTarget]
- Line 10:    let windows: [ShareableCaptureTarget]
- Line 11:    let selectedTargetID: String?
- Line 12:    let hasScreenRecordingPermission: Bool
- Line 13:    let statusMessage: String?
- Line 17:    let hasScreenRecordingPermission: Bool
- Line 18:    let statusMessage: String
- Line 22:    private let permissionsService: PermissionsService
- Line 23:    private let screenCaptureService: ScreenCaptureService
- Line 33:    func loadTargets(selectedTargetID: String?, silent: Bool) async throws -> CaptureTargetRefreshResult {
- Line 34:        let hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
- Line 35:        let targets = try await screenCaptureService.fetchTargets()
- Line 36:        let allTargets = targets.displays + targets.windows
- Line 37:        let validatedSelectedTargetID: String?
- Line 53:    func requestScreenRecordingPermission() -> CapturePermissionResult {
- Line 55:        let hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
- Line 64:    private func defaultTargetStatusMessage(hasScreenRecordingPermission: Bool) -> String {

### Managers/ExportManager.swift
- Lines: 88
- Imports:
- import AppKit
- import Foundation
- import UniformTypeIdentifiers
- Types:
- Line 7:    enum Outcome {
- Functions / Vars:
- Line 13:    private let exportRenderService = ExportRenderService()
- Line 14:    private var exportTask: Task<Void, Never>?
- Line 15:    private var activeExportOperationID = UUID()
- Line 17:    var hasActiveExport: Bool {
- Line 21:    func chooseExportDestination(defaultName: String) -> URL? {
- Line 22:        let panel = NSSavePanel()
- Line 32:    func exportRecording(
- Line 39:        let exportOperationID = UUID()
- Line 45:                let result = try await exportRenderService.exportRecording(
- Line 52:                    let clampedProgress = max(0, min(progress, 1))
- Line 77:    func cancelExport() {
- Line 82:    func reset() {

### Managers/FlowTrackOnboardingManager.swift
- Lines: 288
- Imports:
- import Foundation
- import Observation
- Types:
- Line 4:struct FlowTrackOnboardingState: Codable, Equatable {
- Line 22:enum FlowTrackOnboardingStage: String, CaseIterable, Codable, Identifiable, Hashable {
- Line 131:struct FlowTrackOnboardingStore {
- Functions / Vars:
- Line 5:    var schemaVersion: Int
- Line 6:    var completedStages: Set<FlowTrackOnboardingStage>
- Line 7:    var hasCompletedOnboarding: Bool
- Line 8:    var dismissedVersion: Int
- Line 10:    static let currentSchemaVersion = 1
- Line 12:    static var initial: FlowTrackOnboardingState {
- Line 32:    var id: String { rawValue }
- Line 34:    static let activeTourStages: [FlowTrackOnboardingStage] = [
- Line 43:    var title: String {
- Line 64:    var body: String {
- Line 85:    var iconName: String {
- Line 106:    var stageIndex: Int {
- Line 110:    var progressIndex: Int {
- Line 114:    var progressCount: Int {
- Line 118:    var nextStage: FlowTrackOnboardingStage? {
- Line 119:        let nextIndex = stageIndex + 1
- Line 124:    var previousStage: FlowTrackOnboardingStage? {
- Line 125:        let previousIndex = stageIndex - 1
- Line 133:        static let schemaVersion = "FlowTrackOnboarding.schemaVersion"
- Line 134:        static let completedStages = "FlowTrackOnboarding.completedStages"
- Line 135:        static let hasCompleted = "FlowTrackOnboarding.hasCompleted"
- Line 136:        static let dismissedVersion = "FlowTrackOnboarding.dismissedVersion"
- Line 139:    private let userDefaults: UserDefaults
- Line 145:    func loadState() -> FlowTrackOnboardingState {
- Line 146:        let storedSchemaVersion = userDefaults.integer(forKey: Key.schemaVersion)
- Line 151:        let completedStages = Set(
- Line 164:    func saveState(_ state: FlowTrackOnboardingState) {
- Line 171:    func reset() {
- Line 178:    private func sortedStageIDs(from stages: Set<FlowTrackOnboardingStage>) -> [String] {
- Line 188:    private let store: FlowTrackOnboardingStore
- Line 189:    private var state: FlowTrackOnboardingState
- Line 199:        let resolvedStore = store ?? FlowTrackOnboardingStore()
- Line 201:        let loadedState = resolvedStore.loadState()
- Line 211:    func startFirstRunIfNeeded() {
- Line 218:    func startManualTour() {
- Line 224:    func advance() {
- Line 235:    func back() {
- Line 240:    func skip() {
- Line 248:    func markComplete(_ stage: FlowTrackOnboardingStage) {
- Line 256:    func reset() {
- Line 267:    private func completeOnboarding() {
- Line 275:    private func nextIncompleteStage() -> FlowTrackOnboardingStage? {
- Line 279:    private func persistState() {
- SwiftUI State:
- Line 186:@Observable

### Managers/LibraryManager.swift
- Lines: 14
- Imports:
- import Foundation
- Types:
- Line 3:struct LibraryManager {
- Functions / Vars:
- Line 4:    let projectBundleService: ProjectBundleService
- Line 6:    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
- Line 10:    func bundleURL(for item: CaptureLibraryItem) throws -> URL {
- Line 11:        let libraryRoot = try projectBundleService.libraryRootURL()

### Managers/PlaybackTransportManager.swift
- Lines: 104
- Imports:
- import Foundation
- Types:
- Line 3:struct PlaybackTransportPlan {
- Line 4:    enum PlayerCommand {
- Line 18:struct PlaybackTransportManager {
- Functions / Vars:
- Line 9:    let shouldResetPreviewPresentation: Bool
- Line 10:    let shouldStopPreviewPlayback: Bool
- Line 11:    let stopPreviewSeekTime: Double
- Line 12:    let retainSlate: Bool
- Line 13:    let shouldCancelPreviewMode: Bool
- Line 14:    let seekTime: Double?
- Line 15:    let playerCommand: PlayerCommand?
- Line 19:    func togglePlan(
- Line 53:    func interactiveSeekPlan(
- Line 75:    func jumpToStartPlan(
- Line 90:    func cancelPreviewPlan(

### Managers/TimelineScrubManager.swift
- Lines: 136
- Imports:
- import Foundation
- Types:
- Line 3:struct TimelineScrubBeginPlan {
- Line 16:struct TimelineScrubUpdatePlan {
- Line 22:struct TimelineScrubEndPlan {
- Line 31:struct TimelineDirectSeekPlan {
- Line 43:struct TimelineScrubManager {
- Functions / Vars:
- Line 4:    let shouldResetPreviewPresentation: Bool
- Line 5:    let shouldStopPreviewPlayback: Bool
- Line 6:    let stopPreviewSeekTime: Double
- Line 7:    let retainSlate: Bool
- Line 8:    let shouldCancelPreviewMode: Bool
- Line 9:    let wasPlayingBeforeTimelineScrub: Bool
- Line 10:    let shouldPause: Bool
- Line 11:    let shouldSetPlaybackInactive: Bool
- Line 12:    let isTimelineScrubbing: Bool
- Line 13:    let suppressionInterval: TimeInterval
- Line 17:    let selectedZoomMarkerID: String?
- Line 18:    let selectedEffectMarkerID: String?
- Line 19:    let targetTime: Double
- Line 23:    let selectedZoomMarkerID: String?
- Line 24:    let selectedEffectMarkerID: String?
- Line 25:    let targetTime: Double
- Line 26:    let isTimelineScrubbing: Bool
- Line 27:    let suppressionInterval: TimeInterval
- Line 28:    let shouldResumePlayback: Bool
- Line 32:    let shouldResetPreviewPresentation: Bool
- Line 33:    let shouldStopPreviewPlayback: Bool
- Line 34:    let stopPreviewSeekTime: Double
- Line 35:    let retainSlate: Bool
- Line 36:    let shouldCancelPreviewMode: Bool
- Line 37:    let selectedZoomMarkerID: String?
- Line 38:    let selectedEffectMarkerID: String?
- Line 39:    let suppressionInterval: TimeInterval?
- Line 40:    let targetTime: Double
- Line 44:    func beginScrubPlan(
- Line 70:    func updateScrubPlan(
- Line 87:    func endScrubPlan(
- Line 108:    func directSeekPlan(
- Line 121:        let suppressionInterval: TimeInterval? =

