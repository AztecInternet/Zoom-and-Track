# Swift Symbols

Generated: 2026-05-15 03:58:08

## App/ContentView.swift

- Line 12:struct ContentView: View {
- Line 73:    struct OverlayMapping {
- Line 82:    struct ZoomPreviewState {
- Line 87:    struct EffectPreviewState {
- Line 98:    struct PrecisionLoupeFrame {
- Line 103:    enum EffectRegionHandle: Hashable {
- Line 114:    enum ActiveEffectHoldPoint {
- Line 119:    struct ZoomStateEvent {
- Line 125:    enum MotionDirection {
- Line 130:    struct MotionProgressSample {
- Line 172:    enum CaptureInfoField: Hashable {
- Line 178:    enum MotionTuning {
- Line 186:    struct LibraryFilterOption: Identifiable {
- Line 471:    func effectTintColorBinding(for marker: EffectPlanItem) -> Binding<Color> {
- Line 491:    func mappedOverlayPoint(
- Line 530:    func infoRow(title: String, value: String) -> some View {
- Line 541:    func metadataItem(_ title: String, _ value: String, multiline: Bool = false) -> some View {
- Line 585:    func reviewHeaderActionIcon(_ systemName: String, action: ReviewHeaderAction) -> some View {
- Line 600:    func sectionHeader(title: String, subtitle: String, accentWidth: CGFloat) -> some View {
- Line 613:    func setTimelineHover(markerID: String, phase: MarkerTimingPhase?, anchor: CGPoint) {
- Line 620:    func clearTimelineHover() {
- Line 629:    func setEffectTimelineHover(markerID: String, anchor: CGPoint) {
- Line 634:    func clearEffectTimelineHover() {
- Line 639:    func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
- Line 649:    func hoveredEffectTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: EffectPlanItem, markerNumber: Int)? {
- Line 658:    func displayedTimelinePhase(for marker: ZoomPlanItem) -> MarkerTimingPhase? {
- Line 673:    func isMarkerPlaybackHighlighted(_ marker: ZoomPlanItem) -> Bool {
- Line 685:    func isEffectPlaybackHighlighted(_ marker: EffectPlanItem) -> Bool {
- Line 689:    func displayedMarkerList(_ markers: [ZoomPlanItem], previewOrder: [String]? = nil) -> [ZoomPlanItem] {
- Line 710:    func displayedEffectMarkerList(_ markers: [EffectPlanItem]) -> [EffectPlanItem] {
- Line 782:struct SharingAnchorView: NSViewRepresentable {
- Line 785:    func makeNSView(context: Context) -> NSView {
- Line 793:    func updateNSView(_ nsView: NSView, context: Context) {
- Line 804:enum ReviewHeaderAction {
- Line 810:enum AppTab: String, CaseIterable, Identifiable {
- Line 845:struct MarkerListEntry: Identifiable {

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
- Line 964:struct EffectPlanItem: Codable, Identifiable, Equatable {
- Line 1089:    func encode(to encoder: Encoder) throws {
- Line 1142:enum ZoomMarkerKind: String, Codable {
- Line 1146:enum ClickPulsePreset: String, Codable, CaseIterable, Identifiable {
- Line 1171:struct ClickPulseConfiguration: Codable, Equatable {
- Line 1192:struct ZoomPlanItem: Codable, Identifiable {
- Line 1401:struct RecordingInspectionSummary {
- Line 1494:enum SharedMotionEngine {
- Line 1495:    enum CoordinateSpace {
- Line 1500:    struct PreviewState {
- Line 1505:    struct ClickPulseRenderState {
- Line 1510:    struct OverlayGeometryResolution {
- Line 1516:    struct Timeline {

## Services/CreatorEffectDefaultsService.swift

- Line 8:struct CreatorEffectDefaultsService {
- Line 15:    func loadCreatorEffectDefaults() -> CreatorEffectDefaults {
- Line 32:    func saveCreatorEffectDefaults(_ defaults: CreatorEffectDefaults) throws {

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
- Line 344:    func persistLastRecordingBundle(_ url: URL) -> Bool {
- Line 352:    func resolveLastRecordingBundle() -> RecordingBundleResolution {
- Line 374:    func beginPlaybackAccess(for bundleURL: URL) throws -> URL? {
- Line 394:    func endPlaybackAccess(_ url: URL?) {
- Line 398:    func saveZoomPlan(_ zoomPlan: ZoomPlanEnvelope, in bundleURL: URL) throws {
- Line 409:    func updateCaptureMetadata(
- Line 446:    func libraryRootURL() throws -> URL {
- Line 453:    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
- Line 485:    func registerCaptureInLibrary(_ summary: RecordingInspectionSummary) throws {

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

## ViewModels/CaptureSetupViewModel.swift

- Line 13:    enum PlaybackPresentationMode {
- Line 20:    enum PlaybackTransitionPlateState {
- Line 27:    enum ExportState: Equatable {
- Line 302:    func load() async {
- Line 324:    func activateCaptureTarget(_ target: ShareableCaptureTarget) {
- Line 342:    func requestPermission() async {
- Line 348:    func startRecording() async {
- Line 378:    func stopRecording() async {
- Line 387:    func revealInFinder() {
- Line 392:    func chooseOutputFolder() {
- Line 398:    func selectDistortionPresetLibraryPreset(_ presetID: String) {
- Line 402:    func createDistortionPresetFromImportedMap() {
- Line 437:    func duplicateSelectedDistortionPreset() {
- Line 456:    func deleteSelectedDistortionPreset() {
- Line 466:    func renameSelectedDistortionPreset(_ name: String) {
- Line 477:    func setSelectedDistortionLibraryPresetEnginePreset(_ preset: DistortionPreset) {
- Line 486:    func setSelectedDistortionLibraryPresetMapSource(_ mapSource: DistortionMapSource) {
- Line 492:    func setSelectedDistortionLibraryPresetDefaultAmount(_ amount: Double) {
- Line 498:    func setSelectedDistortionLibraryPresetDefaultScale(_ scale: Double) {
- Line 504:    func setSelectedDistortionLibraryPresetDefaultBackgroundBlend(_ blend: Double) {
- Line 510:    func setSelectedDistortionLibraryPresetDefaultBackgroundBlur(_ blur: Double) {
- Line 516:    func openRecording() {
- Line 521:    func exportRecording() {
- Line 572:    func cancelExport() {
- Line 578:    func dismissExportSheet() {
- Line 623:    func revealExportInFinder() {
- Line 628:    func openLibraryCapture(_ item: CaptureLibraryItem) {
- Line 641:    func revealLibraryCapture(_ item: CaptureLibraryItem) {
- Line 650:    func startMarkerPreview(_ markerID: String) {
- Line 754:    func togglePlayback() {
- Line 786:    func seekPlaybackInteractively(to seconds: Double) {
- Line 810:    func jumpPlaybackToStart() {
- Line 833:    func cancelPlaybackPreview() {
- Line 851:    func beginTimelineScrub() {
- Line 882:    func updateTimelineScrub(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 895:    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 915:    func seekTimelineDirectly(
- Line 954:    func nudgeSelectedTimelineMarker(by delta: Double) {
- Line 976:    func nudgeSelectedEffectTimelineMarker(by delta: Double) {
- Line 1012:    func setSelectedMarkerEnabled(_ enabled: Bool) {
- Line 1018:    func setMarkerEnabled(_ enabled: Bool, for markerID: String) {
- Line 1024:    func toggleMarkerEnabled(_ markerID: String) {
- Line 1030:    func setMarkerName(_ markerName: String?, for markerID: String) {
- Line 1037:    func setSelectedMarkerZoomScale(_ zoomScale: Double) {
- Line 1043:    func setSelectedMarkerLeadInTime(_ leadInTime: Double) {
- Line 1050:    func setSelectedMarkerZoomInDuration(_ zoomInDuration: Double) {
- Line 1057:    func setSelectedMarkerHoldDuration(_ holdDuration: Double) {
- Line 1064:    func setSelectedMarkerZoomOutDuration(_ zoomOutDuration: Double) {
- Line 1071:    func setSelectedMarkerEaseStyle(_ easeStyle: ZoomEaseStyle) {
- Line 1077:    func setSelectedMarkerZoomType(_ zoomType: ZoomType) {
- Line 1087:    func setSelectedMarkerBounceAmount(_ bounceAmount: Double) {
- Line 1093:    func setSelectedMarkerNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 1099:    func setSelectedMarkerNoZoomOverflowRegion(_ region: NoZoomOverflowRegion?) {
- Line 1105:    func clearSelectedMarkerNoZoomOverflowRegion() {
- Line 1109:    func setSelectedEffectFocusRegion(_ region: EffectFocusRegion?) {
- Line 1121:    func clearSelectedEffectFocusRegion() {
- Line 1125:    func selectEffectMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 1147:    func selectZoomMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 1166:    func previewEffectMarker(_ markerID: String) {
- Line 1189:    func startEffectMarkerPreview(_ markerID: String) {
- Line 1295:    func setSelectedEffectMarkerEnabled(_ enabled: Bool) {
- Line 1301:    func toggleEffectMarkerEnabled(_ markerID: String) {
- Line 1307:    func setEffectMarkerName(_ markerName: String?, for markerID: String) {
- Line 1314:    func setSelectedEffectStyle(_ style: EffectStyle) {
- Line 1330:    func setSelectedEffectAmount(_ amount: Double) {
- Line 1336:    func setDistortionLoupePoint(_ point: CGPoint) {
- Line 1344:    func resetDistortionLoupePointToDefault() {
- Line 1349:    func setSelectedEffectDistortionPreset(_ preset: DistortionPreset) {
- Line 1356:    func setSelectedEffectDistortionPresetSelectionID(_ presetID: String) {
- Line 1363:    func setSelectedEffectDistortionScale(_ scale: Double) {
- Line 1372:    func setSelectedEffectDistortionBackgroundBlend(_ blend: Double) {
- Line 1381:    func setSelectedEffectDistortionBackgroundBlur(_ blur: Double) {
- Line 1390:    func setSelectedEffectDistortionColorGlowStrength(_ strength: Double) {
- Line 1399:    func setSelectedEffectDistortionColorGlowRadius(_ radius: Double) {
- Line 1408:    func setSelectedEffectDistortionColorAnimationIntensity(_ intensity: Double) {
- Line 1417:    func setSelectedEffectDistortionColorCoreOpacity(_ opacity: Double) {
- Line 1426:    func setSelectedEffectDistortionColorEffectPalette(_ palette: DistortionColorEffectPalette) {
- Line 1435:    func saveSelectedDistortionAsCreatorDefault() {
- Line 1439:    func applyCreatorDistortionDefaultsToSelectedEffect() {
- Line 1443:    func saveCurrentEffectStyleAsCreatorDefault() {
- Line 1472:    func applyCreatorDefaultsToSelectedEffectStyle() {
- Line 1499:    func setSelectedEffectBlurAmount(_ amount: Double) {
- Line 1509:    func setSelectedEffectDarkenAmount(_ amount: Double) {
- Line 1519:    func setSelectedEffectTintAmount(_ amount: Double) {
- Line 1529:    func setSelectedEffectFadeInDuration(_ duration: Double) {
- Line 1535:    func setSelectedEffectFadeOutDuration(_ duration: Double) {
- Line 1541:    func setSelectedEffectHoldStartTime(_ time: Double) {
- Line 1552:    func setSelectedEffectHoldEndTime(_ time: Double) {
- Line 1563:    func setSelectedEffectHoldDuration(_ duration: Double) {
- Line 1569:    func setSelectedEffectCornerRadius(_ radius: Double) {
- Line 1575:    func setSelectedEffectFeather(_ feather: Double) {
- Line 1581:    func setSelectedEffectTintColor(_ tintColor: EffectTintColor) {
- Line 1587:    func addEffectMarker(at timestamp: Double? = nil) {
- Line 1624:    func deleteSelectedEffectMarker() {
- Line 1633:    func reorderEffectMarkerList(to orderedMarkerIDs: [String]) {
- Line 1653:    func setDefaultNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 1658:    func setSelectedMarkerClickPulseEnabled(_ enabled: Bool) {
- Line 1669:    func setSelectedMarkerClickPulsePreset(_ preset: ClickPulsePreset) {
- Line 1680:    func setCurrentCaptureTitle(_ title: String) {
- Line 1685:    func setCurrentCaptureCollectionName(_ collectionName: String) {
- Line 1690:    func setCurrentCaptureProjectName(_ projectName: String) {
- Line 1695:    func setCurrentCaptureType(_ captureType: CaptureType) {
- Line 1700:    func setCompositionAspectRatio(_ aspectRatio: OutputAspectRatio) {
- Line 1709:    func setCompositionSourceScale(_ scale: Double) {
- Line 1718:    func setCompositionSourceOffset(x: Double, y: Double) {
- Line 1727:    func resetCompositionSourceTransform() {
- Line 1731:    func resetCompositionLayout() {
- Line 1735:    func deleteSelectedMarker() {
- Line 1743:    func duplicateSelectedMarker() {
- Line 1754:    func addClickFocusMarker(at sourcePoint: CGPoint, timestamp: Double? = nil) {
- Line 1805:    func reorderMarkerList(to orderedMarkerIDs: [String]) {
- Line 1824:    func moveSelectedMarker(to sourcePoint: CGPoint) {
- Line 1951:    func refreshLibrary() async {
- Line 2025:    func distortionPresetSelectionID(for marker: EffectPlanItem) -> String {
- Line 2066:    func toggleDistortionMapOverlay() {
- Line 2074:    func hideDistortionMapOverlay() {
- Line 2404:    func scheduleDistortionLoupeRefresh() {
- Line 2412:    func defaultDistortionLoupeNormalizedPoint(for marker: EffectPlanItem) -> CGPoint {

## Views/Capture/CaptureSetupViews.swift

- Line 3:extension ContentView {
- Line 222:    func nudgeCompositionOffset(x xDelta: Double, y yDelta: Double) {
- Line 394:    func targetSection(title: String, targets: [ShareableCaptureTarget]) -> some View {
- Line 412:    func targetRow(_ target: ShareableCaptureTarget) -> some View {

## Views/Library/LibraryViews.swift

- Line 3:extension ContentView {
- Line 113:    func libraryCaptureRow(_ item: CaptureLibraryItem) -> some View {
- Line 243:    func libraryMetadataPill(text: String, systemName: String) -> some View {
- Line 259:    func matchesLibrarySearch(_ item: CaptureLibraryItem) -> Bool {
- Line 271:    func matchesLibraryCollectionFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 276:    func matchesLibraryProjectFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 281:    func matchesLibraryTypeFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 355:    func buildLibraryFilterOptions(
- Line 365:    func libraryFilterSection(
- Line 450:    func activeLibraryFilterChip(title: String, removeAction: @escaping () -> Void) -> some View {
- Line 474:    func toggleLibraryCollectionFilter(_ collectionName: String) {
- Line 486:    func toggleLibraryProjectFilter(_ projectName: String) {
- Line 494:    func toggleLibraryTypeFilter(_ type: CaptureType) {
- Line 498:    func clearLibraryFilters() {

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

- Line 4:func effectTimelineSegmentLayouts(for markers: [EffectPlanItem], duration: Double) -> [EffectTimelineSegmentLayout] {
- Line 82:struct EffectTimelineSegmentLayout: Identifiable {
- Line 94:struct EffectTimelineSegmentView: View {
- Line 197:struct EffectsTimelineTrackView: View {
- Line 336:struct EffectListEntry: Identifiable {
- Line 345:struct EffectListTableView: NSViewRepresentable {
- Line 357:    func makeCoordinator() -> Coordinator {
- Line 361:    func makeNSView(context: Context) -> NSScrollView {
- Line 400:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 422:        func handleTableViewAction(_ sender: Any?) {
- Line 432:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 436:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 440:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 466:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 479:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 488:        func tableView(
- Line 498:        func tableView(
- Line 519:        func syncSelection() {
- Line 536:        func refreshTableIfNeeded() {
- Line 769:    func update(rootView: EffectListCellContent) {

## Views/Review/MarkerListTableViews.swift

- Line 5:struct MarkerListTableView: NSViewRepresentable {
- Line 17:    func makeCoordinator() -> Coordinator {
- Line 21:    func makeNSView(context: Context) -> NSScrollView {
- Line 60:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 82:        func handleTableViewAction(_ sender: Any?) {
- Line 92:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 96:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 100:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 126:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 139:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 148:        func tableView(
- Line 158:        func tableView(
- Line 179:        func syncSelection() {
- Line 196:        func refreshTableIfNeeded() {
- Line 423:    func update(rootView: MarkerListCellContent) {
- Line 441:    func validateDrop(info: DropInfo) -> Bool {
- Line 445:    func dropEntered(info: DropInfo) {
- Line 458:    func dropUpdated(info: DropInfo) -> DropProposal? {
- Line 465:    func performDrop(info: DropInfo) -> Bool {
- Line 488:    func dropExited(info: DropInfo) {

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
- Line 63:struct EffectsPlaceholderControlStrip: View {
- Line 115:func segmentedPillTextColor(isSelected: Bool) -> Color {
- Line 119:func segmentedPillBackgroundColor(isSelected: Bool) -> Color {
- Line 123:func accentContrastingTextColor() -> Color {
- Line 129:extension ReviewEditorMode {

## Views/Review/ReviewInspectorViews.swift

- Line 4:enum EditInspectorMode: String, CaseIterable, Identifiable {
- Line 11:struct InspectorSectionHeaderView: View {
- Line 28:struct EffectsInspectorPlaceholderView: View {
- Line 74:struct InspectorOverflowHintView: View {
- Line 110:struct ResizableInspectorSplitView<TopContent: View, BottomContent: View>: View {
- Line 155:    func makeCoordinator() -> Coordinator { Coordinator() }
- Line 157:    func makeNSView(context: Context) -> NSScrollView {
- Line 161:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 175:        func makeScrollView(rootView: AnyView) -> NSScrollView {
- Line 196:        func update(scrollView: NSScrollView, rootView: AnyView) {
- Line 259:    func update(rootView: AnyView) {
- Line 263:    func updateWidth(_ width: CGFloat) {
- Line 325:    func observeDocumentView(_ documentView: NSView?) {
- Line 371:    func updateOverflowHintVisibility(animated: Bool = true) {
- Line 487:    func makeCoordinator() -> Coordinator {
- Line 491:    func makeNSView(context: Context) -> InspectorSplitView {
- Line 500:    func updateNSView(_ nsView: InspectorSplitView, context: Context) {
- Line 524:        func makeSplitView(
- Line 556:        func update(
- Line 571:        func splitViewDidResizeSubviews(_ notification: Notification) {
- Line 597:        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
- Line 601:        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
- Line 673:struct ReviewInspectorCard<PrimaryContent: View, EffectsContent: View>: View {

## Views/Review/ReviewMarkerInspectorViews.swift

- Line 4:extension ContentView {
- Line 9:    func markerInspectorCard(_ summary: RecordingInspectionSummary) -> some View {
- Line 49:    func effectsInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 107:    func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 165:    func markerListRow(
- Line 297:    func markerListDragPreview(
- Line 661:    func supportsCreatorDefaults(_ style: EffectStyle) -> Bool {
- Line 670:    func markerDisplayNumber(for marker: ZoomPlanItem) -> Int {
- Line 678:    func timingSliderRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
- Line 713:    func pointTimingRow(
- Line 784:    func beginEffectHoldTimingEdit(_ holdPoint: ActiveEffectHoldPoint, _ phase: MarkerTimingPhase) {
- Line 792:    func endEffectHoldTimingEdit(_ holdPoint: ActiveEffectHoldPoint, _ phase: MarkerTimingPhase) {
- Line 800:    func seekPlaybackToActiveEffectHoldPoint(_ holdPoint: ActiveEffectHoldPoint) {
- Line 810:    func scheduleRealtimeEffectPreviewResume(for holdPoint: ActiveEffectHoldPoint) {
- Line 820:    func nudgeActiveEffectHoldPoint(by delta: Double) {
- Line 841:    func setSelectedEffectHoldStartTimeAndFollowPlayback(_ time: Double) {
- Line 850:    func setSelectedEffectHoldEndTimeAndFollowPlayback(_ time: Double) {
- Line 860:    func effectAmountEditorSection(for marker: EffectPlanItem) -> some View {
- Line 898:    func distortionEditorSection(for marker: EffectPlanItem) -> some View {
- Line 984:    func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
- Line 1005:    func markerTypeSymbol(for zoomType: ZoomType) -> String {

## Views/Review/ReviewPlaybackMainViews.swift

- Line 4:extension ContentView {
- Line 5:    func playbackVideoCard(
- Line 685:    func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
- Line 1079:    func finishEffectFocusRegionDrawing(with region: EffectFocusRegion? = nil) {
- Line 1091:    func playbackInfoPopover(_ summary: RecordingInspectionSummary) -> some View {

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

- Line 3:extension ContentView {
- Line 5:    func timelineToolbar(
- Line 32:    func timelineCanvasView(
- Line 167:    func timelinePlayheadView(
- Line 200:    func timelineFooterView(

## Views/Review/ReviewTimelineViews.swift

- Line 3:extension ContentView {
- Line 4:    func playbackTransportBar(_ summary: RecordingInspectionSummary) -> some View {
- Line 35:    func referenceTimelineSegment(
- Line 67:    func timelineLane(for startRatio: Double, endRatio: Double, laneEndRatios: inout [Double]) -> Int {
- Line 85:    func timelineTime(for x: CGFloat, width: CGFloat, duration: Double) -> Double {
- Line 90:    func timelineX(for time: Double, duration: Double, width: CGFloat) -> CGFloat {
- Line 96:    func timelineSnapTarget(
- Line 116:    func effectTimelineSnapTarget(
- Line 136:    func effectTimelineHitTarget(

## Views/Review/TimelineToolbarControls.swift

- Line 3:struct TimelineToolbarView: View {
- Line 109:struct EffectsTimelineToolbarView: View {
- Line 199:struct TimelineGadgetButton: View {

## Views/Review/ZoomAndClicksEditorViews.swift

- Line 4:enum MarkerTimingPhase: String {
- Line 11:struct TimelineSegmentLayout: Identifiable {
- Line 22:func timelineSegmentLayouts(for markers: [ZoomPlanItem], duration: Double) -> [TimelineSegmentLayout] {
- Line 64:func timelineSegment(
- Line 211:func timelineMarkerTooltipOverlay(

## Views/Settings/SettingsViews.swift

- Line 3:extension ContentView {
- Line 81:    func settingsCard(title: String, body: AnyView) -> some View {
- Line 201:    func distortionMapSourceSummary(for descriptor: DistortionPresetDescriptor) -> String {
- Line 211:    func distortionImportedMapDetails(for descriptor: DistortionPresetDescriptor) -> DistortionImportedMapAsset? {

## Views/Shared/ExportProgressSheetViews.swift

- Line 4:extension ContentView {
- Line 87:    func presentExportSharePicker() {

## Views/Shared/FlowTrackAccent.swift

- Line 3:enum FlowTrackAccentRole {
- Line 11:enum FlowTrackAccent {

## Views/Shared/TimecodeFormatting.swift

- Line 3:extension ContentView {
- Line 4:    func timecodeString(since start: Date, now: Date) -> String {
- Line 14:    func timecodeString(for seconds: Double) -> String {

