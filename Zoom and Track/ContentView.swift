//
//  ContentView.swift
//  Zoom and Track
//

import AppKit
import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var viewModel = CaptureSetupViewModel()
    @State var selectedTab: AppTab? = .capture
    @State private var playbackVideoHeightOverride: CGFloat?
    @State var playbackVideoHeightDragOrigin: CGFloat?
    @State var isPlaybackInspectorVisible = true
    @State private var isPlaybackInfoPresented = false
    @State private var playbackScrubTime = 0.0
    @State private var isScrubbingPlayback = false
    @State var suppressMarkerListAutoScrollUntil: Date?
    @State private var draggedMarkerListID: String?
    @State private var markerListDropTargetID: String?
    @State private var markerListPreviewOrder: [String]?
    @State var renamingMarkerID: String?
    @State var markerNameDraft: String = ""
    @State var renamingEffectMarkerID: String?
    @State var effectMarkerNameDraft: String = ""
    @State var hoveredTimelineMarkerID: String?
    @State var hoveredEffectTimelineMarkerID: String?
    @State var isDraggingTimeline = false
    @State var inspectorFocusedTimingPhase: MarkerTimingPhase?
    @State var hoveredTimelinePhase: MarkerTimingPhase?
    @State var hoveredTimelineTooltipAnchor: CGPoint?
    @State var hoveredEffectTimelineTooltipAnchor: CGPoint?
    @State private var exportShareAnchorView: NSView?
    @State var isPlacingClickFocus = false
    @State var pendingMarkerDragSourcePoint: CGPoint?
    @State var isDrawingNoZoomOverflowRegion = false
    @State var pendingNoZoomOverflowRegion: NoZoomOverflowRegion?
    @State var isDrawingEffectFocusRegion = false
    @State var pendingEffectFocusRegion: EffectFocusRegion?
    @State var effectFocusRegionInteractionBase: EffectFocusRegion?
    @State var activeEffectRegionPrecisionPoint: CGPoint?
    @State var activeEffectRegionHandle: EffectRegionHandle?
    @State var activeTimelineMarkerDragID: String?
    @State var activeTimelineMarkerDragStartTime: Double?
    @State var librarySearchText = ""
    @State var editorMode: ReviewEditorMode = .zoomAndClicks
    @State var inspectorMode: EditInspectorMode = .markers
    @State var selectedLibraryCollectionFilter: String?
    @State var selectedLibraryProjectFilter: String?
    @State var selectedLibraryTypeFilter: CaptureType?
    @State var captureInfoTitleDraft = ""
    @State var captureInfoCollectionDraft = ""
    @State var captureInfoProjectDraft = ""
    @FocusState var focusedCaptureInfoField: CaptureInfoField?
    @FocusState var isTimelineKeyboardFocused: Bool

    struct OverlayMapping {
        let point: CGPoint
        let fittedRect: CGRect
        let sourceSize: CGSize
        let sourcePoint: CGPoint
        let rawPoint: CGPoint?
        let captureSourceLabel: String
    }

    struct ZoomPreviewState {
        let scale: CGFloat
        let normalizedPoint: CGPoint
    }

    struct EffectPreviewState {
        let style: EffectStyle
        let region: EffectFocusRegion
        let blurIntensity: Double
        let darkenIntensity: Double
        let tintIntensity: Double
        let cornerRadius: CGFloat
        let feather: CGFloat
        let tintColor: Color
    }

    enum EffectRegionHandle: Hashable {
        case topLeading
        case topCenter
        case topTrailing
        case centerLeading
        case centerTrailing
        case bottomLeading
        case bottomCenter
        case bottomTrailing
    }

    struct ZoomStateEvent {
        let marker: ZoomPlanItem
        let normalizedPoint: CGPoint
        let scale: CGFloat
    }

    enum MotionDirection {
        case entering
        case exiting
    }

    struct MotionProgressSample {
        let scale: Double
        let pan: Double
    }

    private enum TimelineSnapSelection {
        case zoom(marker: ZoomPlanItem, time: Double, distance: CGFloat)
        case effect(marker: EffectPlanItem, time: Double, distance: CGFloat)

        var time: Double {
            switch self {
            case let .zoom(_, time, _), let .effect(_, time, _):
                return time
            }
        }

        var zoomMarkerID: String? {
            switch self {
            case let .zoom(marker, _, _):
                return marker.id
            case .effect:
                return nil
            }
        }

        var effectMarkerID: String? {
            switch self {
            case .zoom:
                return nil
            case let .effect(marker, _, _):
                return marker.id
            }
        }

        var distance: CGFloat {
            switch self {
            case let .zoom(_, _, distance), let .effect(_, _, distance):
                return distance
            }
        }
    }

    enum CaptureInfoField: Hashable {
        case title
        case collection
        case project
    }

    enum MotionTuning {
        static let bounceApproachFraction = 0.82
        static let bounceMaxOvershoot = 0.14
        static let bounceMinOvershoot = 0.04
        static let bounceOscillationCount = 2.6
        static let panBounceInfluence = 0.35
    }

    struct LibraryFilterOption: Identifiable {
        let label: String
        let count: Int

        var id: String { label }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .frame(minWidth: 1180, minHeight: 760)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.sessionState) {
            if case .finished = viewModel.sessionState {
                selectedTab = .review
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarBrandHeader
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(AppTab.allCases) { tab in
                    sidebarTabRow(tab)
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
        .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
    }

    private var sidebarBrandHeader: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 150)
    }

    private func sidebarTabRow(_ tab: AppTab) -> some View {
        let isSelected = (selectedTab ?? .capture) == tab

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? accentContrastingTextColor() : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch selectedTab ?? .capture {
            case .capture:
                captureView
            case .library:
                libraryView
            case .review:
                reviewView
            case .settings:
                settingsView
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(detailBackground)
    }

    private var reviewView: some View {
        let reviewTitle = viewModel.recordingSummary?.displayTitle ?? "Edit"
        let reviewSubtitle = viewModel.recordingSummary.map { "\($0.displaySubtitle) • \($0.bundleName)" } ?? "Review your latest capture"

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                sectionHeader(
                    title: reviewTitle,
                    subtitle: reviewSubtitle,
                    accentWidth: 132
                )

                Spacer()

                if viewModel.recordingSummary != nil {
                    Button {
                        isPlaybackInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .popover(isPresented: $isPlaybackInfoPresented, arrowEdge: .top) {
                        if let summary = viewModel.recordingSummary {
                            playbackInfoPopover(summary)
                                .frame(width: 360)
                                .padding(16)
                        }
                    }
                }

                Button {
                    isPlaybackInspectorVisible.toggle()
                } label: {
                    Image(systemName: isPlaybackInspectorVisible ? "sidebar.right" : "sidebar.right")
                }
                .help(isPlaybackInspectorVisible ? "Hide Inspector" : "Show Inspector")

                if viewModel.recordingSummary != nil {
                    Button("Export…") {
                        viewModel.exportRecording()
                    }
                    .disabled(!viewModel.canExportRecording)
                }
            }
            .zIndex(2)

            if let mainPlayer = viewModel.mainPlayer, let summary = viewModel.recordingSummary {
                GeometryReader { geometry in
                    let safeAspectRatio = max(summary.videoAspectRatio, 0.1)
                    let inspectorWidth: CGFloat = 320
                    let activeInspectorWidth = isPlaybackInspectorVisible ? inspectorWidth : 0
                    let contentWidth = max(geometry.size.width - activeInspectorWidth - (isPlaybackInspectorVisible ? 22 : 0), 320)
                    let reservedBottomHeight: CGFloat = 156
                    let totalVerticalSpacing: CGFloat = 16
                    let maxVideoHeight = max(180, min(geometry.size.height - reservedBottomHeight - totalVerticalSpacing, geometry.size.height * 0.7))
                    let minVideoHeight = min(280, maxVideoHeight)
                    let defaultVideoHeight = min(max(contentWidth / safeAspectRatio, minVideoHeight), maxVideoHeight)
                    let videoHeight = min(max(playbackVideoHeightOverride ?? defaultVideoHeight, minVideoHeight), maxVideoHeight)

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            playbackVideoCard(
                                mainPlayer: mainPlayer,
                                previewPlayer: viewModel.previewPlayer,
                                aspectRatio: summary.videoAspectRatio,
                                selectedMarker: editorMode == .zoomAndClicks ? viewModel.selectedZoomMarker : nil,
                                selectedEffectMarker: editorMode == .effects ? viewModel.selectedEffectMarker : nil,
                                contentCoordinateSize: summary.contentCoordinateSize,
                                zoomMarkers: summary.zoomMarkers,
                                effectMarkers: summary.effectMarkers,
                                currentTime: viewModel.currentPlaybackTime,
                                isRenderedPreviewActive: viewModel.isRenderedPreviewActive,
                                renderingStatusMessage: viewModel.markerPreviewStatusMessage,
                                playbackPresentationMode: viewModel.playbackPresentationMode,
                                playbackTransitionPlateState: viewModel.playbackTransitionPlateState,
                                isPlacingClickFocus: editorMode == .zoomAndClicks ? isPlacingClickFocus : false,
                                draggedMarkerSourcePoint: editorMode == .zoomAndClicks ? pendingMarkerDragSourcePoint : nil,
                                isDrawingNoZoomOverflowRegion: editorMode == .zoomAndClicks ? isDrawingNoZoomOverflowRegion : false,
                                pendingNoZoomOverflowRegion: editorMode == .zoomAndClicks ? pendingNoZoomOverflowRegion : nil,
                                isDrawingEffectFocusRegion: editorMode == .effects ? isDrawingEffectFocusRegion : false,
                                pendingEffectFocusRegion: editorMode == .effects ? pendingEffectFocusRegion : nil,
                                placeClickFocusAction: { sourcePoint in
                                    viewModel.addClickFocusMarker(at: sourcePoint)
                                    pendingMarkerDragSourcePoint = nil
                                    isPlacingClickFocus = false
                                },
                                dragSelectedMarkerAction: { sourcePoint in
                                    pendingMarkerDragSourcePoint = sourcePoint
                                },
                                commitDraggedMarkerAction: { sourcePoint in
                                    viewModel.moveSelectedMarker(to: sourcePoint)
                                    pendingMarkerDragSourcePoint = nil
                                },
                                updateNoZoomOverflowRegionAction: { region in
                                    pendingNoZoomOverflowRegion = region
                                },
                                updateEffectFocusRegionAction: { region in
                                    pendingEffectFocusRegion = region
                                }
                            )
                                .frame(height: videoHeight)
                                .layoutPriority(1)

                            playbackTimelineStrip(summary)

                            playbackTransportBar(summary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        if isPlaybackInspectorVisible {
                            markerInspectorCard(summary)
                                .frame(width: inspectorWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(0)
                    .onChange(of: summary.recordingURL) {
                        playbackVideoHeightOverride = nil
                        playbackVideoHeightDragOrigin = nil
                        playbackScrubTime = 0
                        isScrubbingPlayback = false
                        isPlacingClickFocus = false
                        pendingMarkerDragSourcePoint = nil
                    }
                    .onChange(of: viewModel.currentPlaybackTime) {
                        guard !isScrubbingPlayback else { return }
                        playbackScrubTime = viewModel.currentPlaybackTime
                    }
                    .onChange(of: editorMode) {
                        isPlacingClickFocus = false
                        pendingMarkerDragSourcePoint = nil
                        isDrawingNoZoomOverflowRegion = false
                        pendingNoZoomOverflowRegion = nil
                        isDrawingEffectFocusRegion = false
                        pendingEffectFocusRegion = nil
                        effectFocusRegionInteractionBase = nil
                        activeEffectRegionPrecisionPoint = nil
                        activeEffectRegionHandle = nil
                        activeTimelineMarkerDragID = nil
                        activeTimelineMarkerDragStartTime = nil
                        renamingEffectMarkerID = nil
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recording loaded")
                        .font(.headline)
                    Text("Open a `.captureproj` bundle or finish a capture to edit it here.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 480, maxHeight: .infinity, alignment: .topLeading)
                .background(cardBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: Binding(
            get: { viewModel.isExportSheetPresented },
            set: { if !$0 { viewModel.dismissExportSheet() } }
        )) {
            exportProgressSheet
                .frame(width: 420)
                .padding(24)
                .interactiveDismissDisabled(viewModel.exportState.isInProgress)
        }
    }

    func effectTintColorBinding(for marker: EffectPlanItem) -> Binding<Color> {
        Binding(
            get: { color(for: marker.tintColor) },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .controlAccentColor
                viewModel.setSelectedEffectTintColor(
                    EffectTintColor(
                        red: Double(nsColor.redComponent),
                        green: Double(nsColor.greenComponent),
                        blue: Double(nsColor.blueComponent),
                        alpha: Double(nsColor.alphaComponent)
                    )
                )
            }
        )
    }

    private var exportProgressSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exportSheetTitle)
                .font(.title3.weight(.semibold))

            if let exportStatusMessage = viewModel.exportStatusMessage {
                Text(exportStatusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressValueForDisplay)
                .progressViewStyle(.linear)

            Text("\(Int(progressValueForDisplay * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack {
                if case .completed = viewModel.exportState {
                    Button("Reveal in Finder") {
                        viewModel.revealExportInFinder()
                    }

                    Button("Share…") {
                        presentExportSharePicker()
                    }
                    .background(
                        SharingAnchorView { view in
                            exportShareAnchorView = view
                        }
                        .frame(width: 0, height: 0)
                    )
                }

                Spacer()

                switch viewModel.exportState {
                case .preparing, .exporting, .finalizing:
                    Button("Cancel") {
                        viewModel.cancelExport()
                    }
                default:
                    Button("Done") {
                        viewModel.dismissExportSheet()
                    }
                }
            }
        }
    }

    private var exportSheetTitle: String {
        switch viewModel.exportState {
        case .idle:
            return "Export"
        case .preparing:
            return "Preparing Export"
        case .exporting:
            return "Exporting Video"
        case .finalizing:
            return "Finalizing Movie"
        case .completed:
            return "Export Complete"
        case .failed:
            return "Export Failed"
        case .cancelled:
            return "Export Cancelled"
        }
    }

    private var progressValueForDisplay: Double {
        let progress = max(0, min(viewModel.exportProgress, 1))
        switch viewModel.exportState {
        case .completed:
            return 1
        case .failed, .cancelled, .idle:
            return progress
        default:
            return max(progress, 0.02)
        }
    }

    private func presentExportSharePicker() {
        guard let exportedRecordingURL = viewModel.exportedRecordingURL,
              let exportShareAnchorView else {
            return
        }

        let picker = NSSharingServicePicker(items: [exportedRecordingURL])
        picker.show(
            relativeTo: exportShareAnchorView.bounds,
            of: exportShareAnchorView,
            preferredEdge: .maxY
        )
    }

    // Best effort mapping from capture coordinates into the fitted video rect.
    // Mouse coordinates are captured in a bottom-left origin space, while SwiftUI
    // overlay positioning uses top-left origin inside the displayed video area.
    func mappedOverlayPoint(
        for marker: ZoomPlanItem?,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> OverlayMapping? {
        guard let marker,
              contentCoordinateSize.width > 0,
              contentCoordinateSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return nil
        }

        let fittedRect = fittedVideoRect(in: containerSize, aspectRatio: videoAspectRatio)
        guard fittedRect.width > 0, fittedRect.height > 0 else {
            return nil
        }

        let normalizedX = min(max(marker.centerX / contentCoordinateSize.width, 0), 1)
        let normalizedY = min(max(marker.centerY / contentCoordinateSize.height, 0), 1)

        let x = fittedRect.minX + (normalizedX * fittedRect.width)
        let y = fittedRect.minY + (normalizedY * fittedRect.height)

        guard x.isFinite, y.isFinite else { return nil }
        return OverlayMapping(
            point: CGPoint(x: x, y: y),
            fittedRect: fittedRect,
            sourceSize: contentCoordinateSize,
            sourcePoint: CGPoint(x: marker.centerX, y: marker.centerY),
            rawPoint: {
                guard let rawX = marker.rawX, let rawY = marker.rawY else { return nil }
                return CGPoint(x: rawX, y: rawY)
            }(),
            captureSourceLabel: "\(viewModel.recordingSummary?.captureSourceKind.rawValue ?? "unknown") • \(viewModel.recordingSummary?.captureSourceTitle ?? "unknown")"
        )
    }

    func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }

    func metadataItem(_ title: String, _ value: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .lineLimit(multiline ? 3 : 1)
        }
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }

    private var detailBackground: some View {
        ZStack {
            if colorScheme == .light {
                Color(nsColor: .windowBackgroundColor)
                accentTint
                    .opacity(0.20)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var accentTint: Color {
        let accent = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? .systemBlue
        return Color(nsColor: accent)
    }

    func sectionHeader(title: String, subtitle: String, accentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: accentWidth, height: 2)
                .padding(.top, 12)
        }
    }

    func setTimelineHover(markerID: String, phase: MarkerTimingPhase?, anchor: CGPoint) {
        hoveredTimelineMarkerID = markerID
        hoveredTimelinePhase = phase
        hoveredTimelineTooltipAnchor = anchor
        print("hover enter marker \(markerID)")
    }

    func clearTimelineHover() {
        if let hoveredTimelineMarkerID {
            print("hover exit marker \(hoveredTimelineMarkerID)")
        }
        hoveredTimelineMarkerID = nil
        hoveredTimelinePhase = nil
        hoveredTimelineTooltipAnchor = nil
    }

    func setEffectTimelineHover(markerID: String, anchor: CGPoint) {
        hoveredEffectTimelineMarkerID = markerID
        hoveredEffectTimelineTooltipAnchor = anchor
    }

    func clearEffectTimelineHover() {
        hoveredEffectTimelineMarkerID = nil
        hoveredEffectTimelineTooltipAnchor = nil
    }

    func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
        guard let hoveredTimelineMarkerID else { return nil }
        guard let entry = summary.zoomMarkers.enumerated().first(where: { $0.element.id == hoveredTimelineMarkerID }) else {
            return nil
        }
        print("hovered id = \(hoveredTimelineMarkerID)")
        print("resolved tooltip id = \(entry.element.id)")
        return (entry.element, entry.offset + 1)
    }

    func hoveredEffectTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: EffectPlanItem, markerNumber: Int)? {
        guard let hoveredEffectTimelineMarkerID else { return nil }
        let displayedMarkers = displayedEffectMarkerList(summary.effectMarkers)
        guard let entry = displayedMarkers.enumerated().first(where: { $0.element.id == hoveredEffectTimelineMarkerID }) else {
            return nil
        }
        return (entry.element, entry.offset + 1)
    }

    func displayedTimelinePhase(for marker: ZoomPlanItem) -> MarkerTimingPhase? {
        if viewModel.activePreviewMarkerID == marker.id {
            return timelinePhase(for: marker, at: viewModel.currentPlaybackTime)
        }

        if viewModel.selectedZoomMarkerID == marker.id {
            if hoveredTimelineMarkerID == marker.id, hoveredTimelinePhase != nil {
                return hoveredTimelinePhase
            }
            return inspectorFocusedTimingPhase
        }

        return nil
    }

    func isMarkerPlaybackHighlighted(_ marker: ZoomPlanItem) -> Bool {
        guard timelinePhase(for: marker, at: viewModel.currentPlaybackTime) != nil else {
            return false
        }

        if viewModel.activePreviewMarkerID == marker.id {
            return true
        }

        return viewModel.isPlaybackActive && viewModel.selectedZoomMarkerID == marker.id
    }

    func isEffectPlaybackHighlighted(_ marker: EffectPlanItem) -> Bool {
        viewModel.currentPlaybackTime >= marker.startTime && viewModel.currentPlaybackTime <= marker.endTime
    }

    func displayedMarkerList(_ markers: [ZoomPlanItem], previewOrder: [String]? = nil) -> [ZoomPlanItem] {
        if let previewOrder {
            let lookup = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
            let ordered = previewOrder.compactMap { lookup[$0] }
            let missing = markers.filter { !previewOrder.contains($0.id) }
            return ordered + missing
        }

        return markers
            .enumerated()
            .sorted { lhs, rhs in
                let leftOrder = lhs.element.displayOrder ?? lhs.offset
                let rightOrder = rhs.element.displayOrder ?? rhs.offset
                if leftOrder == rightOrder {
                    return lhs.offset < rhs.offset
                }
                return leftOrder < rightOrder
            }
            .map(\.element)
    }

    func displayedEffectMarkerList(_ markers: [EffectPlanItem]) -> [EffectPlanItem] {
        markers
            .enumerated()
            .sorted { lhs, rhs in
                let leftOrder = lhs.element.displayOrder ?? lhs.offset
                let rightOrder = rhs.element.displayOrder ?? rhs.offset
                if leftOrder == rightOrder {
                    return lhs.offset < rhs.offset
                }
                return leftOrder < rightOrder
            }
            .map(\.element)
    }

    private func timelinePhase(for marker: ZoomPlanItem, at currentTime: Double) -> MarkerTimingPhase? {
        let timeline = zoomTimeline(for: marker)
        guard currentTime >= timeline.startTime, currentTime <= timeline.endTime else {
            return nil
        }

        switch marker.zoomType {
        case .inOut:
            let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)
            if currentTime < zoomInStart {
                return .leadIn
            }
            if currentTime < timeline.peakTime {
                return .zoomIn
            }
            if currentTime < timeline.holdUntil {
                return .hold
            }
            return .zoomOut

        case .inOnly:
            let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)
            if currentTime < zoomInStart {
                return .leadIn
            }
            if currentTime < timeline.peakTime {
                return .zoomIn
            }
            return .hold

        case .noZoom:
            let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)
            if currentTime < zoomInStart {
                return .leadIn
            }
            if currentTime < timeline.peakTime {
                return .zoomIn
            }
            return .hold

        case .outOnly:
            return currentTime <= timeline.endTime ? .zoomOut : nil
        }
    }

    private func timelineMarkerTooltip(for marker: ZoomPlanItem, markerNumber: Int, isEnabled: Bool) -> String {
        [
            "Marker #\(markerNumber)",
            timecodeString(for: marker.sourceEventTimestamp),
            "\(markerTypeSymbol(for: marker.zoomType)) \(marker.zoomType.displayName)",
            "Zoom \(String(format: "%.1fx", marker.zoomScale))",
            "Duration \(String(format: "%.2fs", marker.totalSegmentDuration))",
            isEnabled ? "Enabled" : "Disabled"
        ].joined(separator: "\n")
    }

    func timecodeString(since start: Date, now: Date) -> String {
        let elapsed = max(now.timeIntervalSince(start), 0)
        let totalFrames = Int(elapsed * 30)
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let seconds = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    func timecodeString(for seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let totalFrames = Int(clampedSeconds * 30)
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let secs = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }
}

private struct SharingAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}

#Preview {
    ContentView()
}

enum AppTab: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case library = "Library"
    case review = "Edit"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .capture:
            return "record.circle"
        case .library:
            return "books.vertical"
        case .review:
            return "play.rectangle"
        case .settings:
            return "gearshape"
        }
    }
}

struct MarkerListEntry: Identifiable {
    let marker: ZoomPlanItem
    let markerNumber: Int
    let isSelected: Bool
    let isPlaybackHighlighted: Bool

    var id: String { marker.id }
}
