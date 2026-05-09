# Swift Symbols

Generated: 2026-05-09 06:35:09

## App/ContentView.swift

- Line 12:struct ContentView: View {
- Line 61:    struct OverlayMapping {
- Line 70:    struct ZoomPreviewState {
- Line 75:    struct EffectPreviewState {
- Line 86:    enum EffectRegionHandle: Hashable {
- Line 97:    struct ZoomStateEvent {
- Line 103:    enum MotionDirection {
- Line 108:    struct MotionProgressSample {
- Line 150:    enum CaptureInfoField: Hashable {
- Line 156:    enum MotionTuning {
- Line 164:    struct LibraryFilterOption: Identifiable {
- Line 426:    func effectTintColorBinding(for marker: EffectPlanItem) -> Binding<Color> {
- Line 446:    func mappedOverlayPoint(
- Line 485:    func infoRow(title: String, value: String) -> some View {
- Line 496:    func metadataItem(_ title: String, _ value: String, multiline: Bool = false) -> some View {
- Line 535:    func sectionHeader(title: String, subtitle: String, accentWidth: CGFloat) -> some View {
- Line 551:    func setTimelineHover(markerID: String, phase: MarkerTimingPhase?, anchor: CGPoint) {
- Line 558:    func clearTimelineHover() {
- Line 567:    func setEffectTimelineHover(markerID: String, anchor: CGPoint) {
- Line 572:    func clearEffectTimelineHover() {
- Line 577:    func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
- Line 587:    func hoveredEffectTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: EffectPlanItem, markerNumber: Int)? {
- Line 596:    func displayedTimelinePhase(for marker: ZoomPlanItem) -> MarkerTimingPhase? {
- Line 611:    func isMarkerPlaybackHighlighted(_ marker: ZoomPlanItem) -> Bool {
- Line 623:    func isEffectPlaybackHighlighted(_ marker: EffectPlanItem) -> Bool {
- Line 627:    func displayedMarkerList(_ markers: [ZoomPlanItem], previewOrder: [String]? = nil) -> [ZoomPlanItem] {
- Line 648:    func displayedEffectMarkerList(_ markers: [EffectPlanItem]) -> [EffectPlanItem] {
- Line 720:struct SharingAnchorView: NSViewRepresentable {
- Line 723:    func makeNSView(context: Context) -> NSView {
- Line 731:    func updateNSView(_ nsView: NSView, context: Context) {
- Line 742:enum AppTab: String, CaseIterable, Identifiable {
- Line 764:struct MarkerListEntry: Identifiable {

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
- Line 66:struct ProjectManifest: Codable {
- Line 136:    func encode(to encoder: Encoder) throws {
- Line 152:struct CaptureMetadata: Equatable {
- Line 174:enum CaptureType: String, Codable, CaseIterable, Identifiable {
- Line 205:struct CaptureLibraryItem: Codable, Identifiable, Equatable {
- Line 289:enum CaptureLibraryItemStatus: String, Codable {
- Line 315:struct CaptureLibraryIndex: Codable {
- Line 320:struct CaptureLibrarySnapshot {
- Line 325:struct RecordingWorkspace {
- Line 333:enum RecordedEventType: String, Codable {
- Line 341:struct RecordedEvent: Codable {
- Line 348:struct RecordedEventEnvelope: Codable {
- Line 354:struct ZoomPlanEnvelope: Codable {
- Line 383:enum ZoomEaseStyle: String, Codable, CaseIterable, Identifiable {
- Line 408:enum ZoomType: String, Codable, CaseIterable, Identifiable {
- Line 430:enum NoZoomFallbackMode: String, Codable, CaseIterable, Identifiable {
- Line 446:struct NoZoomOverflowRegion: Codable, Equatable {
- Line 453:enum EffectStyle: String, Codable, CaseIterable, Identifiable {
- Line 485:enum DistortionPreset: String, Codable, CaseIterable, Identifiable {
- Line 501:enum DistortionMapSource: Codable, Equatable {
- Line 527:    func encode(to encoder: Encoder) throws {
- Line 540:struct DistortionConfiguration: Codable, Equatable {
- Line 564:struct EffectFocusRegion: Codable, Equatable {
- Line 571:struct EffectTintColor: Codable, Equatable {
- Line 580:struct EffectPlanItem: Codable, Identifiable, Equatable {
- Line 705:    func encode(to encoder: Encoder) throws {
- Line 758:enum ZoomMarkerKind: String, Codable {
- Line 762:enum ClickPulsePreset: String, Codable, CaseIterable, Identifiable {
- Line 787:struct ClickPulseConfiguration: Codable, Equatable {
- Line 808:struct ZoomPlanItem: Codable, Identifiable {
- Line 1017:struct RecordingInspectionSummary {
- Line 1053:enum SharedMotionEngine {
- Line 1054:    enum CoordinateSpace {
- Line 1059:    struct PreviewState {
- Line 1064:    struct ClickPulseRenderState {
- Line 1069:    struct OverlayGeometryResolution {
- Line 1075:    struct Timeline {

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

- Line 7:struct RenderedMarkerPreview {
- Line 19:    func renderPreview(
- Line 185:    func renderEffectPreview(
- Line 346:    func renderDistortionLoupeFrame(
- Line 474:    func makeRealtimeEffectPreviewImage(
- Line 591:enum ExportRenderPhase {
- Line 597:struct ExportRenderResult {
- Line 607:    func cancelExport() {
- Line 611:    func exportRecording(

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

- Line 11:struct ProjectBundleService {
- Line 19:    enum OutputDirectoryResolution {
- Line 25:    enum RecordingBundleResolution {
- Line 31:    func createWorkspace(outputDirectory: URL? = nil, captureMetadata: CaptureMetadata) throws -> RecordingWorkspace {
- Line 89:    func finalizeWorkspace(_ workspace: RecordingWorkspace, manifest: ProjectManifest, events: [RecordedEvent]) throws -> URL {
- Line 123:    func cleanupWorkspace(_ workspace: RecordingWorkspace?) {
- Line 132:    func chooseOutputDirectory() -> URL? {
- Line 152:    func resolvedSelectedOutputDirectory() -> URL? {
- Line 161:    func resolveSelectedOutputDirectory() -> OutputDirectoryResolution {
- Line 196:    func openRecordingBundle() -> URL? {
- Line 215:    func loadRecordingInspection(from bundleURL: URL) async throws -> RecordingInspectionSummary {
- Line 279:    func persistLastRecordingBundle(_ url: URL) -> Bool {
- Line 287:    func resolveLastRecordingBundle() -> RecordingBundleResolution {
- Line 309:    func beginPlaybackAccess(for bundleURL: URL) throws -> URL? {
- Line 329:    func endPlaybackAccess(_ url: URL?) {
- Line 333:    func saveZoomPlan(_ zoomPlan: ZoomPlanEnvelope, in bundleURL: URL) throws {
- Line 344:    func updateCaptureMetadata(
- Line 380:    func libraryRootURL() throws -> URL {
- Line 387:    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
- Line 419:    func registerCaptureInLibrary(_ summary: RecordingInspectionSummary) throws {

## Services/RecordingCoordinator.swift

- Line 36:    func startRecording(target: ShareableCaptureTarget, outputDirectory: URL?, captureMetadata: CaptureMetadata) async {
- Line 85:    func stopRecording() async {

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
- Line 241:    func load() async {
- Line 263:    func activateCaptureTarget(_ target: ShareableCaptureTarget) {
- Line 281:    func requestPermission() async {
- Line 287:    func startRecording() async {
- Line 316:    func stopRecording() async {
- Line 325:    func revealInFinder() {
- Line 330:    func chooseOutputFolder() {
- Line 336:    func openRecording() {
- Line 341:    func exportRecording() {
- Line 392:    func cancelExport() {
- Line 398:    func dismissExportSheet() {
- Line 443:    func revealExportInFinder() {
- Line 448:    func openLibraryCapture(_ item: CaptureLibraryItem) {
- Line 461:    func revealLibraryCapture(_ item: CaptureLibraryItem) {
- Line 470:    func startMarkerPreview(_ markerID: String) {
- Line 574:    func togglePlayback() {
- Line 606:    func seekPlaybackInteractively(to seconds: Double) {
- Line 630:    func jumpPlaybackToStart() {
- Line 653:    func cancelPlaybackPreview() {
- Line 671:    func beginTimelineScrub() {
- Line 702:    func updateTimelineScrub(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 714:    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 733:    func seekTimelineDirectly(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 762:    func nudgeSelectedTimelineMarker(by delta: Double) {
- Line 784:    func nudgeSelectedEffectTimelineMarker(by delta: Double) {
- Line 820:    func setSelectedMarkerEnabled(_ enabled: Bool) {
- Line 826:    func setMarkerEnabled(_ enabled: Bool, for markerID: String) {
- Line 832:    func toggleMarkerEnabled(_ markerID: String) {
- Line 838:    func setMarkerName(_ markerName: String?, for markerID: String) {
- Line 845:    func setSelectedMarkerZoomScale(_ zoomScale: Double) {
- Line 851:    func setSelectedMarkerLeadInTime(_ leadInTime: Double) {
- Line 858:    func setSelectedMarkerZoomInDuration(_ zoomInDuration: Double) {
- Line 865:    func setSelectedMarkerHoldDuration(_ holdDuration: Double) {
- Line 872:    func setSelectedMarkerZoomOutDuration(_ zoomOutDuration: Double) {
- Line 879:    func setSelectedMarkerEaseStyle(_ easeStyle: ZoomEaseStyle) {
- Line 885:    func setSelectedMarkerZoomType(_ zoomType: ZoomType) {
- Line 895:    func setSelectedMarkerBounceAmount(_ bounceAmount: Double) {
- Line 901:    func setSelectedMarkerNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 907:    func setSelectedMarkerNoZoomOverflowRegion(_ region: NoZoomOverflowRegion?) {
- Line 913:    func clearSelectedMarkerNoZoomOverflowRegion() {
- Line 917:    func setSelectedEffectFocusRegion(_ region: EffectFocusRegion?) {
- Line 929:    func clearSelectedEffectFocusRegion() {
- Line 933:    func selectEffectMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 949:    func selectZoomMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 968:    func previewEffectMarker(_ markerID: String) {
- Line 990:    func startEffectMarkerPreview(_ markerID: String) {
- Line 1094:    func setSelectedEffectMarkerEnabled(_ enabled: Bool) {
- Line 1100:    func toggleEffectMarkerEnabled(_ markerID: String) {
- Line 1106:    func setEffectMarkerName(_ markerName: String?, for markerID: String) {
- Line 1113:    func setSelectedEffectStyle(_ style: EffectStyle) {
- Line 1128:    func setSelectedEffectAmount(_ amount: Double) {
- Line 1134:    func setDistortionLoupePoint(_ point: CGPoint) {
- Line 1142:    func resetDistortionLoupePointToDefault() {
- Line 1147:    func setSelectedEffectDistortionPreset(_ preset: DistortionPreset) {
- Line 1157:    func setSelectedEffectDistortionScale(_ scale: Double) {
- Line 1166:    func setSelectedEffectDistortionBackgroundBlend(_ blend: Double) {
- Line 1175:    func setSelectedEffectDistortionBackgroundBlur(_ blur: Double) {
- Line 1184:    func setSelectedEffectBlurAmount(_ amount: Double) {
- Line 1194:    func setSelectedEffectDarkenAmount(_ amount: Double) {
- Line 1204:    func setSelectedEffectTintAmount(_ amount: Double) {
- Line 1214:    func setSelectedEffectFadeInDuration(_ duration: Double) {
- Line 1220:    func setSelectedEffectFadeOutDuration(_ duration: Double) {
- Line 1226:    func setSelectedEffectHoldStartTime(_ time: Double) {
- Line 1237:    func setSelectedEffectHoldEndTime(_ time: Double) {
- Line 1248:    func setSelectedEffectHoldDuration(_ duration: Double) {
- Line 1254:    func setSelectedEffectCornerRadius(_ radius: Double) {
- Line 1260:    func setSelectedEffectFeather(_ feather: Double) {
- Line 1266:    func setSelectedEffectTintColor(_ tintColor: EffectTintColor) {
- Line 1272:    func addEffectMarker(at timestamp: Double? = nil) {
- Line 1308:    func deleteSelectedEffectMarker() {
- Line 1316:    func reorderEffectMarkerList(to orderedMarkerIDs: [String]) {
- Line 1336:    func setDefaultNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 1341:    func setSelectedMarkerClickPulseEnabled(_ enabled: Bool) {
- Line 1352:    func setSelectedMarkerClickPulsePreset(_ preset: ClickPulsePreset) {
- Line 1363:    func setCurrentCaptureTitle(_ title: String) {
- Line 1368:    func setCurrentCaptureCollectionName(_ collectionName: String) {
- Line 1373:    func setCurrentCaptureProjectName(_ projectName: String) {
- Line 1378:    func setCurrentCaptureType(_ captureType: CaptureType) {
- Line 1383:    func deleteSelectedMarker() {
- Line 1391:    func duplicateSelectedMarker() {
- Line 1402:    func addClickFocusMarker(at sourcePoint: CGPoint, timestamp: Double? = nil) {
- Line 1453:    func reorderMarkerList(to orderedMarkerIDs: [String]) {
- Line 1472:    func moveSelectedMarker(to sourcePoint: CGPoint) {
- Line 1599:    func refreshLibrary() async {
- Line 1933:    func scheduleDistortionLoupeRefresh() {
- Line 1941:    func defaultDistortionLoupeNormalizedPoint(for marker: EffectPlanItem) -> CGPoint {

## Views/Capture/CaptureSetupViews.swift

- Line 3:extension ContentView {
- Line 223:    func targetSection(title: String, targets: [ShareableCaptureTarget]) -> some View {
- Line 241:    func targetRow(_ target: ShareableCaptureTarget) -> some View {

## Views/Library/LibraryViews.swift

- Line 3:extension ContentView {
- Line 103:    func libraryCaptureRow(_ item: CaptureLibraryItem) -> some View {
- Line 219:    func libraryMetadataPill(text: String, systemName: String) -> some View {
- Line 235:    func matchesLibrarySearch(_ item: CaptureLibraryItem) -> Bool {
- Line 247:    func matchesLibraryCollectionFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 252:    func matchesLibraryProjectFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 257:    func matchesLibraryTypeFilter(_ item: CaptureLibraryItem) -> Bool {
- Line 331:    func buildLibraryFilterOptions(
- Line 341:    func libraryFilterSection(
- Line 426:    func activeLibraryFilterChip(title: String, removeAction: @escaping () -> Void) -> some View {
- Line 450:    func toggleLibraryCollectionFilter(_ collectionName: String) {
- Line 462:    func toggleLibraryProjectFilter(_ projectName: String) {
- Line 470:    func toggleLibraryTypeFilter(_ type: CaptureType) {
- Line 474:    func clearLibraryFilters() {

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
- Line 195:struct EffectsTimelineTrackView: View {
- Line 342:struct EffectListEntry: Identifiable {
- Line 351:struct EffectListTableView: NSViewRepresentable {
- Line 363:    func makeCoordinator() -> Coordinator {
- Line 367:    func makeNSView(context: Context) -> NSScrollView {
- Line 404:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 425:        func handleTableViewAction(_ sender: Any?) {
- Line 435:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 439:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 443:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 469:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 482:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 491:        func tableView(
- Line 501:        func tableView(
- Line 522:        func syncSelection() {
- Line 539:        func refreshTableIfNeeded() {
- Line 810:    func update(rootView: EffectListCellContent) {

## Views/Review/MarkerListTableViews.swift

- Line 5:struct MarkerListTableView: NSViewRepresentable {
- Line 17:    func makeCoordinator() -> Coordinator {
- Line 21:    func makeNSView(context: Context) -> NSScrollView {
- Line 58:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 79:        func handleTableViewAction(_ sender: Any?) {
- Line 89:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 93:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 97:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 123:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 136:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 145:        func tableView(
- Line 155:        func tableView(
- Line 176:        func syncSelection() {
- Line 193:        func refreshTableIfNeeded() {
- Line 420:    func update(rootView: MarkerListCellContent) {
- Line 438:    func validateDrop(info: DropInfo) -> Bool {
- Line 442:    func dropEntered(info: DropInfo) {
- Line 455:    func dropUpdated(info: DropInfo) -> DropProposal? {
- Line 462:    func performDrop(info: DropInfo) -> Bool {
- Line 485:    func dropExited(info: DropInfo) {

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

## Views/Review/ReviewInspectorViews.swift

- Line 3:enum EditInspectorMode: String, CaseIterable, Identifiable {
- Line 10:struct InspectorSectionHeaderView: View {
- Line 21:struct EffectsInspectorPlaceholderView: View {
- Line 47:struct ReviewInspectorCard<PrimaryContent: View, EffectsContent: View>: View {

## Views/Review/ReviewMarkerInspectorViews.swift

- Line 4:extension ContentView {
- Line 5:    func markerInspectorCard(_ summary: RecordingInspectionSummary) -> some View {
- Line 27:    func effectsInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 85:    func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
- Line 144:    func markerListRow(
- Line 264:    func markerListDragPreview(
- Line 599:    func markerDisplayNumber(for marker: ZoomPlanItem) -> Int {
- Line 607:    func timingSliderRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
- Line 642:    func pointTimingRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
- Line 707:    func setSelectedEffectHoldStartTimeAndFollowPlayback(_ time: Double) {
- Line 716:    func setSelectedEffectHoldEndTimeAndFollowPlayback(_ time: Double) {
- Line 726:    func effectAmountEditorSection(for marker: EffectPlanItem) -> some View {
- Line 764:    func distortionEditorSection(for marker: EffectPlanItem) -> some View {
- Line 806:    func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
- Line 827:    func markerTypeSymbol(for zoomType: ZoomType) -> String {

## Views/Review/ReviewPlaybackMainViews.swift

- Line 4:extension ContentView {
- Line 5:    func playbackVideoCard(
- Line 644:    func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
- Line 991:    func playbackInfoPopover(_ summary: RecordingInspectionSummary) -> some View {

## Views/Review/ReviewPlaybackPreviewViews.swift

- Line 5:extension ContentView {
- Line 6:    func playbackTransitionPlateOpacity(
- Line 19:    func playbackTransitionPlateAnimationDuration(
- Line 34:    func activeZoomPreviewState(
- Line 50:    func activeEffectPreviewState(
- Line 106:    func effectPreviewOverlay(
- Line 147:    func effectBlurLayer(
- Line 186:    func effectOutsideMask(
- Line 207:    func effectPreviewOverlayColor(for effectState: EffectPreviewState) -> Color {
- Line 224:    func color(for tintColor: EffectTintColor) -> Color {
- Line 234:    func transformedOverlayRect(
- Line 260:    func zoomPreviewOffset(for previewState: ZoomPreviewState?, in fittedRect: CGRect) -> CGSize {
- Line 273:    func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
- Line 278:    func overlayPoint(
- Line 304:    func sourcePoint(
- Line 330:    func noZoomOverflowRegion(
- Line 351:    func effectFocusRegion(
- Line 367:    func aspectLockedSourceRect(
- Line 396:    func freeformSourceRect(
- Line 425:    func effectFocusSourceRect(
- Line 437:    func effectFocusRegion(
- Line 449:    func overlayRect(
- Line 488:    func overlayRect(
- Line 522:    func overflowRegionCornerRadii(
- Line 543:    func nudgedNoZoomOverflowRegion(
- Line 570:    func nudgedEffectFocusRegion(
- Line 597:    func movedEffectFocusRegion(
- Line 606:    func effectRegionHandlePoint(for handle: EffectRegionHandle, in rect: CGRect) -> CGPoint {
- Line 627:    func resizedEffectFocusRegion(
- Line 713:    func fittedVideoRect(in containerSize: CGSize, aspectRatio: CGFloat) -> CGRect {
- Line 730:    func effectRegionPrecisionLoupe(
- Line 789:    func transformedOverlayPoint(

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
- Line 165:    func timelinePlayheadView(
- Line 198:    func timelineFooterView(

## Views/Review/ReviewTimelineViews.swift

- Line 3:extension ContentView {
- Line 4:    func playbackTransportBar(_ summary: RecordingInspectionSummary) -> some View {
- Line 35:    func referenceTimelineSegment(
- Line 67:    func timelineLane(for startRatio: Double, endRatio: Double, laneEndRatios: inout [Double]) -> Int {
- Line 85:    func timelineTime(for x: CGFloat, width: CGFloat, duration: Double) -> Double {
- Line 90:    func timelineX(for time: Double, duration: Double, width: CGFloat) -> CGFloat {
- Line 96:    func timelineSnapTarget(
- Line 116:    func effectTimelineSnapTarget(

## Views/Review/TimelineToolbarControls.swift

- Line 3:struct TimelineToolbarView: View {
- Line 107:struct EffectsTimelineToolbarView: View {
- Line 169:struct TimelineGadgetButton: View {

## Views/Review/ZoomAndClicksEditorViews.swift

- Line 4:enum MarkerTimingPhase: String {
- Line 11:struct TimelineSegmentLayout: Identifiable {
- Line 22:func timelineSegmentLayouts(for markers: [ZoomPlanItem], duration: Double) -> [TimelineSegmentLayout] {
- Line 64:func timelineSegment(
- Line 210:func timelineMarkerTooltipOverlay(

## Views/Settings/SettingsViews.swift

- Line 3:extension ContentView {
- Line 76:    func settingsCard(title: String, body: AnyView) -> some View {

## Views/Shared/ExportProgressSheetViews.swift

- Line 4:extension ContentView {
- Line 87:    func presentExportSharePicker() {

## Views/Shared/TimecodeFormatting.swift

- Line 3:extension ContentView {
- Line 4:    func timecodeString(since start: Date, now: Date) -> String {
- Line 14:    func timecodeString(for seconds: Double) -> String {

