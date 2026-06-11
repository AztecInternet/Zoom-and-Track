# Swift Symbols

Generated: 2026-06-11 10:05:29

## App/ContentView.swift
- Line 12:struct ContentView: View {
- Line 97:    struct OverlayMapping {
- Line 106:    struct ZoomPreviewState {
- Line 111:    struct EffectPreviewState {
- Line 122:    struct PrecisionLoupeFrame {
- Line 127:    enum EffectRegionHandle: Hashable {
- Line 138:    enum ActiveEffectHoldPoint {
- Line 143:    struct ZoomStateEvent {
- Line 149:    enum MotionDirection {
- Line 154:    struct MotionProgressSample {
- Line 196:    enum CaptureInfoField: Hashable {
- Line 202:    enum MotionTuning {
- Line 210:    struct LibraryFilterOption: Identifiable {
- Line 361:    func isGuidedTourStage(_ stage: FlowTrackOnboardingStage) -> Bool {
- Line 676:    func effectTintColorBinding(for marker: EffectPlanItem) -> Binding<Color> {
- Line 696:    func mappedOverlayPoint(
- Line 735:    func infoRow(title: String, value: String) -> some View {
- Line 746:    func metadataItem(_ title: String, _ value: String, multiline: Bool = false) -> some View {
- Line 861:    func selectedSmartSetupTimelineRange() -> SmartSetupSourceTimeRange? {
- Line 871:    func selectedSmartSetupTimelineEventTimes() -> [Double] {
- Line 1010:    func updateTimelineScrubAutoScroll(cursorX: CGFloat, width: CGFloat, duration: Double) {
- Line 1040:    func cancelTimelineScrubAutoScroll() {
- Line 1077:    func beginTimelineMarkerDrag(
- Line 1097:    func updateTimelineMarkerDrag(
- Line 1121:    func finishTimelineMarkerDrag(
- Line 1300:    func navigateToPreviousMarkerFromMenu() {
- Line 1304:    func navigateToNextMarkerFromMenu() {
- Line 1364:    func reviewHeaderActionIcon(_ systemName: String, action: ReviewHeaderAction) -> some View {
- Line 1379:    func sectionHeader(title: String, subtitle: String, accentWidth: CGFloat) -> some View {
- Line 1395:    func setTimelineHover(markerID: String, phase: MarkerTimingPhase?, anchor: CGPoint) {
- Line 1402:    func clearTimelineHover() {
- Line 1411:    func setEffectTimelineHover(markerID: String, anchor: CGPoint) {
- Line 1416:    func clearEffectTimelineHover() {
- Line 1421:    func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
- Line 1431:    func hoveredEffectTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: EffectPlanItem, markerNumber: Int)? {
- Line 1440:    func displayedTimelinePhase(for marker: ZoomPlanItem) -> MarkerTimingPhase? {
- Line 1455:    func isMarkerPlaybackHighlighted(_ marker: ZoomPlanItem) -> Bool {
- Line 1467:    func isEffectPlaybackHighlighted(_ marker: EffectPlanItem) -> Bool {
- Line 1471:    func displayedMarkerList(_ markers: [ZoomPlanItem], previewOrder: [String]? = nil) -> [ZoomPlanItem] {
- Line 1492:    func displayedEffectMarkerList(_ markers: [EffectPlanItem]) -> [EffectPlanItem] {
- Line 1564:struct SharingAnchorView: NSViewRepresentable {
- Line 1567:    func makeNSView(context: Context) -> NSView {
- Line 1575:    func updateNSView(_ nsView: NSView, context: Context) {
- Line 1586:enum ReviewHeaderAction {
- Line 1592:enum AppTab: String, CaseIterable, Identifiable {
- Line 1627:struct MarkerListEntry: Identifiable {

## App/FlowTrackCommands.swift
- Line 3:struct FlowTrackCommandContext {
- Line 36:extension FocusedValues {
- Line 43:struct FlowTrackCommands: Commands {

## App/TutorialCaptureApp.swift
- Line 9:struct TutorialCaptureApp: App {

## Managers/CaptureMetadataManager.swift
- Line 16:    func scheduleSave(
- Line 39:    func cancelPendingSave() {

## Managers/CaptureTargetManager.swift
- Line 8:struct CaptureTargetRefreshResult {
- Line 16:struct CapturePermissionResult {
- Line 21:struct CaptureTargetManager {
- Line 33:    func loadTargets(selectedTargetID: String?, silent: Bool) async throws -> CaptureTargetRefreshResult {
- Line 53:    func requestScreenRecordingPermission() -> CapturePermissionResult {

## Managers/ExportManager.swift
- Line 7:    enum Outcome {
- Line 21:    func chooseExportDestination(defaultName: String) -> URL? {
- Line 32:    func exportRecording(
- Line 77:    func cancelExport() {
- Line 82:    func reset() {

## Managers/FlowTrackOnboardingManager.swift
- Line 4:struct FlowTrackOnboardingState: Codable, Equatable {
- Line 22:enum FlowTrackOnboardingStage: String, CaseIterable, Codable, Identifiable, Hashable {
- Line 131:struct FlowTrackOnboardingStore {
- Line 145:    func loadState() -> FlowTrackOnboardingState {
- Line 164:    func saveState(_ state: FlowTrackOnboardingState) {
- Line 171:    func reset() {
- Line 211:    func startFirstRunIfNeeded() {
- Line 218:    func startManualTour() {
- Line 224:    func advance() {
- Line 235:    func back() {
- Line 240:    func skip() {
- Line 248:    func markComplete(_ stage: FlowTrackOnboardingStage) {
- Line 256:    func reset() {

## Managers/LibraryManager.swift
- Line 3:struct LibraryManager {
- Line 6:    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
- Line 10:    func bundleURL(for item: CaptureLibraryItem) throws -> URL {

## Managers/PlaybackTransportManager.swift
- Line 3:struct PlaybackTransportPlan {
- Line 4:    enum PlayerCommand {
- Line 18:struct PlaybackTransportManager {
- Line 19:    func togglePlan(
- Line 53:    func interactiveSeekPlan(
- Line 75:    func jumpToStartPlan(
- Line 90:    func cancelPreviewPlan(

## Managers/TimelineScrubManager.swift
- Line 3:struct TimelineScrubBeginPlan {
- Line 16:struct TimelineScrubUpdatePlan {
- Line 22:struct TimelineScrubEndPlan {
- Line 31:struct TimelineDirectSeekPlan {
- Line 43:struct TimelineScrubManager {
- Line 44:    func beginScrubPlan(
- Line 70:    func updateScrubPlan(
- Line 87:    func endScrubPlan(
- Line 108:    func directSeekPlan(

## Models/Models.swift
- Line 9:enum CaptureTargetKind: String, Codable {
- Line 14:struct ShareableCaptureTarget: Identifiable, Equatable {
- Line 42:enum RecordingSessionState: Equatable {
- Line 52:struct CaptureSource: Codable {
- Line 66:enum OutputAspectRatio: String, Codable, Equatable, CaseIterable, Identifiable {
- Line 118:struct CompositionLayout: Codable, Equatable {
- Line 149:struct ProjectManifest: Codable {
- Line 224:    func encode(to encoder: Encoder) throws {
- Line 241:struct CaptureMetadata: Equatable {
- Line 263:enum CaptureType: String, Codable, CaseIterable, Identifiable {
- Line 294:struct CaptureLibraryItem: Codable, Identifiable, Equatable {
- Line 378:enum CaptureLibraryItemStatus: String, Codable {
- Line 404:struct CaptureLibraryIndex: Codable {
- Line 409:struct CaptureLibrarySnapshot {
- Line 414:struct RecordingWorkspace {
- Line 422:enum RecordedEventType: String, Codable {
- Line 430:struct RecordedEvent: Codable {
- Line 437:struct RecordedEventEnvelope: Codable {
- Line 443:struct ZoomPlanEnvelope: Codable {
- Line 472:enum ZoomEaseStyle: String, Codable, CaseIterable, Identifiable {
- Line 497:enum ZoomType: String, Codable, CaseIterable, Identifiable {
- Line 519:enum NoZoomFallbackMode: String, Codable, CaseIterable, Identifiable {
- Line 535:struct NoZoomOverflowRegion: Codable, Equatable {
- Line 542:enum EffectStyle: String, Codable, CaseIterable, Identifiable {
- Line 574:enum DistortionPreset: String, Codable, CaseIterable, Identifiable {
- Line 590:enum DistortionPresetKind: String, Codable, CaseIterable, Identifiable {
- Line 597:enum DistortionPresetReference: Codable, Equatable {
- Line 623:    func encode(to encoder: Encoder) throws {
- Line 636:enum DistortionMapSource: Codable, Equatable {
- Line 662:    func encode(to encoder: Encoder) throws {
- Line 675:struct DistortionImportedMapAsset: Codable, Identifiable, Equatable {
- Line 684:struct DistortionPresetDescriptor: Codable, Identifiable, Equatable {
- Line 733:struct DistortionPresetLibrary: Codable, Equatable {
- Line 745:struct DistortionConfiguration: Codable, Equatable {
- Line 850:struct DistortionEffectDefault: Codable, Equatable {
- Line 860:struct BlurEffectDefault: Codable, Equatable {
- Line 866:struct DarkenEffectDefault: Codable, Equatable {
- Line 872:struct TintEffectDefault: Codable, Equatable {
- Line 882:struct CreatorEffectDefaults: Codable, Equatable {
- Line 923:enum DistortionColorEffectPalette: String, Codable, CaseIterable, Identifiable {
- Line 948:struct EffectFocusRegion: Codable, Equatable {
- Line 955:struct EffectTintColor: Codable, Equatable {
- Line 964:enum MarkerNameSource: String, Codable, Equatable {
- Line 974:struct EffectPlanItem: Codable, Identifiable, Equatable {
- Line 1107:    func encode(to encoder: Encoder) throws {
- Line 1190:enum ZoomMarkerKind: String, Codable {
- Line 1194:enum ClickPulsePreset: String, Codable, CaseIterable, Identifiable {
- Line 1219:struct ClickPulseConfiguration: Codable, Equatable {
- Line 1240:struct ZoomPlanItem: Codable, Identifiable {
- Line 1484:enum MarkerNameFormatter {
- Line 1494:struct RecordingInspectionSummary {
- Line 1587:enum SharedMotionEngine {
- Line 1588:    enum CoordinateSpace {
- Line 1593:    struct PreviewState {
- Line 1598:    struct ClickPulseRenderState {
- Line 1603:    struct OverlayGeometryResolution {
- Line 1609:    struct Timeline {

## Models/SmartSetupModels.swift
- Line 3:struct SmartSetupSuggestionEnvelope: Codable, Equatable {
- Line 22:struct SmartSetupSuggestion: Codable, Equatable, Identifiable {
- Line 88:enum SmartSetupSuggestionKind: String, Codable, CaseIterable {
- Line 94:enum SmartSetupSuggestionReason: String, Codable, CaseIterable {
- Line 103:struct SmartSetupCandidateScore: Codable, Equatable {
- Line 113:struct SmartSetupScoreComponent: Codable, Equatable {
- Line 119:struct SmartSetupSourceTimeRange: Codable, Equatable {
- Line 129:struct SmartSetupSourceEventReference: Codable, Equatable {
- Line 150:enum SmartSetupMarkerProposal: Codable, Equatable {
- Line 157:struct SmartSetupZoomMarkerAdjustmentProposal: Codable, Equatable {
- Line 168:struct SmartSetupZoomMarkerProposal: Codable, Equatable {
- Line 187:struct SmartSetupEffectMarkerProposal: Codable, Equatable {
- Line 205:struct SmartSetupRegionTightenProposal: Codable, Equatable {
- Line 224:extension SmartSetupSuggestion {
- Line 225:    func reviewPlaybackRange(recordingDuration: Double) -> SmartSetupSourceTimeRange {

## Services/CreatorEffectDefaultsService.swift
- Line 8:struct CreatorEffectDefaultsService {
- Line 15:    func loadCreatorEffectDefaults() -> CreatorEffectDefaults {
- Line 32:    func saveCreatorEffectDefaults(_ defaults: CreatorEffectDefaults) throws {

## Services/FlowTrackThemeStore.swift
- Line 3:struct FlowTrackThemeStore {
- Line 31:    func loadLibrary() -> FlowTrackThemeLibrary {
- Line 55:    func saveLibrary(_ library: FlowTrackThemeLibrary) throws {

## Services/InputEventCaptureService.swift
- Line 31:    func start() {
- Line 70:    func setSessionStart(videoTimestamp: CMTime, uptime: TimeInterval) {
- Line 75:    func stop() {
- Line 89:    func finish() -> [RecordedEvent] {
- Line 100:    func cancel() {

## Services/MarkerPreviewCacheService.swift
- Line 10:    func cachedPreview(
- Line 34:    func cachedEffectPreview(
- Line 58:    func storePreview(
- Line 78:    func storeEffectPreview(
- Line 98:    func pruneStaleFiles() {

## Services/MarkerPreviewRenderService.swift
- Line 20:    func value(for key: String) -> DistortionImportedColorMaskSet? {
- Line 26:    func store(_ value: DistortionImportedColorMaskSet, for key: String) {
- Line 33:struct RenderedMarkerPreview {
- Line 61:    func renderPreview(
- Line 228:    func renderEffectPreview(
- Line 390:    func renderDistortionLoupeFrame(
- Line 518:    func makeRealtimeEffectPreviewImage(
- Line 636:enum ExportRenderPhase {
- Line 642:struct ExportRenderResult {
- Line 668:    func cancelExport() {
- Line 672:    func exportRecording(

## Services/MediaWriterService.swift
- Line 18:    func startWriting(to url: URL, width: Int, height: Int) throws {
- Line 55:    func append(sampleBuffer: CMSampleBuffer) throws {
- Line 78:    func finishWriting() async throws {
- Line 88:    func cancelWriting() {

## Services/PermissionsService.swift
- Line 9:struct PermissionsService {
- Line 10:    func hasScreenRecordingPermission() -> Bool {
- Line 14:    func requestScreenRecordingPermission() -> Bool {

## Services/ProjectBundleService.swift
- Line 14:struct ProjectBundleService {
- Line 22:    enum OutputDirectoryResolution {
- Line 28:    enum RecordingBundleResolution {
- Line 34:    func createWorkspace(outputDirectory: URL? = nil, captureMetadata: CaptureMetadata) throws -> RecordingWorkspace {
- Line 92:    func finalizeWorkspace(_ workspace: RecordingWorkspace, manifest: ProjectManifest, events: [RecordedEvent]) throws -> URL {
- Line 126:    func cleanupWorkspace(_ workspace: RecordingWorkspace?) {
- Line 135:    func chooseOutputDirectory() -> URL? {
- Line 155:    func resolvedSelectedOutputDirectory() -> URL? {
- Line 164:    func resolveSelectedOutputDirectory() -> OutputDirectoryResolution {
- Line 199:    func openRecordingBundle() -> URL? {
- Line 218:    func loadDistortionPresetLibrary() throws -> DistortionPresetLibrary {
- Line 228:    func saveDistortionPresetLibrary(_ library: DistortionPresetLibrary) throws {
- Line 234:    func chooseDistortionMapImage() -> URL? {
- Line 245:    func importDistortionMap(from sourceURL: URL, suggestedName: String? = nil) throws -> DistortionImportedMapAsset {
- Line 270:    func distortionImportedMapURL(for mapID: String, in library: DistortionPresetLibrary? = nil) throws -> URL? {
- Line 279:    func loadRecordingInspection(from bundleURL: URL) async throws -> RecordingInspectionSummary {
- Line 344:    func loadRecordedEventEnvelope(from bundleURL: URL) throws -> RecordedEventEnvelope {
- Line 365:    func loadRecordedEvents(from bundleURL: URL) throws -> [RecordedEvent] {
- Line 369:    func persistLastRecordingBundle(_ url: URL) -> Bool {
- Line 377:    func resolveLastRecordingBundle() -> RecordingBundleResolution {
- Line 399:    func beginPlaybackAccess(for bundleURL: URL) throws -> URL? {
- Line 419:    func endPlaybackAccess(_ url: URL?) {
- Line 423:    func saveZoomPlan(_ zoomPlan: ZoomPlanEnvelope, in bundleURL: URL) throws {
- Line 434:    func updateCaptureMetadata(
- Line 471:    func libraryRootURL() throws -> URL {
- Line 478:    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
- Line 510:    func registerCaptureInLibrary(_ summary: RecordingInspectionSummary) throws {

## Services/RecordingCoordinator.swift
- Line 37:    func startRecording(
- Line 92:    func stopRecording() async {

## Services/ScreenCaptureService.swift
- Line 24:    func fetchTargets() async throws -> (displays: [ShareableCaptureTarget], windows: [ShareableCaptureTarget]) {
- Line 108:    func startCapture(
- Line 133:    func stopCapture() async throws {
- Line 182:extension ScreenCaptureService: SCStreamOutput, SCStreamDelegate {
- Line 183:    func stream(_ stream: SCStream, didStopWithError error: any Error) {
- Line 187:    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {

## Services/SmartSetupSuggestionService.swift
- Line 4:struct SmartSetupSuggestionService {
- Line 25:    func generateSuggestions(
- Line 85:        func flushCurrentGroup() {

## Services/SmartSuggestionCoreMLAnalysisService.swift
- Line 6:enum SmartSuggestionCoreMLUIElementType: String, CaseIterable {
- Line 20:enum SmartSuggestionCoreMLAnalysisSource: String {
- Line 26:struct SmartSuggestionCoreMLObservation {
- Line 37:struct SmartSuggestionCoreMLDiagnostics {
- Line 49:struct SmartSuggestionCoreMLAnalysisResult {
- Line 54:struct SmartSuggestionCoreMLAnalysisService {
- Line 72:    func analyzeUI(

## Services/SmartSuggestionFrameSamplerService.swift
- Line 5:struct ActivityRegion: Identifiable {
- Line 6:    enum Kind: String {
- Line 24:struct ActivityRegionFrameSample {
- Line 31:struct ActivityRegionFrameSamplingDiagnostics {
- Line 38:struct ActivityRegionFrameSamplingResult {
- Line 43:struct ActivityRegionBuilder {
- Line 265:    func store(image: CGImage, actualTime: Double) {
- Line 278:    func sampleFrames(

## Services/SmartSuggestionProviders.swift
- Line 4:struct SmartSuggestionContext {
- Line 12:protocol SmartSuggestionProvider {
- Line 15:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion]
- Line 18:struct RuleSmartSuggestionProvider: SmartSuggestionProvider {
- Line 27:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
- Line 91:struct ExistingEditReviewSmartSuggestionProvider: SmartSuggestionProvider {
- Line 99:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
- Line 710:struct ClickClusterSmartSuggestionProvider: SmartSuggestionProvider {
- Line 723:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
- Line 778:        func flushCurrentCluster() {
- Line 1069:struct ClickHeuristicSmartSuggestionProvider: SmartSuggestionProvider {
- Line 1076:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
- Line 1204:struct TemplateSmartSuggestionProvider: SmartSuggestionProvider {
- Line 1207:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
- Line 1291:struct SmartSuggestionAggregator {
- Line 1324:    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
- Line 2576:    func stableChoice(from options: [String]) -> String {

## Services/SmartSuggestionVisionAnalysisService.swift
- Line 5:struct SmartSuggestionOCRTextObservation {
- Line 13:struct SmartSuggestionOCRDiagnostics {
- Line 25:struct SmartSuggestionOCRAnalysisResult {
- Line 30:enum SmartSuggestionUIContext: String, CaseIterable {
- Line 68:enum SmartSuggestionOCRTextRole: String {
- Line 78:struct SmartSuggestionOCRRegionMetadata {
- Line 100:struct SmartSuggestionVisionAnalysisService {
- Line 112:    func analyzeText(
- Line 185:    func regionMetadata(
- Line 203:    func visionTunedSuggestions(
- Line 1081:        func addScore(_ context: SmartSuggestionUIContext, _ amount: Double, supportingText: String? = nil) {

## Services/SmartSuggestionVisualChangeService.swift
- Line 4:struct SmartSuggestionVisualChangeMetadata {
- Line 21:struct SmartSuggestionVisualChangeDiagnostics {
- Line 30:struct SmartSuggestionVisualChangeAnalysisResult {
- Line 35:struct SmartSuggestionVisualChangeService {
- Line 57:    func analyzeChanges(

## ViewModels/CaptureSetupViewModel.swift
- Line 23:    enum PlaybackPresentationMode {
- Line 30:    enum PlaybackTransitionPlateState {
- Line 37:    enum ExportState: Equatable {
- Line 338:    func load() async {
- Line 360:    func activateCaptureTarget(_ target: ShareableCaptureTarget) {
- Line 378:    func requestPermission() async {
- Line 384:    func startRecording() async {
- Line 414:    func stopRecording() async {
- Line 423:    func revealInFinder() {
- Line 428:    func chooseOutputFolder() {
- Line 434:    func selectDistortionPresetLibraryPreset(_ presetID: String) {
- Line 438:    func createDistortionPresetFromImportedMap() {
- Line 473:    func duplicateSelectedDistortionPreset() {
- Line 492:    func deleteSelectedDistortionPreset() {
- Line 502:    func renameSelectedDistortionPreset(_ name: String) {
- Line 513:    func setSelectedDistortionLibraryPresetEnginePreset(_ preset: DistortionPreset) {
- Line 522:    func setSelectedDistortionLibraryPresetMapSource(_ mapSource: DistortionMapSource) {
- Line 528:    func setSelectedDistortionLibraryPresetDefaultAmount(_ amount: Double) {
- Line 534:    func setSelectedDistortionLibraryPresetDefaultScale(_ scale: Double) {
- Line 540:    func setSelectedDistortionLibraryPresetDefaultBackgroundBlend(_ blend: Double) {
- Line 546:    func setSelectedDistortionLibraryPresetDefaultBackgroundBlur(_ blur: Double) {
- Line 552:    func openRecording() {
- Line 557:    func runSmartSetup() {
- Line 843:    func acceptSmartSetupSuggestion(_ suggestionID: String) {
- Line 859:    func selectSmartSetupSuggestion(_ suggestionID: String, previewRange: Bool = true) {
- Line 868:    func clearSelectedSmartSetupSuggestion() {
- Line 873:    func dismissSmartSetupSuggestion(_ suggestionID: String) {
- Line 884:    func clearSmartSetupSuggestions() {
- Line 922:    func exportRecording() {
- Line 973:    func cancelExport() {
- Line 979:    func dismissExportSheet() {
- Line 1024:    func revealExportInFinder() {
- Line 1029:    func openLibraryCapture(_ item: CaptureLibraryItem) {
- Line 1042:    func revealLibraryCapture(_ item: CaptureLibraryItem) {
- Line 1051:    func startMarkerPreview(_ markerID: String) {
- Line 1155:    func togglePlayback() {
- Line 1187:    func seekPlaybackInteractively(to seconds: Double) {
- Line 1211:    func jumpPlaybackToStart() {
- Line 1234:    func cancelPlaybackPreview() {
- Line 1252:    func beginTimelineScrub() {
- Line 1283:    func updateTimelineScrub(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 1296:    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 1316:    func seekTimelineDirectly(
- Line 1355:    func nudgeSelectedTimelineMarker(by delta: Double, stepDuration: Double? = nil) {
- Line 1378:    func updateSelectedTimelineMarkerDrag(to seconds: Double) {
- Line 1383:    func commitSelectedTimelineMarkerDrag(to seconds: Double) {
- Line 1388:    func nudgeSelectedEffectTimelineMarker(by delta: Double, stepDuration: Double? = nil) {
- Line 1426:    func setSelectedMarkerEnabled(_ enabled: Bool) {
- Line 1432:    func setMarkerEnabled(_ enabled: Bool, for markerID: String) {
- Line 1438:    func toggleMarkerEnabled(_ markerID: String) {
- Line 1444:    func setMarkerName(_ markerName: String?, for markerID: String) {
- Line 1457:    func setSelectedMarkerZoomScale(_ zoomScale: Double) {
- Line 1463:    func setSelectedMarkerLeadInTime(_ leadInTime: Double) {
- Line 1470:    func setSelectedMarkerZoomInDuration(_ zoomInDuration: Double) {
- Line 1477:    func setSelectedMarkerHoldDuration(_ holdDuration: Double) {
- Line 1484:    func setSelectedMarkerZoomOutDuration(_ zoomOutDuration: Double) {
- Line 1491:    func setSelectedMarkerEaseStyle(_ easeStyle: ZoomEaseStyle) {
- Line 1497:    func setSelectedMarkerZoomType(_ zoomType: ZoomType) {
- Line 1507:    func setSelectedMarkerBounceAmount(_ bounceAmount: Double) {
- Line 1513:    func setSelectedMarkerNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 1519:    func setSelectedMarkerNoZoomOverflowRegion(_ region: NoZoomOverflowRegion?) {
- Line 1525:    func clearSelectedMarkerNoZoomOverflowRegion() {
- Line 1529:    func setSelectedEffectFocusRegion(_ region: EffectFocusRegion?) {
- Line 1541:    func clearSelectedEffectFocusRegion() {
- Line 1545:    func selectEffectMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 1567:    func selectZoomMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 1586:    func previewEffectMarker(_ markerID: String) {
- Line 1609:    func startEffectMarkerPreview(_ markerID: String) {
- Line 1715:    func setSelectedEffectMarkerEnabled(_ enabled: Bool) {
- Line 1721:    func toggleEffectMarkerEnabled(_ markerID: String) {
- Line 1727:    func setEffectMarkerName(_ markerName: String?, for markerID: String) {
- Line 1740:    func setSelectedEffectStyle(_ style: EffectStyle) {
- Line 1756:    func setSelectedEffectAmount(_ amount: Double) {
- Line 1762:    func setDistortionLoupePoint(_ point: CGPoint) {
- Line 1770:    func resetDistortionLoupePointToDefault() {
- Line 1775:    func setSelectedEffectDistortionPreset(_ preset: DistortionPreset) {
- Line 1782:    func setSelectedEffectDistortionPresetSelectionID(_ presetID: String) {
- Line 1789:    func setSelectedEffectDistortionScale(_ scale: Double) {
- Line 1798:    func setSelectedEffectDistortionBackgroundBlend(_ blend: Double) {
- Line 1807:    func setSelectedEffectDistortionBackgroundBlur(_ blur: Double) {
- Line 1816:    func setSelectedEffectDistortionColorGlowStrength(_ strength: Double) {
- Line 1825:    func setSelectedEffectDistortionColorGlowRadius(_ radius: Double) {
- Line 1834:    func setSelectedEffectDistortionColorAnimationIntensity(_ intensity: Double) {
- Line 1843:    func setSelectedEffectDistortionColorCoreOpacity(_ opacity: Double) {
- Line 1852:    func setSelectedEffectDistortionColorEffectPalette(_ palette: DistortionColorEffectPalette) {
- Line 1861:    func saveSelectedDistortionAsCreatorDefault() {
- Line 1865:    func applyCreatorDistortionDefaultsToSelectedEffect() {
- Line 1869:    func saveCurrentEffectStyleAsCreatorDefault() {
- Line 1898:    func applyCreatorDefaultsToSelectedEffectStyle() {
- Line 1925:    func setSelectedEffectBlurAmount(_ amount: Double) {
- Line 1935:    func setSelectedEffectDarkenAmount(_ amount: Double) {
- Line 1945:    func setSelectedEffectTintAmount(_ amount: Double) {
- Line 1955:    func setSelectedEffectFadeInDuration(_ duration: Double) {
- Line 1961:    func setSelectedEffectFadeOutDuration(_ duration: Double) {
- Line 1967:    func setSelectedEffectHoldStartTime(_ time: Double) {
- Line 1978:    func setSelectedEffectHoldEndTime(_ time: Double) {
- Line 1989:    func setSelectedEffectHoldDuration(_ duration: Double) {
- Line 1995:    func setSelectedEffectCornerRadius(_ radius: Double) {
- Line 2001:    func setSelectedEffectFeather(_ feather: Double) {
- Line 2007:    func setSelectedEffectTintColor(_ tintColor: EffectTintColor) {
- Line 2013:    func addEffectMarker(at timestamp: Double? = nil) {
- Line 2051:    func deleteSelectedEffectMarker() {
- Line 2060:    func reorderEffectMarkerList(to orderedMarkerIDs: [String]) {
- Line 2080:    func setDefaultNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 2085:    func setSelectedMarkerClickPulseEnabled(_ enabled: Bool) {
- Line 2096:    func setSelectedMarkerClickPulsePreset(_ preset: ClickPulsePreset) {
- Line 2107:    func setCurrentCaptureTitle(_ title: String) {
- Line 2112:    func setCurrentCaptureCollectionName(_ collectionName: String) {
- Line 2117:    func setCurrentCaptureProjectName(_ projectName: String) {
- Line 2122:    func setCurrentCaptureType(_ captureType: CaptureType) {
- Line 2127:    func setCompositionAspectRatio(_ aspectRatio: OutputAspectRatio) {
- Line 2136:    func setCompositionSourceScale(_ scale: Double) {
- Line 2145:    func setCompositionSourceOffset(x: Double, y: Double) {
- Line 2154:    func resetCompositionSourceTransform() {
- Line 2158:    func resetCompositionLayout() {
- Line 2162:    func deleteSelectedMarker() {
- Line 2170:    func duplicateSelectedMarker() {
- Line 2181:    func addClickFocusMarker(at sourcePoint: CGPoint, timestamp: Double? = nil) {
- Line 2233:    func reorderMarkerList(to orderedMarkerIDs: [String]) {
- Line 2252:    func moveSelectedMarker(to sourcePoint: CGPoint) {
- Line 2379:    func refreshLibrary() async {
- Line 2453:    func distortionPresetSelectionID(for marker: EffectPlanItem) -> String {
- Line 2494:    func toggleDistortionMapOverlay() {
- Line 2502:    func hideDistortionMapOverlay() {
- Line 2886:    func scheduleDistortionLoupeRefresh() {
- Line 2894:    func defaultDistortionLoupeNormalizedPoint(for marker: EffectPlanItem) -> CGPoint {

## Views/Capture/CaptureSetupViews.swift
- Line 3:extension ContentView {
- Line 261:    func nudgeCompositionOffset(x xDelta: Double, y yDelta: Double) {
- Line 452:    func targetSection(title: String, targets: [ShareableCaptureTarget]) -> some View {
- Line 470:    func targetRow(_ target: ShareableCaptureTarget) -> some View {

## Views/Library/LibraryViews.swift
- Line 3:extension ContentView {
- Line 124:    func libraryCaptureRow(_ item: CaptureLibraryItem) -> some View {
- Line 254:    func libraryMetadataPill(text: String, systemName: String) -> some View {
- Line 270:    func matchesLibrarySearch(_ item: CaptureLibraryItem) -> Bool {
- Line 282:    func matchesLibraryCollectionFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 287:    func matchesLibraryProjectFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 292:    func matchesLibraryTypeFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 377:    func buildLibraryFilterOptions(
- Line 387:    func libraryFilterSection(
- Line 472:    func activeLibraryFilterChip(title: String, removeAction: @escaping () -> Void) -> some View {
- Line 496:    func toggleLibraryCollectionFilter(_ collectionName: String) {
- Line 508:    func toggleLibraryProjectFilter(_ projectName: String) {
- Line 516:    func toggleLibraryTypeFilter(_ type: CaptureType) {
- Line 520:    func clearLibraryFilters() {

## Views/Review/CaptureInfoInspectorViews.swift
- Line 3:extension ContentView {
- Line 4:    func captureInfoInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 145:    func syncCaptureInfoDrafts(from summary: RecordingInspectionSummary, force: Bool = false) {
- Line 201:    func autocompleteSuggestions(from values: [String], matching query: String) -> [String] {
- Line 222:    func selectCollectionSuggestion(_ suggestion: String) {
- Line 228:    func selectProjectSuggestion(_ suggestion: String) {
- Line 234:    func autocompleteSuggestionPanel(
- Line 271:    func captureTypeChips(selectedType: CaptureType) -> some View {

## Views/Review/EffectsEditorViews.swift
- Line 4:func compactTimelineLaneCenterY(for lane: Int, verticalOrigin: CGFloat) -> CGFloat {
- Line 10:func effectTimelineSegmentLayouts(
- Line 95:struct EffectTimelineSegmentLayout: Identifiable {
- Line 107:struct EffectTimelineSegmentView: View {
- Line 211:struct EffectsTimelineTrackView: View {
- Line 350:struct EffectListEntry: Identifiable {
- Line 359:struct EffectListTableView: NSViewRepresentable {
- Line 371:    func makeCoordinator() -> Coordinator {
- Line 375:    func makeNSView(context: Context) -> NSScrollView {
- Line 414:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 436:        func handleTableViewAction(_ sender: Any?) {
- Line 446:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 450:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 454:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 480:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 493:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 502:        func tableView(
- Line 512:        func tableView(
- Line 533:        func syncSelection() {
- Line 550:        func refreshTableIfNeeded() {
- Line 783:    func update(rootView: EffectListCellContent) {

## Views/Review/MarkerListTableViews.swift
- Line 5:struct MarkerListTableView: NSViewRepresentable {
- Line 18:    func makeCoordinator() -> Coordinator {
- Line 22:    func makeNSView(context: Context) -> NSScrollView {
- Line 61:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 84:        func handleTableViewAction(_ sender: Any?) {
- Line 94:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 98:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 102:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 109:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 122:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 131:        func tableView(
- Line 141:        func tableView(
- Line 162:        func syncSelection() {
- Line 179:        func refreshTableIfNeeded() {
- Line 207:        func refreshVisibleRows() {
- Line 437:    func update(rootView: MarkerListCellContent) {
- Line 455:    func validateDrop(info: DropInfo) -> Bool {
- Line 459:    func dropEntered(info: DropInfo) {
- Line 472:    func dropUpdated(info: DropInfo) -> DropProposal? {
- Line 479:    func performDrop(info: DropInfo) -> Bool {
- Line 502:    func dropExited(info: DropInfo) {

## Views/Review/RealtimeEffectPreviewSurface.swift
- Line 6:struct RealtimeEffectPreviewSurface: NSViewRepresentable {
- Line 14:    func makeCoordinator() -> Coordinator {
- Line 18:    func makeNSView(context: Context) -> MTKView {
- Line 22:    func updateNSView(_ nsView: MTKView, context: Context) {
- Line 65:        func makeView() -> MTKView {
- Line 78:        func update(
- Line 106:        func detach() {
- Line 118:        func draw(in view: MTKView) {
- Line 184:        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

## Views/Review/ReviewEditorControls.swift
- Line 3:enum ReviewEditorMode: String, CaseIterable, Identifiable {
- Line 10:struct ReviewEditorModeControlStrip: View {
- Line 65:struct EffectsPlaceholderControlStrip: View {
- Line 119:func segmentedPillTextColor(isSelected: Bool, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
- Line 123:func segmentedPillBackgroundColor(isSelected: Bool, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
- Line 127:func accentContrastingTextColor(theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
- Line 131:extension ReviewEditorMode {

## Views/Review/ReviewInspectorViews.swift
- Line 4:enum EditInspectorMode: String, CaseIterable, Identifiable {
- Line 12:struct InspectorSectionHeaderView: View {
- Line 29:struct EffectsInspectorPlaceholderView: View {
- Line 75:struct InspectorOverflowHintView: View {
- Line 119:struct ResizableInspectorSplitView<TopContent: View, BottomContent: View>: View {
- Line 182:    func makeCoordinator() -> Coordinator { Coordinator() }
- Line 184:    func makeNSView(context: Context) -> NSScrollView {
- Line 188:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 202:        func makeScrollView(rootView: AnyView) -> NSScrollView {
- Line 223:        func update(scrollView: NSScrollView, rootView: AnyView) {
- Line 286:    func update(rootView: AnyView) {
- Line 290:    func updateWidth(_ width: CGFloat) {
- Line 352:    func observeDocumentView(_ documentView: NSView?) {
- Line 398:    func updateOverflowHintVisibility(animated: Bool = true) {
- Line 517:    func makeCoordinator() -> Coordinator {
- Line 521:    func makeNSView(context: Context) -> InspectorSplitView {
- Line 531:    func updateNSView(_ nsView: InspectorSplitView, context: Context) {
- Line 557:        func makeSplitView(
- Line 591:        func update(
- Line 608:        func splitViewDidResizeSubviews(_ notification: Notification) {
- Line 634:        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
- Line 639:        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
- Line 720:struct ReviewInspectorCard<PrimaryContent: View, EffectsContent: View>: View {

## Views/Review/ReviewMarkerInspectorViews.swift
- Line 4:extension ContentView {
- Line 9:    func markerInspectorCard(_ summary: RecordingInspectionSummary) -> some View {
- Line 71:    func effectsInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 128:    func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 186:    func markerListRow(
- Line 318:    func markerListDragPreview(
- Line 682:    func supportsCreatorDefaults(_ style: EffectStyle) -> Bool {
- Line 691:    func markerDisplayNumber(for marker: ZoomPlanItem) -> Int {
- Line 699:    func timingSliderRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
- Line 734:    func pointTimingRow(
- Line 805:    func beginEffectHoldTimingEdit(_ holdPoint: ActiveEffectHoldPoint, _ phase: MarkerTimingPhase) {
- Line 813:    func endEffectHoldTimingEdit(_ holdPoint: ActiveEffectHoldPoint, _ phase: MarkerTimingPhase) {
- Line 821:    func seekPlaybackToActiveEffectHoldPoint(_ holdPoint: ActiveEffectHoldPoint) {
- Line 831:    func scheduleRealtimeEffectPreviewResume(for holdPoint: ActiveEffectHoldPoint) {
- Line 841:    func nudgeActiveEffectHoldPoint(by delta: Double) {
- Line 862:    func setSelectedEffectHoldStartTimeAndFollowPlayback(_ time: Double) {
- Line 871:    func setSelectedEffectHoldEndTimeAndFollowPlayback(_ time: Double) {
- Line 881:    func effectAmountEditorSection(for marker: EffectPlanItem) -> some View {
- Line 919:    func distortionEditorSection(for marker: EffectPlanItem) -> some View {
- Line 1005:    func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
- Line 1026:    func markerTypeSymbol(for zoomType: ZoomType) -> String {

## Views/Review/ReviewPlaybackMainViews.swift
- Line 4:extension ContentView {
- Line 5:    func playbackVideoCard(
- Line 698:    func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
- Line 1237:    func finishEffectFocusRegionDrawing(with region: EffectFocusRegion? = nil) {
- Line 1249:    func playbackInfoPopover(_ summary: RecordingInspectionSummary) -> some View {

## Views/Review/ReviewPlaybackPreviewViews.swift
- Line 6:extension ContentView {
- Line 7:    func playbackTransitionPlateOpacity(
- Line 20:    func playbackTransitionPlateAnimationDuration(
- Line 35:    func activeZoomPreviewState(
- Line 51:    func activeEffectPreviewState(
- Line 107:    func effectPreviewOverlay(
- Line 148:    func effectBlurLayer(
- Line 187:    func effectOutsideMask(
- Line 208:    func effectPreviewOverlayColor(for effectState: EffectPreviewState) -> Color {
- Line 225:    func color(for tintColor: EffectTintColor) -> Color {
- Line 235:    func transformedOverlayRect(
- Line 261:    func zoomPreviewOffset(for previewState: ZoomPreviewState?, in fittedRect: CGRect) -> CGSize {
- Line 274:    func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
- Line 279:    func overlayPoint(
- Line 305:    func sourcePoint(
- Line 331:    func noZoomOverflowRegion(
- Line 352:    func effectFocusRegion(
- Line 368:    func aspectLockedSourceRect(
- Line 397:    func freeformSourceRect(
- Line 426:    func effectFocusSourceRect(
- Line 438:    func effectFocusRegion(
- Line 450:    func overlayRect(
- Line 489:    func overlayRect(
- Line 523:    func overflowRegionCornerRadii(
- Line 544:    func nudgedNoZoomOverflowRegion(
- Line 571:    func nudgedEffectFocusRegion(
- Line 598:    func movedEffectFocusRegion(
- Line 607:    func effectRegionHandlePoint(for handle: EffectRegionHandle, in rect: CGRect) -> CGPoint {
- Line 628:    func resizedEffectFocusRegion(
- Line 714:    func fittedVideoRect(in containerSize: CGSize, aspectRatio: CGFloat) -> CGRect {
- Line 735:    func precisionLoupeFrame(
- Line 744:    func positionedPrecisionLoupe(
- Line 760:    func updateClickPointPrecisionLoupe(at point: CGPoint, fittedRect: CGRect) {
- Line 772:    func resetClickPointPrecisionLoupe() {
- Line 778:    func updateEffectRegionPrecisionLoupe(at point: CGPoint, fittedRect: CGRect) {
- Line 790:    func updateEffectRegionPrecisionLoupeOffset(for point: CGPoint, fittedRect: CGRect) {
- Line 801:    func resetEffectRegionPrecisionLoupe() {
- Line 808:    func preparePrecisionLoupeFrameIfNeeded() {
- Line 844:    func clearPrecisionLoupeFrame() {
- Line 915:    func effectRegionPrecisionLoupe(
- Line 1009:    func transformedOverlayPoint(

## Views/Review/ReviewSupportViews.swift
- Line 5:struct PlaybackVideoSurface: NSViewRepresentable {
- Line 8:    func makeNSView(context: Context) -> AVPlayerView {
- Line 16:    func updateNSView(_ nsView: AVPlayerView, context: Context) {
- Line 25:struct PlaybackVideoLayerSurface: NSViewRepresentable {
- Line 28:    func makeNSView(context: Context) -> PlayerLayerHostView {
- Line 34:    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
- Line 64:struct PrecisionTimeField: NSViewRepresentable {
- Line 71:    func makeCoordinator() -> Coordinator {
- Line 75:    func makeNSView(context: Context) -> NSTextField {
- Line 89:    func updateNSView(_ nsView: NSTextField, context: Context) {
- Line 122:        func controlTextDidBeginEditing(_ obj: Notification) {
- Line 130:        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
- Line 146:        func controlTextDidEndEditing(_ obj: Notification) {
- Line 168:        func displayString(for value: Double) -> String {

## Views/Review/ReviewTimelineInteractionViews.swift
- Line 77:    func path(in rect: CGRect) -> Path {
- Line 93:extension ContentView {
- Line 95:    func timelineToolbar(
- Line 126:    func timelineCanvasView(
- Line 281:    func smartSetupTimelineHighlight(
- Line 304:    func timelineRulerView(
- Line 336:    func timelinePlayheadView(
- Line 386:    func timelineInstructionText(
- Line 400:    func timelineInstructionView(
- Line 416:    func timelineFooterView(

## Views/Review/ReviewTimelineViews.swift
- Line 4:struct TimelineRulerTick: Identifiable {
- Line 14:struct TimelineVisibleRange: Equatable {
- Line 34:    func contains(_ time: Double) -> Bool {
- Line 38:    func ratio(for time: Double) -> Double {
- Line 42:    func clampedRatio(for time: Double) -> Double {
- Line 46:    func clippedRange(start: Double, end: Double) -> (start: Double, end: Double)? {
- Line 58:extension ContentView {
- Line 59:    func playbackTransportControls() -> some View {
- Line 85:    func playbackTransportBar(_ summary: RecordingInspectionSummary) -> some View {
- Line 93:    func referenceTimelineSegment(
- Line 115:    func timelineLane(for startRatio: Double, endRatio: Double, laneEndRatios: inout [Double]) -> Int {
- Line 133:    func timelineVisibleRange(for duration: Double) -> TimelineVisibleRange {
- Line 143:    func timelineMaximumZoomScale(for duration: Double) -> Double {
- Line 154:    func clampedTimelineZoomScale(_ zoomScale: Double, duration: Double) -> Double {
- Line 158:    func clampedTimelineStartTime(_ startTime: Double, visibleDuration: Double, fullDuration: Double) -> Double {
- Line 163:    func zoomTimelineVisibleRange(
- Line 195:    func panTimelineVisibleRange(
- Line 218:    func timelineTime(for x: CGFloat, width: CGFloat, visibleRange: TimelineVisibleRange) -> Double {
- Line 223:    func timelineX(for time: Double, visibleRange: TimelineVisibleRange, width: CGFloat) -> CGFloat {
- Line 227:    func timelineRulerTicks(visibleRange: TimelineVisibleRange, width: CGFloat) -> [TimelineRulerTick] {
- Line 288:    func zoomTimelineMarkerHitTarget(
- Line 316:    func timelineSnapTarget(
- Line 337:    func effectTimelineSnapTarget(
- Line 358:    func effectTimelineHitTarget(
- Line 385:struct TimelineTrackpadGestureCaptureView: NSViewRepresentable {
- Line 389:    func makeCoordinator() -> Coordinator {
- Line 393:    func makeNSView(context: Context) -> NSView {
- Line 399:    func updateNSView(_ nsView: NSView, context: Context) {
- Line 415:        func installMonitor(for view: NSView) {
- Line 441:        func removeMonitor() {

## Views/Review/SmartSetupViews.swift
- Line 3:struct SmartSetupReviewPanel: View {
- Line 349:    func debugVisibleIdentity(

## Views/Review/TimelineToolbarControls.swift
- Line 3:struct TimelineToolbarView: View {
- Line 128:struct EffectsTimelineToolbarView: View {
- Line 237:struct TimelineGadgetButton: View {

## Views/Review/ZoomAndClicksEditorViews.swift
- Line 4:enum MarkerTimingPhase: String {
- Line 11:struct TimelineSegmentLayout: Identifiable {
- Line 22:func timelineSegmentLayouts(
- Line 71:func timelineSegment(
- Line 221:func timelineMarkerTooltipOverlay(

## Views/Settings/SettingsViews.swift
- Line 3:extension ContentView {
- Line 86:    func settingsCard(title: String, body: AnyView) -> some View {
- Line 239:    func distortionMapSourceSummary(for descriptor: DistortionPresetDescriptor) -> String {
- Line 249:    func distortionImportedMapDetails(for descriptor: DistortionPresetDescriptor) -> DistortionImportedMapAsset? {

## Views/Shared/ExportProgressSheetViews.swift
- Line 4:extension ContentView {
- Line 87:    func presentExportSharePicker() {

## Views/Shared/FlowTrackAccent.swift
- Line 3:enum FlowTrackAccentRole {
- Line 11:enum FlowTrackAccent {

## Views/Shared/FlowTrackColourLabViews.swift
- Line 4:struct FlowTrackColourLabView: View {
- Line 504:    enum Mode {
- Line 673:    func color(in theme: FlowTrackTheme) -> Color {
- Line 677:    func setColor(_ color: Color, in theme: inout FlowTrackTheme) {
- Line 863:    func makeCoordinator() -> Coordinator {
- Line 867:    func makeNSView(context: Context) -> ShortcutMonitorView {
- Line 876:    func updateNSView(_ nsView: ShortcutMonitorView, context: Context) {
- Line 902:        func installMonitor(for view: NSView) {
- Line 944:struct FlowTrackColourLabPanelPresenter: NSViewRepresentable {
- Line 953:    func makeCoordinator() -> Coordinator {
- Line 957:    func makeNSView(context: Context) -> NSView {
- Line 961:    func updateNSView(_ nsView: NSView, context: Context) {
- Line 978:        func update(
- Line 1045:        func windowWillClose(_ notification: Notification) {
- Line 1051:struct FlowTrackColourLabShortcutView: NSViewRepresentable {
- Line 1054:    func makeCoordinator() -> Coordinator {
- Line 1058:    func makeNSView(context: Context) -> ShortcutMonitorView {
- Line 1067:    func updateNSView(_ nsView: ShortcutMonitorView, context: Context) {
- Line 1087:        func installMonitor(for view: NSView) {

## Views/Shared/FlowTrackOnboardingViews.swift
- Line 3:struct FlowTrackOnboardingCoachCard: View {
- Line 253:struct FlowTrackOnboardingRegionHighlight: View {
- Line 277:    enum Kind {
- Line 285:    func makeBody(configuration: Configuration) -> some View {

## Views/Shared/FlowTrackTheme.swift
- Line 6:struct FlowTrackBuiltInTheme: Identifiable, Equatable {
- Line 16:enum FlowTrackThemeTextScheme: String, Codable, CaseIterable {
- Line 33:struct FlowTrackTheme: Codable {
- Line 65:    func timelineRailColor(for colorScheme: ColorScheme) -> Color {
- Line 69:    func accentColor(for role: FlowTrackAccentRole) -> Color {
- Line 84:    enum CodingKeys: String, CodingKey {
- Line 217:    func encode(to encoder: Encoder) throws {
- Line 252:struct FlowTrackCodableColor: Codable {
- Line 278:struct FlowTrackSavedTheme: Codable, Identifiable, Equatable {
- Line 293:struct FlowTrackThemeLibrary: Codable {
- Line 299:    enum CodingKeys: String, CodingKey {
- Line 327:struct FlowTrackThemeActions {
- Line 337:enum FlowTrackThemeDefaults {
- Line 556:extension EnvironmentValues {

## Views/Shared/HelpModeViews.swift
- Line 3:enum HelpTopic {
- Line 133:struct HelpModeHintView: View {
- Line 222:struct HelpModeRegionHighlight: View {

## Views/Shared/TimecodeFormatting.swift
- Line 3:extension ContentView {
- Line 4:    func timecodeString(since start: Date, now: Date) -> String {
- Line 14:    func timecodeString(for seconds: Double) -> String {

