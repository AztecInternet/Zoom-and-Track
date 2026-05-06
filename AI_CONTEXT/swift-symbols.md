# Swift Symbols

Generated: 2026-05-06 20:33:30

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
- Line 542:    func mappedOverlayPoint(
- Line 581:    func infoRow(title: String, value: String) -> some View {
- Line 592:    func metadataItem(_ title: String, _ value: String, multiline: Bool = false) -> some View {
- Line 631:    func sectionHeader(title: String, subtitle: String, accentWidth: CGFloat) -> some View {
- Line 647:    func setTimelineHover(markerID: String, phase: MarkerTimingPhase?, anchor: CGPoint) {
- Line 654:    func clearTimelineHover() {
- Line 663:    func setEffectTimelineHover(markerID: String, anchor: CGPoint) {
- Line 668:    func clearEffectTimelineHover() {
- Line 673:    func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
- Line 683:    func hoveredEffectTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: EffectPlanItem, markerNumber: Int)? {
- Line 692:    func displayedTimelinePhase(for marker: ZoomPlanItem) -> MarkerTimingPhase? {
- Line 707:    func isMarkerPlaybackHighlighted(_ marker: ZoomPlanItem) -> Bool {
- Line 719:    func isEffectPlaybackHighlighted(_ marker: EffectPlanItem) -> Bool {
- Line 723:    func displayedMarkerList(_ markers: [ZoomPlanItem], previewOrder: [String]? = nil) -> [ZoomPlanItem] {
- Line 744:    func displayedEffectMarkerList(_ markers: [EffectPlanItem]) -> [EffectPlanItem] {
- Line 819:    func makeNSView(context: Context) -> NSView {
- Line 827:    func updateNSView(_ nsView: NSView, context: Context) {
- Line 838:enum AppTab: String, CaseIterable, Identifiable {
- Line 860:struct MarkerListEntry: Identifiable {

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
- Line 475:struct EffectFocusRegion: Codable, Equatable {
- Line 482:struct EffectTintColor: Codable, Equatable {
- Line 491:struct EffectPlanItem: Codable, Identifiable, Equatable {
- Line 604:enum ZoomMarkerKind: String, Codable {
- Line 608:enum ClickPulsePreset: String, Codable, CaseIterable, Identifiable {
- Line 633:struct ClickPulseConfiguration: Codable, Equatable {
- Line 654:struct ZoomPlanItem: Codable, Identifiable {
- Line 863:struct RecordingInspectionSummary {
- Line 899:enum SharedMotionEngine {
- Line 900:    enum CoordinateSpace {
- Line 905:    struct PreviewState {
- Line 910:    struct ClickPulseRenderState {
- Line 915:    struct OverlayGeometryResolution {
- Line 921:    struct Timeline {

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
- Line 406:enum ExportRenderPhase {
- Line 412:struct ExportRenderResult {
- Line 422:    func cancelExport() {
- Line 426:    func exportRecording(

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
- Line 230:    func load() async {
- Line 252:    func activateCaptureTarget(_ target: ShareableCaptureTarget) {
- Line 270:    func requestPermission() async {
- Line 276:    func startRecording() async {
- Line 305:    func stopRecording() async {
- Line 314:    func revealInFinder() {
- Line 319:    func chooseOutputFolder() {
- Line 325:    func openRecording() {
- Line 330:    func exportRecording() {
- Line 381:    func cancelExport() {
- Line 387:    func dismissExportSheet() {
- Line 432:    func revealExportInFinder() {
- Line 437:    func openLibraryCapture(_ item: CaptureLibraryItem) {
- Line 450:    func revealLibraryCapture(_ item: CaptureLibraryItem) {
- Line 459:    func startMarkerPreview(_ markerID: String) {
- Line 563:    func togglePlayback() {
- Line 590:    func seekPlaybackInteractively(to seconds: Double) {
- Line 604:    func jumpPlaybackToStart() {
- Line 618:    func cancelPlaybackPreview() {
- Line 628:    func beginTimelineScrub() {
- Line 644:    func updateTimelineScrub(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 659:    func endTimelineScrub(at seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 680:    func seekTimelineDirectly(to seconds: Double, snappedMarkerID: String?, snappedEffectMarkerID: String? = nil) {
- Line 706:    func beginTimelineMarkerMove(_ markerID: String) {
- Line 722:    func previewTimelineMarkerMove(_ markerID: String, to seconds: Double) {
- Line 726:    func commitTimelineMarkerMove(_ markerID: String, to seconds: Double) {
- Line 736:    func nudgeSelectedTimelineMarker(by delta: Double) {
- Line 758:    func nudgeSelectedEffectTimelineMarker(by delta: Double) {
- Line 794:    func setSelectedMarkerEnabled(_ enabled: Bool) {
- Line 800:    func setMarkerEnabled(_ enabled: Bool, for markerID: String) {
- Line 806:    func toggleMarkerEnabled(_ markerID: String) {
- Line 812:    func setMarkerName(_ markerName: String?, for markerID: String) {
- Line 819:    func setSelectedMarkerZoomScale(_ zoomScale: Double) {
- Line 825:    func setSelectedMarkerLeadInTime(_ leadInTime: Double) {
- Line 832:    func setSelectedMarkerZoomInDuration(_ zoomInDuration: Double) {
- Line 839:    func setSelectedMarkerHoldDuration(_ holdDuration: Double) {
- Line 846:    func setSelectedMarkerZoomOutDuration(_ zoomOutDuration: Double) {
- Line 853:    func setSelectedMarkerEaseStyle(_ easeStyle: ZoomEaseStyle) {
- Line 859:    func setSelectedMarkerZoomType(_ zoomType: ZoomType) {
- Line 869:    func setSelectedMarkerBounceAmount(_ bounceAmount: Double) {
- Line 875:    func setSelectedMarkerNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 881:    func setSelectedMarkerNoZoomOverflowRegion(_ region: NoZoomOverflowRegion?) {
- Line 887:    func clearSelectedMarkerNoZoomOverflowRegion() {
- Line 891:    func setSelectedEffectFocusRegion(_ region: EffectFocusRegion?) {
- Line 903:    func clearSelectedEffectFocusRegion() {
- Line 907:    func selectEffectMarker(_ markerID: String, seekPlaybackHead: Bool = true) {
- Line 921:    func previewEffectMarker(_ markerID: String) {
- Line 943:    func startEffectMarkerPreview(_ markerID: String) {
- Line 1047:    func setSelectedEffectMarkerEnabled(_ enabled: Bool) {
- Line 1053:    func toggleEffectMarkerEnabled(_ markerID: String) {
- Line 1059:    func setEffectMarkerName(_ markerName: String?, for markerID: String) {
- Line 1066:    func setSelectedEffectStyle(_ style: EffectStyle) {
- Line 1072:    func setSelectedEffectAmount(_ amount: Double) {
- Line 1078:    func setSelectedEffectBlurAmount(_ amount: Double) {
- Line 1088:    func setSelectedEffectDarkenAmount(_ amount: Double) {
- Line 1098:    func setSelectedEffectTintAmount(_ amount: Double) {
- Line 1108:    func setSelectedEffectFadeInDuration(_ duration: Double) {
- Line 1114:    func setSelectedEffectFadeOutDuration(_ duration: Double) {
- Line 1120:    func setSelectedEffectHoldDuration(_ duration: Double) {
- Line 1126:    func setSelectedEffectCornerRadius(_ radius: Double) {
- Line 1132:    func setSelectedEffectFeather(_ feather: Double) {
- Line 1138:    func setSelectedEffectTintColor(_ tintColor: EffectTintColor) {
- Line 1144:    func addEffectMarker(at timestamp: Double? = nil) {
- Line 1179:    func deleteSelectedEffectMarker() {
- Line 1187:    func reorderEffectMarkerList(to orderedMarkerIDs: [String]) {
- Line 1207:    func setDefaultNoZoomFallbackMode(_ fallbackMode: NoZoomFallbackMode) {
- Line 1212:    func setSelectedMarkerClickPulseEnabled(_ enabled: Bool) {
- Line 1223:    func setSelectedMarkerClickPulsePreset(_ preset: ClickPulsePreset) {
- Line 1230:    func setCurrentCaptureTitle(_ title: String) {
- Line 1235:    func setCurrentCaptureCollectionName(_ collectionName: String) {
- Line 1240:    func setCurrentCaptureProjectName(_ projectName: String) {
- Line 1245:    func setCurrentCaptureType(_ captureType: CaptureType) {
- Line 1250:    func deleteSelectedMarker() {
- Line 1258:    func duplicateSelectedMarker() {
- Line 1269:    func addClickFocusMarker(at sourcePoint: CGPoint, timestamp: Double? = nil) {
- Line 1320:    func reorderMarkerList(to orderedMarkerIDs: [String]) {
- Line 1339:    func moveSelectedMarker(to sourcePoint: CGPoint) {
- Line 1466:    func refreshLibrary() async {

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
- Line 78:struct EffectTimelineSegmentLayout: Identifiable {
- Line 88:struct EffectTimelineSegmentView: View {
- Line 169:struct EffectsTimelineTrackView: View {
- Line 313:struct EffectListEntry: Identifiable {
- Line 322:struct EffectListTableView: NSViewRepresentable {
- Line 334:    func makeCoordinator() -> Coordinator {
- Line 338:    func makeNSView(context: Context) -> NSScrollView {
- Line 375:    func updateNSView(_ nsView: NSScrollView, context: Context) {
- Line 396:        func handleTableViewAction(_ sender: Any?) {
- Line 406:        func numberOfRows(in tableView: NSTableView) -> Int {
- Line 410:        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
- Line 414:        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
- Line 440:        func tableViewSelectionDidChange(_ notification: Notification) {
- Line 453:        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
- Line 462:        func tableView(
- Line 472:        func tableView(
- Line 493:        func syncSelection() {
- Line 510:        func refreshTableIfNeeded() {
- Line 777:    func update(rootView: EffectListCellContent) {

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
- Line 577:    func markerDisplayNumber(for marker: ZoomPlanItem) -> Int {
- Line 585:    func timingSliderRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
- Line 621:    func effectAmountEditorSection(for marker: EffectPlanItem) -> some View {
- Line 657:    func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
- Line 678:    func markerTypeSymbol(for zoomType: ZoomType) -> String {

## Views/Review/ReviewPlaybackMainViews.swift

- Line 4:extension ContentView {
- Line 5:    func playbackVideoCard(
- Line 628:    func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
- Line 1014:    func playbackInfoPopover(_ summary: RecordingInspectionSummary) -> some View {

## Views/Review/ReviewPlaybackPreviewViews.swift

- Line 5:extension ContentView {
- Line 6:    func playbackTransitionPlateOpacity(
- Line 19:    func playbackTransitionPlateAnimationDuration(
- Line 34:    func activeZoomPreviewState(
- Line 50:    func activeEffectPreviewState(
- Line 102:    func effectPreviewOverlay(
- Line 143:    func effectBlurLayer(
- Line 182:    func effectOutsideMask(
- Line 203:    func effectPreviewOverlayColor(for effectState: EffectPreviewState) -> Color {
- Line 216:    func color(for tintColor: EffectTintColor) -> Color {
- Line 226:    func transformedOverlayRect(
- Line 252:    func zoomPreviewOffset(for previewState: ZoomPreviewState?, in fittedRect: CGRect) -> CGSize {
- Line 265:    func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
- Line 270:    func overlayPoint(
- Line 296:    func sourcePoint(
- Line 322:    func noZoomOverflowRegion(
- Line 343:    func effectFocusRegion(
- Line 359:    func aspectLockedSourceRect(
- Line 388:    func freeformSourceRect(
- Line 417:    func effectFocusSourceRect(
- Line 429:    func effectFocusRegion(
- Line 441:    func overlayRect(
- Line 480:    func overlayRect(
- Line 514:    func overflowRegionCornerRadii(
- Line 535:    func nudgedNoZoomOverflowRegion(
- Line 562:    func nudgedEffectFocusRegion(
- Line 589:    func movedEffectFocusRegion(
- Line 598:    func effectRegionHandlePoint(for handle: EffectRegionHandle, in rect: CGRect) -> CGPoint {
- Line 619:    func resizedEffectFocusRegion(
- Line 705:    func fittedVideoRect(in containerSize: CGSize, aspectRatio: CGFloat) -> CGRect {
- Line 722:    func effectRegionPrecisionLoupe(
- Line 780:    func transformedOverlayPoint(

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
- Line 38:    func timelineCanvasView(
- Line 183:    func timelinePlayheadView(
- Line 216:    func timelineFooterView(

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
- Line 144:struct EffectsTimelineToolbarView: View {
- Line 206:struct TimelineGadgetButton: View {

## Views/Review/ZoomAndClicksEditorViews.swift

- Line 4:enum MarkerTimingPhase: String {
- Line 11:struct TimelineSegmentLayout: Identifiable {
- Line 22:func timelineSegmentLayouts(for markers: [ZoomPlanItem], duration: Double) -> [TimelineSegmentLayout] {
- Line 64:func timelineSegment(
- Line 230:func timelineMarkerTooltipOverlay(

## Views/Settings/SettingsViews.swift

- Line 3:extension ContentView {
- Line 76:    func settingsCard(title: String, body: AnyView) -> some View {

## Views/Shared/TimecodeFormatting.swift

- Line 3:extension ContentView {
- Line 4:    func timecodeString(since start: Date, now: Date) -> String {
- Line 14:    func timecodeString(for seconds: Double) -> String {

