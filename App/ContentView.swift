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
    @State var isHelpModeEnabled = false
    @State private var isPlaybackInfoPresented = false
    @State private var playbackScrubTime = 0.0
    @State private var hoveredReviewHeaderAction: ReviewHeaderAction?
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
    @State var exportShareAnchorView: NSView?
    @State var isPlacingClickFocus = false
    @State var pendingMarkerDragSourcePoint: CGPoint?
    @State var activeClickPointPrecisionPoint: CGPoint?
    @State var activeClickPointLoupeOffset: CGSize = .zero
    @State var activePrecisionLoupeFrame: PrecisionLoupeFrame?
    @State var precisionLoupeFrameTask: Task<Void, Never>?
    @State var isDrawingNoZoomOverflowRegion = false
    @State var pendingNoZoomOverflowRegion: NoZoomOverflowRegion?
    @State var isDrawingEffectFocusRegion = false
    @State var suppressRealtimeEffectPreviewDuringTimingEdit = false
    @State var activeEffectHoldPoint: ActiveEffectHoldPoint?
    @State var realtimeEffectPreviewResumeTask: Task<Void, Never>?
    @State var autoCommitsEffectFocusRegionOnRelease = false
    @State var pendingEffectFocusRegion: EffectFocusRegion?
    @State var effectFocusRegionInteractionBase: EffectFocusRegion?
    @State var activeEffectRegionPrecisionPoint: CGPoint?
    @State var activeEffectRegionHandle: EffectRegionHandle?
    @State var activeEffectRegionLoupeOffset: CGSize = .zero
    @State var activeTimelineMarkerDragID: String?
    @State var activeTimelineMarkerDragStartTime: Double?
    @State private var activeTimelineMarkerDragTimeOffset = 0.0
    @State private var activeTimelineMarkerDragCursorX: CGFloat?
    @State private var activeTimelineMarkerDragWidth: CGFloat = 1
    @State private var activeTimelineMarkerDragDuration = 0.0
    @State private var timelineMarkerAutoScrollTask: Task<Void, Never>?
    @State private var activeTimelineScrubCursorX: CGFloat?
    @State private var activeTimelineScrubWidth: CGFloat = 1
    @State private var activeTimelineScrubDuration = 0.0
    @State private var timelineScrubAutoScrollTask: Task<Void, Never>?
    @State var timelineZoomScale = 1.0
    @State var visibleTimelineStartTime = 0.0
    @State var isTimelineScrubSnappingEnabled = true
    @State var isPlayheadTimeNudgeFlashActive = false
    @State private var playheadTimeNudgeFlashTask: Task<Void, Never>?
    @State var librarySearchText = ""
    @State var editorMode: ReviewEditorMode = .zoomAndClicks
    @State var inspectorMode: EditInspectorMode = .markers
    @State var selectedLibraryCollectionFilter: String?
    @State var selectedLibraryProjectFilter: String?
    @State var selectedLibraryTypeFilter: CaptureType?
    @State var selectedLibraryCaptureID: UUID?
    @State var captureInfoTitleDraft = ""
    @State var captureInfoCollectionDraft = ""
    @State var captureInfoProjectDraft = ""
    @State var isConfirmingDistortionPresetDelete = false
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

    struct PrecisionLoupeFrame {
        let image: NSImage
        let playbackTime: Double
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

    enum ActiveEffectHoldPoint {
        case holdStart
        case holdEnd
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
        .focusedValue(\.flowTrackCommandContext, flowTrackCommandContext)
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

            helpModeToggle
                .padding(.horizontal, 12)
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
                    .fill(isSelected ? FlowTrackAccent.color(for: tab.accentRole) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var helpModeToggle: some View {
        Button {
            isHelpModeEnabled.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isHelpModeEnabled ? "questionmark.circle.fill" : "questionmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 18)
                Text("Help")
                    .font(.system(size: 14, weight: isHelpModeEnabled ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHelpModeEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHelpModeEnabled ? Color(nsColor: .controlBackgroundColor).opacity(0.82) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHelpModeEnabled ? Color.secondary.opacity(0.16) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isHelpModeEnabled ? "Turn Help Mode Off" : "Turn Help Mode On")
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
        .tint(detailAccentColor)
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

                HStack(spacing: 2) {
                    if viewModel.recordingSummary != nil {
                        Button {
                            isPlaybackInfoPresented = true
                        } label: {
                            reviewHeaderActionIcon("info.circle", action: .info)
                        }
                        .buttonStyle(.plain)
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
                        reviewHeaderActionIcon("sidebar.right", action: .inspector)
                    }
                    .buttonStyle(.plain)
                    .help(isPlaybackInspectorVisible ? "Hide Inspector" : "Show Inspector")

                    if viewModel.recordingSummary != nil {
                        Button {
                            viewModel.exportRecording()
                        } label: {
                            reviewHeaderActionIcon("square.and.arrow.up", action: .export)
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canExportRecording)
                        .help("Export Movie File")
                    }
                }
                .padding(3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            }
            .zIndex(2)

            if let mainPlayer = viewModel.mainPlayer, let summary = viewModel.recordingSummary {
                GeometryReader { geometry in
                    let safeAspectRatio = max(summary.videoAspectRatio, 0.1)
                    let inspectorWidth: CGFloat = 320
                    let activeInspectorWidth = isPlaybackInspectorVisible ? inspectorWidth : 0
                    let contentWidth = max(geometry.size.width - activeInspectorWidth - (isPlaybackInspectorVisible ? 22 : 0), 320)
                    let reservedBottomHeight: CGFloat = 132
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
                                autoCommitsEffectFocusRegionOnRelease: editorMode == .effects ? autoCommitsEffectFocusRegionOnRelease : false,
                                pendingEffectFocusRegion: editorMode == .effects ? pendingEffectFocusRegion : nil,
                                placeClickFocusAction: { sourcePoint in
                                    viewModel.addClickFocusMarker(at: sourcePoint)
                                    pendingMarkerDragSourcePoint = nil
                                    resetClickPointPrecisionLoupe()
                                    isPlacingClickFocus = false
                                },
                                dragSelectedMarkerAction: { sourcePoint in
                                    pendingMarkerDragSourcePoint = sourcePoint
                                },
                                commitDraggedMarkerAction: { sourcePoint in
                                    viewModel.moveSelectedMarker(to: sourcePoint)
                                    pendingMarkerDragSourcePoint = nil
                                    resetClickPointPrecisionLoupe()
                                },
                                updateNoZoomOverflowRegionAction: { region in
                                    pendingNoZoomOverflowRegion = region
                                },
                                updateEffectFocusRegionAction: { region in
                                    pendingEffectFocusRegion = region
                                },
                                commitEffectFocusRegionAction: { region in
                                    finishEffectFocusRegionDrawing(with: region)
                                }
                            )
                                .frame(height: videoHeight)
                                .layoutPriority(1)

                            playbackTimelineStrip(summary)

                            timelineInstructionView(
                                editorMode: editorMode,
                                isDrawingEffectFocusRegion: isDrawingEffectFocusRegion,
                                isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion
                            )
                            .padding(.horizontal, 14)
                            .padding(.top, -8)
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
                        cancelTimelineMarkerAutoScroll()
                        cancelTimelineScrubAutoScroll()
                        playbackVideoHeightOverride = nil
                        playbackVideoHeightDragOrigin = nil
                        playbackScrubTime = 0
                        isScrubbingPlayback = false
                        isPlacingClickFocus = false
                        pendingMarkerDragSourcePoint = nil
                        resetClickPointPrecisionLoupe()
                    }
                    .onChange(of: viewModel.currentPlaybackTime) {
                        guard !isScrubbingPlayback else { return }
                        playbackScrubTime = viewModel.currentPlaybackTime
                    }
                    .onChange(of: editorMode) {
                        cancelTimelineMarkerAutoScroll()
                        cancelTimelineScrubAutoScroll()
                        finishEffectFocusRegionDrawing()
                        isPlacingClickFocus = false
                        pendingMarkerDragSourcePoint = nil
                        resetClickPointPrecisionLoupe()
                        isDrawingNoZoomOverflowRegion = false
                        pendingNoZoomOverflowRegion = nil
                        activeTimelineMarkerDragID = nil
                        activeTimelineMarkerDragStartTime = nil
                        activeTimelineMarkerDragCursorX = nil
                        activeTimelineScrubCursorX = nil
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
        detailAccentColor
    }

    private var detailAccentColor: Color {
        let activeTab = selectedTab ?? .capture
        let accentRole = activeTab == .review ? editorMode.accentRole : activeTab.accentRole
        return FlowTrackAccent.color(for: accentRole)
    }

    private var flowTrackCommandContext: FlowTrackCommandContext {
        FlowTrackCommandContext(
            isHelpModeEnabled: isHelpModeEnabled,
            canZoomTimelineIn: canZoomTimelineInFromMenu,
            canZoomTimelineOut: canZoomTimelineOutFromMenu,
            canResetTimelineZoom: canResetTimelineZoomFromMenu,
            isTimelineScrubSnappingEnabled: isTimelineScrubSnappingEnabled,
            canUsePlayback: canUsePlaybackFromMenu,
            canJumpToStart: canUsePlaybackFromMenu,
            canNudgePlayheadByFrame: canNudgePlayheadByFrameFromMenu,
            canGoToPreviousMarker: previousMarkerNavigationTarget() != nil,
            canGoToNextMarker: nextMarkerNavigationTarget() != nil,
            canDeleteSelectedMarker: canDeleteSelectedMarkerFromMenu,
            canDuplicateSelectedMarker: canDuplicateSelectedMarkerFromMenu,
            toggleHelpMode: {
                isHelpModeEnabled.toggle()
            },
            zoomTimelineIn: {
                zoomTimelineFromMenu(by: 1.25)
            },
            zoomTimelineOut: {
                zoomTimelineFromMenu(by: 0.8)
            },
            resetTimelineZoom: {
                resetTimelineZoomFromMenu()
            },
            toggleTimelineScrubSnapping: {
                isTimelineScrubSnappingEnabled.toggle()
            },
            togglePlayback: {
                viewModel.togglePlayback()
            },
            jumpToStart: {
                viewModel.jumpPlaybackToStart()
            },
            nudgePlayheadBackwardOneFrame: {
                nudgePlayheadByFrame(-1)
            },
            nudgePlayheadForwardOneFrame: {
                nudgePlayheadByFrame(1)
            },
            goToPreviousMarker: {
                navigateToPreviousMarkerFromMenu()
            },
            goToNextMarker: {
                navigateToNextMarkerFromMenu()
            },
            deleteSelectedMarker: {
                deleteSelectedMarkerFromMenu()
            },
            duplicateSelectedMarker: {
                duplicateSelectedMarkerFromMenu()
            }
        )
    }

    private var timelineCommandDuration: Double? {
        guard (selectedTab ?? .capture) == .review,
              let duration = viewModel.recordingSummary?.duration,
              duration > 0.001 else {
            return nil
        }

        return duration
    }

    private var canZoomTimelineInFromMenu: Bool {
        guard let duration = timelineCommandDuration else { return false }
        return timelineZoomScale < timelineMaximumZoomScale(for: duration) - 0.0001
    }

    private var canZoomTimelineOutFromMenu: Bool {
        timelineCommandDuration != nil && timelineZoomScale > 1.0001
    }

    private var canResetTimelineZoomFromMenu: Bool {
        timelineCommandDuration != nil && (timelineZoomScale > 1.0001 || visibleTimelineStartTime > 0.0001)
    }

    private var canUsePlaybackFromMenu: Bool {
        (selectedTab ?? .capture) == .review && (viewModel.canUsePlaybackTransport || viewModel.isRenderedPreviewActive)
    }

    private var canNudgePlayheadByFrameFromMenu: Bool {
        canUsePlaybackFromMenu && timelineCommandDuration != nil
    }

    var timelineFrameDuration: Double {
        1.0 / 60.0
    }

    private var canDeleteSelectedMarkerFromMenu: Bool {
        guard (selectedTab ?? .capture) == .review else { return false }

        switch editorMode {
        case .zoomAndClicks:
            return viewModel.selectedZoomMarkerID != nil
        case .effects:
            return viewModel.selectedEffectMarkerID != nil
        }
    }

    private var canDuplicateSelectedMarkerFromMenu: Bool {
        (selectedTab ?? .capture) == .review &&
        editorMode == .zoomAndClicks &&
        viewModel.selectedZoomMarkerID != nil
    }

    private enum MarkerNavigationDirection {
        case previous
        case next
    }

    private enum MarkerNavigationTarget {
        case zoom(ZoomPlanItem)
        case effect(EffectPlanItem)

        var time: Double {
            switch self {
            case .zoom(let marker):
                return marker.sourceEventTimestamp
            case .effect(let marker):
                return marker.snapTime
            }
        }
    }

    private func zoomTimelineFromMenu(by factor: Double) {
        guard let duration = timelineCommandDuration else { return }

        let safeDuration = max(duration, 0.001)
        let currentRange = timelineVisibleRange(for: safeDuration)
        let centreTime = currentRange.startTime + (currentRange.duration / 2)
        let newZoomScale = clampedTimelineZoomScale(timelineZoomScale * factor, duration: safeDuration)
        let newVisibleDuration = safeDuration / newZoomScale

        timelineZoomScale = newZoomScale
        visibleTimelineStartTime = clampedTimelineStartTime(
            centreTime - (newVisibleDuration / 2),
            visibleDuration: newVisibleDuration,
            fullDuration: safeDuration
        )
    }

    private func resetTimelineZoomFromMenu() {
        timelineZoomScale = 1
        visibleTimelineStartTime = 0
    }

    private func nudgePlayheadByFrame(_ direction: Int) {
        guard let duration = timelineCommandDuration else { return }

        let targetTime = min(
            max(viewModel.currentPlaybackTime + (Double(direction) * timelineFrameDuration), 0),
            duration
        )
        viewModel.seekTimelineDirectly(
            to: targetTime,
            snappedMarkerID: nil,
            snappedEffectMarkerID: nil,
            suppressAutoSelectionWhenUnsnapped: true
        )
        revealTimelineTimeFromMenu(targetTime)
        flashPlayheadTimeDisplay()
    }

    private func flashPlayheadTimeDisplay() {
        playheadTimeNudgeFlashTask?.cancel()
        isPlayheadTimeNudgeFlashActive = true
        playheadTimeNudgeFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                isPlayheadTimeNudgeFlashActive = false
            }
            playheadTimeNudgeFlashTask = nil
        }
    }

    func updateTimelineScrubAutoScroll(cursorX: CGFloat, width: CGFloat, duration: Double) {
        guard isDraggingTimeline, activeTimelineMarkerDragID == nil else {
            cancelTimelineScrubAutoScroll()
            return
        }

        let safeWidth = max(width, 1)
        let safeDuration = max(duration, 0.001)
        let clampedCursorX = min(max(cursorX, 0), safeWidth)
        activeTimelineScrubCursorX = clampedCursorX
        activeTimelineScrubWidth = safeWidth
        activeTimelineScrubDuration = safeDuration

        guard timelineMarkerAutoScrollIntensity(cursorX: clampedCursorX, width: safeWidth) != nil,
              timelineVisibleRange(for: safeDuration).duration < safeDuration else {
            cancelTimelineScrubAutoScroll()
            return
        }

        guard timelineScrubAutoScrollTask == nil else { return }

        timelineScrubAutoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard tickTimelineScrubAutoScroll() else { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            timelineScrubAutoScrollTask = nil
        }
    }

    func cancelTimelineScrubAutoScroll() {
        timelineScrubAutoScrollTask?.cancel()
        timelineScrubAutoScrollTask = nil
    }

    private func tickTimelineScrubAutoScroll() -> Bool {
        guard isDraggingTimeline,
              activeTimelineMarkerDragID == nil,
              let cursorX = activeTimelineScrubCursorX,
              let edgeState = timelineMarkerAutoScrollIntensity(cursorX: cursorX, width: activeTimelineScrubWidth) else {
            return false
        }

        let safeDuration = max(activeTimelineScrubDuration, 0.001)
        let visibleRange = timelineVisibleRange(for: safeDuration)
        guard visibleRange.duration < visibleRange.fullDuration else { return false }

        let speed = visibleRange.duration * 0.75 * edgeState.intensity * edgeState.intensity
        let proposedStartTime = visibleTimelineStartTime + (edgeState.direction * speed / 60)
        let newStartTime = clampedTimelineStartTime(
            proposedStartTime,
            visibleDuration: visibleRange.duration,
            fullDuration: visibleRange.fullDuration
        )

        guard abs(newStartTime - visibleTimelineStartTime) > 0.0001 else { return false }

        visibleTimelineStartTime = newStartTime
        let updatedRange = timelineVisibleRange(for: safeDuration)
        viewModel.updateTimelineScrub(
            to: timelineTime(for: cursorX, width: activeTimelineScrubWidth, visibleRange: updatedRange),
            snappedMarkerID: nil,
            snappedEffectMarkerID: nil
        )
        return true
    }

    func beginTimelineMarkerDrag(
        marker: ZoomPlanItem,
        startX: CGFloat,
        width: CGFloat,
        duration: Double,
        visibleRange: TimelineVisibleRange
    ) {
        finishEffectFocusRegionDrawing()
        clearTimelineHover()
        isTimelineKeyboardFocused = true
        suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
        viewModel.selectZoomMarker(marker.id, seekPlaybackHead: false)
        activeTimelineMarkerDragID = marker.id
        activeTimelineMarkerDragStartTime = marker.sourceEventTimestamp
        activeTimelineMarkerDragTimeOffset = marker.sourceEventTimestamp - timelineTime(for: startX, width: width, visibleRange: visibleRange)
        activeTimelineMarkerDragCursorX = startX
        activeTimelineMarkerDragWidth = max(width, 1)
        activeTimelineMarkerDragDuration = max(duration, 0.001)
    }

    func updateTimelineMarkerDrag(
        cursorX: CGFloat,
        width: CGFloat,
        duration: Double
    ) {
        guard activeTimelineMarkerDragID != nil else { return }

        let safeWidth = max(width, 1)
        let safeDuration = max(duration, 0.001)
        let clampedCursorX = min(max(cursorX, 0), safeWidth)
        activeTimelineMarkerDragCursorX = clampedCursorX
        activeTimelineMarkerDragWidth = safeWidth
        activeTimelineMarkerDragDuration = safeDuration

        let visibleRange = timelineVisibleRange(for: safeDuration)
        let targetTime = timelineMarkerDragTime(
            cursorX: clampedCursorX,
            width: safeWidth,
            visibleRange: visibleRange
        )
        viewModel.updateSelectedTimelineMarkerDrag(to: targetTime)
        updateTimelineMarkerAutoScroll(cursorX: clampedCursorX, width: safeWidth, duration: safeDuration)
    }

    func finishTimelineMarkerDrag(
        cursorX: CGFloat,
        width: CGFloat,
        duration: Double
    ) {
        guard activeTimelineMarkerDragID != nil else { return }

        cancelTimelineMarkerAutoScroll()
        let safeWidth = max(width, 1)
        let safeDuration = max(duration, 0.001)
        let clampedCursorX = min(max(cursorX, 0), safeWidth)
        let visibleRange = timelineVisibleRange(for: safeDuration)
        let targetTime = timelineMarkerDragTime(
            cursorX: clampedCursorX,
            width: safeWidth,
            visibleRange: visibleRange
        )
        viewModel.commitSelectedTimelineMarkerDrag(to: targetTime)
        activeTimelineMarkerDragID = nil
        activeTimelineMarkerDragStartTime = nil
        activeTimelineMarkerDragCursorX = nil
    }

    private func timelineMarkerDragTime(
        cursorX: CGFloat,
        width: CGFloat,
        visibleRange: TimelineVisibleRange
    ) -> Double {
        min(
            max(timelineTime(for: cursorX, width: width, visibleRange: visibleRange) + activeTimelineMarkerDragTimeOffset, 0),
            visibleRange.fullDuration
        )
    }

    private func updateTimelineMarkerAutoScroll(cursorX: CGFloat, width: CGFloat, duration: Double) {
        guard activeTimelineMarkerDragID != nil,
              timelineMarkerAutoScrollIntensity(cursorX: cursorX, width: width) != nil,
              timelineVisibleRange(for: duration).duration < max(duration, 0.001) else {
            cancelTimelineMarkerAutoScroll()
            return
        }

        guard timelineMarkerAutoScrollTask == nil else { return }

        timelineMarkerAutoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard tickTimelineMarkerAutoScroll() else { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            timelineMarkerAutoScrollTask = nil
        }
    }

    private func cancelTimelineMarkerAutoScroll() {
        timelineMarkerAutoScrollTask?.cancel()
        timelineMarkerAutoScrollTask = nil
    }

    private func tickTimelineMarkerAutoScroll() -> Bool {
        guard activeTimelineMarkerDragID != nil,
              let cursorX = activeTimelineMarkerDragCursorX,
              let edgeState = timelineMarkerAutoScrollIntensity(cursorX: cursorX, width: activeTimelineMarkerDragWidth) else {
            return false
        }

        let safeDuration = max(activeTimelineMarkerDragDuration, 0.001)
        let visibleRange = timelineVisibleRange(for: safeDuration)
        guard visibleRange.duration < visibleRange.fullDuration else { return false }

        let speed = visibleRange.duration * 0.75 * edgeState.intensity * edgeState.intensity
        let proposedStartTime = visibleTimelineStartTime + (edgeState.direction * speed / 60)
        let newStartTime = clampedTimelineStartTime(
            proposedStartTime,
            visibleDuration: visibleRange.duration,
            fullDuration: visibleRange.fullDuration
        )

        guard abs(newStartTime - visibleTimelineStartTime) > 0.0001 else { return false }

        visibleTimelineStartTime = newStartTime
        let updatedRange = timelineVisibleRange(for: safeDuration)
        let targetTime = timelineMarkerDragTime(
            cursorX: cursorX,
            width: activeTimelineMarkerDragWidth,
            visibleRange: updatedRange
        )
        viewModel.updateSelectedTimelineMarkerDrag(to: targetTime)
        return true
    }

    private func timelineMarkerAutoScrollIntensity(cursorX: CGFloat, width: CGFloat) -> (direction: Double, intensity: Double)? {
        let safeWidth = max(width, 1)
        let edgeWidth = min(CGFloat(80), safeWidth / 3)
        guard edgeWidth > 0 else { return nil }

        if cursorX < edgeWidth {
            return (-1, Double((edgeWidth - max(cursorX, 0)) / edgeWidth))
        }

        if cursorX > safeWidth - edgeWidth {
            return (1, Double((min(cursorX, safeWidth) - (safeWidth - edgeWidth)) / edgeWidth))
        }

        return nil
    }

    private func previousMarkerNavigationTarget() -> MarkerNavigationTarget? {
        markerNavigationTarget(direction: .previous)
    }

    private func nextMarkerNavigationTarget() -> MarkerNavigationTarget? {
        markerNavigationTarget(direction: .next)
    }

    private func markerNavigationTarget(direction: MarkerNavigationDirection) -> MarkerNavigationTarget? {
        guard (selectedTab ?? .capture) == .review,
              let summary = viewModel.recordingSummary else {
            return nil
        }

        switch editorMode {
        case .zoomAndClicks:
            let markers = summary.zoomMarkers.sorted {
                if $0.sourceEventTimestamp == $1.sourceEventTimestamp {
                    return $0.id < $1.id
                }
                return $0.sourceEventTimestamp < $1.sourceEventTimestamp
            }
            guard !markers.isEmpty else { return nil }

            if let selectedMarkerID = viewModel.selectedZoomMarkerID,
               let selectedIndex = markers.firstIndex(where: { $0.id == selectedMarkerID }) {
                switch direction {
                case .previous:
                    guard selectedIndex > 0 else { return nil }
                    return .zoom(markers[selectedIndex - 1])
                case .next:
                    guard selectedIndex < markers.count - 1 else { return nil }
                    return .zoom(markers[selectedIndex + 1])
                }
            }

            switch direction {
            case .previous:
                return markers.last(where: { $0.sourceEventTimestamp < viewModel.currentPlaybackTime }).map(MarkerNavigationTarget.zoom)
            case .next:
                return markers.first(where: { $0.sourceEventTimestamp > viewModel.currentPlaybackTime }).map(MarkerNavigationTarget.zoom)
            }

        case .effects:
            let markers = summary.effectMarkers.sorted {
                if $0.snapTime == $1.snapTime {
                    return $0.id < $1.id
                }
                return $0.snapTime < $1.snapTime
            }
            guard !markers.isEmpty else { return nil }

            if let selectedMarkerID = viewModel.selectedEffectMarkerID,
               let selectedIndex = markers.firstIndex(where: { $0.id == selectedMarkerID }) {
                switch direction {
                case .previous:
                    guard selectedIndex > 0 else { return nil }
                    return .effect(markers[selectedIndex - 1])
                case .next:
                    guard selectedIndex < markers.count - 1 else { return nil }
                    return .effect(markers[selectedIndex + 1])
                }
            }

            switch direction {
            case .previous:
                return markers.last(where: { $0.snapTime < viewModel.currentPlaybackTime }).map(MarkerNavigationTarget.effect)
            case .next:
                return markers.first(where: { $0.snapTime > viewModel.currentPlaybackTime }).map(MarkerNavigationTarget.effect)
            }
        }
    }

    func navigateToPreviousMarkerFromMenu() {
        navigateToMarkerFromMenu(previousMarkerNavigationTarget())
    }

    func navigateToNextMarkerFromMenu() {
        navigateToMarkerFromMenu(nextMarkerNavigationTarget())
    }

    private func navigateToMarkerFromMenu(_ target: MarkerNavigationTarget?) {
        guard let target else { return }

        finishEffectFocusRegionDrawing()
        isTimelineKeyboardFocused = true
        revealTimelineTimeFromMenu(target.time)

        switch target {
        case .zoom(let marker):
            suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
            viewModel.selectZoomMarker(marker.id, seekPlaybackHead: true)
        case .effect(let marker):
            viewModel.selectEffectMarker(marker.id, seekPlaybackHead: true)
        }
    }

    private func revealTimelineTimeFromMenu(_ time: Double) {
        guard let duration = timelineCommandDuration else { return }

        let visibleRange = timelineVisibleRange(for: duration)
        guard visibleRange.duration < visibleRange.fullDuration else { return }

        let padding = min(visibleRange.duration * 0.15, max(visibleRange.duration / 2, 0))
        let leadingEdge = visibleRange.startTime + padding
        let trailingEdge = visibleRange.endTime - padding

        let proposedStartTime: Double
        if time < leadingEdge {
            proposedStartTime = time - padding
        } else if time > trailingEdge {
            proposedStartTime = time + padding - visibleRange.duration
        } else {
            return
        }

        visibleTimelineStartTime = clampedTimelineStartTime(
            proposedStartTime,
            visibleDuration: visibleRange.duration,
            fullDuration: visibleRange.fullDuration
        )
    }

    private func deleteSelectedMarkerFromMenu() {
        switch editorMode {
        case .zoomAndClicks:
            viewModel.deleteSelectedMarker()
        case .effects:
            viewModel.deleteSelectedEffectMarker()
        }
    }

    private func duplicateSelectedMarkerFromMenu() {
        guard editorMode == .zoomAndClicks else { return }
        viewModel.duplicateSelectedMarker()
    }

    func reviewHeaderActionIcon(_ systemName: String, action: ReviewHeaderAction) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(hoveredReviewHeaderAction == action ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Circle())
            .onHover { isHovered in
                hoveredReviewHeaderAction = isHovered ? action : nil
            }
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

}

struct SharingAnchorView: NSViewRepresentable {
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

enum ReviewHeaderAction {
    case info
    case inspector
    case export
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

    var accentRole: FlowTrackAccentRole {
        switch self {
        case .capture:
            return .capture
        case .library:
            return .library
        case .review:
            return .zoomAndClicks
        case .settings:
            return .settings
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
