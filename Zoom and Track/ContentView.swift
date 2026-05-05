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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var viewModel = CaptureSetupViewModel()
    @State var selectedTab: AppTab? = .capture
    @State private var playbackVideoHeightOverride: CGFloat?
    @State private var playbackVideoHeightDragOrigin: CGFloat?
    @State private var isPlaybackInspectorVisible = true
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
    @State private var hoveredTimelineMarkerID: String?
    @State private var hoveredEffectTimelineMarkerID: String?
    @State private var isDraggingTimeline = false
    @State var inspectorFocusedTimingPhase: MarkerTimingPhase?
    @State private var hoveredTimelinePhase: MarkerTimingPhase?
    @State private var hoveredTimelineTooltipAnchor: CGPoint?
    @State private var hoveredEffectTimelineTooltipAnchor: CGPoint?
    @State private var exportShareAnchorView: NSView?
    @State private var isPlacingClickFocus = false
    @State private var pendingMarkerDragSourcePoint: CGPoint?
    @State private var isDrawingNoZoomOverflowRegion = false
    @State private var pendingNoZoomOverflowRegion: NoZoomOverflowRegion?
    @State private var isDrawingEffectFocusRegion = false
    @State private var pendingEffectFocusRegion: EffectFocusRegion?
    @State private var effectFocusRegionInteractionBase: EffectFocusRegion?
    @State private var activeEffectRegionPrecisionPoint: CGPoint?
    @State private var activeEffectRegionHandle: EffectRegionHandle?
    @State private var activeTimelineMarkerDragID: String?
    @State private var activeTimelineMarkerDragStartTime: Double?
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
    @FocusState private var isTimelineKeyboardFocused: Bool

    private struct OverlayMapping {
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

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Settings",
                subtitle: "Capture location and permissions",
                accentWidth: 132
            )

            settingsCard(
                title: "Library Root",
                body: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.selectedOutputFolderPath ?? "Movies/FlowTrack Capture Library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Choose Library Root") {
                            viewModel.chooseOutputFolder()
                        }
                    }
                )
            )

            settingsCard(
                title: "Permissions",
                body: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            viewModel.hasScreenRecordingPermission ? "Screen Recording available" : "Screen Recording required",
                            systemImage: viewModel.hasScreenRecordingPermission ? "checkmark.shield" : "exclamationmark.shield"
                        )
                        Button("Request Permission") {
                            Task { await viewModel.requestPermission() }
                        }
                        Button("Reload Targets") {
                            Task { await viewModel.load() }
                        }
                    }
                )
            )

            settingsCard(
                title: "Capture Defaults",
                body: AnyView(
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New captures are saved into the selected library root using Collection and Project folders.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("No Zoom Overflow")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Picker("No Zoom Overflow", selection: Binding(
                                get: { viewModel.defaultNoZoomFallbackMode },
                                set: { viewModel.setDefaultNoZoomFallbackMode($0) }
                            )) {
                                ForEach(NoZoomFallbackMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                )
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func playbackVideoCard(
        mainPlayer: AVPlayer,
        previewPlayer: AVPlayer?,
        aspectRatio: CGFloat,
        selectedMarker: ZoomPlanItem?,
        selectedEffectMarker: EffectPlanItem?,
        contentCoordinateSize: CGSize,
        zoomMarkers: [ZoomPlanItem],
        effectMarkers: [EffectPlanItem],
        currentTime: Double,
        isRenderedPreviewActive: Bool,
        renderingStatusMessage: String?,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        playbackTransitionPlateState: CaptureSetupViewModel.PlaybackTransitionPlateState,
        isPlacingClickFocus: Bool,
        draggedMarkerSourcePoint: CGPoint?,
        isDrawingNoZoomOverflowRegion: Bool,
        pendingNoZoomOverflowRegion: NoZoomOverflowRegion?,
        isDrawingEffectFocusRegion: Bool,
        pendingEffectFocusRegion: EffectFocusRegion?,
        placeClickFocusAction: @escaping (CGPoint) -> Void,
        dragSelectedMarkerAction: @escaping (CGPoint) -> Void,
        commitDraggedMarkerAction: @escaping (CGPoint) -> Void,
        updateNoZoomOverflowRegionAction: @escaping (NoZoomOverflowRegion?) -> Void,
        updateEffectFocusRegionAction: @escaping (EffectFocusRegion?) -> Void
    ) -> some View {
        let safeAspectRatio = max(aspectRatio, 0.1)

        return ZStack {
            cardBackground

            GeometryReader { geometry in
                let fittedRect = fittedVideoRect(in: geometry.size, aspectRatio: safeAspectRatio)
                let isMarkerDragActive = draggedMarkerSourcePoint != nil
                let isOverflowRegionDrawActive = isDrawingNoZoomOverflowRegion
                let isEffectRegionDrawActive = isDrawingEffectFocusRegion
                let previewState = isRenderedPreviewActive
                    ? nil
                    : isMarkerDragActive
                    ? nil
                    : isOverflowRegionDrawActive
                    ? nil
                    : isEffectRegionDrawActive
                    ? nil
                    : activeZoomPreviewState(
                        at: currentTime,
                        zoomMarkers: zoomMarkers,
                        contentCoordinateSize: contentCoordinateSize
                    )
                let activeEffectState = isRenderedPreviewActive
                    ? nil
                    : isEffectRegionDrawActive
                    ? nil
                    : activeEffectPreviewState(
                        at: currentTime,
                        effectMarkers: effectMarkers
                    )

                ZStack {
                    PlaybackVideoSurface(player: mainPlayer)
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .scaleEffect(previewState?.scale ?? 1, anchor: .topLeading)
                        .offset(zoomPreviewOffset(for: previewState, in: fittedRect))
                        .blur(radius: playbackVideoHeightDragOrigin == nil ? 0 : 4)

                    if let activeEffectState,
                       activeEffectState.style == .blur || activeEffectState.style == .blurDarken,
                       let overlayRect = overlayRect(
                        for: activeEffectState.region,
                        contentCoordinateSize: contentCoordinateSize,
                        in: geometry.size,
                        videoAspectRatio: safeAspectRatio
                    ) {
                        effectBlurLayer(
                            mainPlayer: mainPlayer,
                            effectState: activeEffectState,
                            overlayRect: overlayRect,
                            fittedRect: fittedRect,
                            previewState: previewState
                        )
                    }

                    if let previewPlayer {
                        PlaybackVideoSurface(player: previewPlayer)
                            .frame(width: fittedRect.width, height: fittedRect.height)
                            .opacity(playbackPresentationMode == .playingRenderedPreview ? 1 : 0)
                            .animation(.easeInOut(duration: 0.16), value: playbackPresentationMode == .playingRenderedPreview)
                    }

                    if let activeEffectState,
                       let overlayRect = overlayRect(
                        for: activeEffectState.region,
                        contentCoordinateSize: contentCoordinateSize,
                        in: geometry.size,
                        videoAspectRatio: safeAspectRatio
                    ) {
                        effectPreviewOverlay(
                            effectState: activeEffectState,
                            overlayRect: overlayRect,
                            fittedRect: fittedRect,
                            previewState: previewState
                        )
                    }
                }
                .frame(width: fittedRect.width, height: fittedRect.height)
                .clipped()
                .position(x: fittedRect.midX, y: fittedRect.midY)
                .coordinateSpace(name: "videoOverlay")

                if !isRenderedPreviewActive,
                   !isOverflowRegionDrawActive,
                   let mapping = mappedOverlayPoint(
                    for: selectedMarker,
                    contentCoordinateSize: contentCoordinateSize,
                    in: geometry.size,
                    videoAspectRatio: safeAspectRatio
                ) {
                    let ringSize = 22 + max((selectedMarker?.zoomScale ?? 1.0) - 1.0, 0) * 10
                    let baseHandlePoint = draggedMarkerSourcePoint.flatMap {
                        overlayPoint(
                            for: $0,
                            contentCoordinateSize: contentCoordinateSize,
                            in: geometry.size,
                            videoAspectRatio: safeAspectRatio
                        )
                    } ?? mapping.point
                    let handlePoint = transformedOverlayPoint(
                        baseHandlePoint,
                        in: fittedRect,
                        previewState: previewState
                    )
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 3)
                            .frame(width: ringSize, height: ringSize)
                        Circle()
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 16, height: 16)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 18, height: 2)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 18)
                    }
                    .position(handlePoint)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                            .onChanged { value in
                                guard let sourcePoint = sourcePoint(
                                    for: value.location,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) else {
                                    return
                                }
                                dragSelectedMarkerAction(sourcePoint)
                            }
                            .onEnded { value in
                                guard let sourcePoint = sourcePoint(
                                    for: value.location,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) else {
                                    pendingMarkerDragSourcePoint = nil
                                    return
                                }
                                commitDraggedMarkerAction(sourcePoint)
                            }
                    )
                }

                if isPlacingClickFocus {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.viewfinder")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Click the video to place a Click Focus marker")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.62))
                            )
                        }
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                .onEnded { value in
                                    guard let sourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    placeClickFocusAction(sourcePoint)
                                }
                        )
                }

                if isOverflowRegionDrawActive {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.06))
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .overlay {
                            ZStack {
                                if let region = pendingNoZoomOverflowRegion ?? selectedMarker?.noZoomOverflowRegion,
                                   let overlayRect = overlayRect(
                                    for: region,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) {
                                    let cornerRadii = overflowRegionCornerRadii(
                                        for: overlayRect,
                                        within: fittedRect,
                                        baseRadius: CGFloat(max(selectedEffectMarker?.cornerRadius ?? 18, 0))
                                    )

                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.10))
                                        .frame(width: overlayRect.width, height: overlayRect.height)
                                        .overlay(
                                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                        )
                                        .position(x: overlayRect.midX - fittedRect.minX, y: overlayRect.midY - fittedRect.minY)
                                }

                                VStack(spacing: 8) {
                                    Image(systemName: "viewfinder.rectangular")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Drag to draw the Scale overflow region")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.62))
                                )
                                .padding(.top, 18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                .onChanged { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let currentSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateNoZoomOverflowRegionAction(
                                        noZoomOverflowRegion(
                                            from: startSourcePoint,
                                            to: currentSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                }
                                .onEnded { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let endSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateNoZoomOverflowRegionAction(
                                        noZoomOverflowRegion(
                                            from: startSourcePoint,
                                            to: endSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                }
                        )
                }

                if isEffectRegionDrawActive {
                    Rectangle()
                        .fill(Color.orange.opacity(0.06))
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .overlay {
                            ZStack {
                                if let region = pendingEffectFocusRegion ?? selectedEffectMarker?.focusRegion,
                                   let overlayRect = overlayRect(
                                    for: region,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) {
                                    let cornerRadii = overflowRegionCornerRadii(
                                        for: overlayRect,
                                        within: fittedRect,
                                        baseRadius: CGFloat(max(selectedEffectMarker?.cornerRadius ?? 18, 0))
                                    )

                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .fill(Color.orange.opacity(0.10))
                                        .frame(width: overlayRect.width, height: overlayRect.height)
                                        .overlay(
                                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                                .strokeBorder(Color.orange, lineWidth: 2)
                                        )
                                        .position(x: overlayRect.midX - fittedRect.minX, y: overlayRect.midY - fittedRect.minY)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                                .onChanged { value in
                                                    let baseRegion = effectFocusRegionInteractionBase ?? region
                                                    if effectFocusRegionInteractionBase == nil {
                                                        effectFocusRegionInteractionBase = baseRegion
                                                    }
                                                    activeEffectRegionHandle = nil
                                                    activeEffectRegionPrecisionPoint = CGPoint(
                                                        x: overlayRect.midX + value.translation.width,
                                                        y: overlayRect.midY + value.translation.height
                                                    )
                                                    let deltaX = (value.translation.width / max(fittedRect.width, 1)) * contentCoordinateSize.width
                                                    let deltaY = (value.translation.height / max(fittedRect.height, 1)) * contentCoordinateSize.height
                                                    updateEffectFocusRegionAction(
                                                        movedEffectFocusRegion(
                                                            baseRegion,
                                                            deltaX: deltaX,
                                                            deltaY: deltaY,
                                                            contentCoordinateSize: contentCoordinateSize
                                                        )
                                                    )
                                                }
                                                .onEnded { value in
                                                    let baseRegion = effectFocusRegionInteractionBase ?? region
                                                    activeEffectRegionHandle = nil
                                                    activeEffectRegionPrecisionPoint = CGPoint(
                                                        x: overlayRect.midX + value.translation.width,
                                                        y: overlayRect.midY + value.translation.height
                                                    )
                                                    let deltaX = (value.translation.width / max(fittedRect.width, 1)) * contentCoordinateSize.width
                                                    let deltaY = (value.translation.height / max(fittedRect.height, 1)) * contentCoordinateSize.height
                                                    updateEffectFocusRegionAction(
                                                        movedEffectFocusRegion(
                                                            baseRegion,
                                                            deltaX: deltaX,
                                                            deltaY: deltaY,
                                                            contentCoordinateSize: contentCoordinateSize
                                                        )
                                                    )
                                                    effectFocusRegionInteractionBase = nil
                                                    activeEffectRegionPrecisionPoint = nil
                                                }
                                        )

                                    ForEach(
                                        [
                                            EffectRegionHandle.topLeading,
                                            .topCenter,
                                            .topTrailing,
                                            .centerLeading,
                                            .centerTrailing,
                                            .bottomLeading,
                                            .bottomCenter,
                                            .bottomTrailing
                                        ],
                                        id: \.self
                                    ) { handle in
                                        let handlePoint = effectRegionHandlePoint(for: handle, in: overlayRect)

                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                                            )
                                            .position(x: handlePoint.x - fittedRect.minX, y: handlePoint.y - fittedRect.minY)
                                            .gesture(
                                                DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                                    .onChanged { value in
                                                        let baseRegion = effectFocusRegionInteractionBase ?? region
                                                        if effectFocusRegionInteractionBase == nil {
                                                            effectFocusRegionInteractionBase = baseRegion
                                                        }
                                                        activeEffectRegionHandle = handle
                                                        activeEffectRegionPrecisionPoint = nil
                                                        let resizePoint = CGPoint(
                                                            x: value.location.x + fittedRect.minX,
                                                            y: value.location.y + fittedRect.minY
                                                        )
                                                        updateEffectFocusRegionAction(
                                                            resizedEffectFocusRegion(
                                                                baseRegion,
                                                                dragging: handle,
                                                                to: resizePoint,
                                                                contentCoordinateSize: contentCoordinateSize,
                                                                in: geometry.size,
                                                                videoAspectRatio: safeAspectRatio
                                                            )
                                                        )
                                                    }
                                                    .onEnded { value in
                                                        let baseRegion = effectFocusRegionInteractionBase ?? region
                                                        activeEffectRegionHandle = nil
                                                        activeEffectRegionPrecisionPoint = nil
                                                        let resizePoint = CGPoint(
                                                            x: value.location.x + fittedRect.minX,
                                                            y: value.location.y + fittedRect.minY
                                                        )
                                                        updateEffectFocusRegionAction(
                                                            resizedEffectFocusRegion(
                                                                baseRegion,
                                                                dragging: handle,
                                                                to: resizePoint,
                                                                contentCoordinateSize: contentCoordinateSize,
                                                                in: geometry.size,
                                                                videoAspectRatio: safeAspectRatio
                                                            )
                                                        )
                                                        effectFocusRegionInteractionBase = nil
                                                        activeEffectRegionPrecisionPoint = nil
                                                    }
                                            )
                                    }
                                }

                                VStack(spacing: 8) {
                                    Image(systemName: "viewfinder.rectangular")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Drag to draw, move, or resize the Effect focus region")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.62))
                                )
                                .padding(.top, 18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                .onChanged { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let currentSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateEffectFocusRegionAction(
                                        effectFocusRegion(
                                            from: startSourcePoint,
                                            to: currentSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                    activeEffectRegionHandle = nil
                                    activeEffectRegionPrecisionPoint = value.location
                                }
                                .onEnded { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let endSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateEffectFocusRegionAction(
                                        effectFocusRegion(
                                            from: startSourcePoint,
                                            to: endSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                    effectFocusRegionInteractionBase = nil
                                    activeEffectRegionHandle = nil
                                    activeEffectRegionPrecisionPoint = nil
                                }
                        )
                }

                if isEffectRegionDrawActive,
                   let focusPoint = {
                       if let region = pendingEffectFocusRegion ?? selectedEffectMarker?.focusRegion,
                          let overlayRect = overlayRect(
                            for: region,
                            contentCoordinateSize: contentCoordinateSize,
                            in: geometry.size,
                            videoAspectRatio: safeAspectRatio
                          ),
                          let activeEffectRegionHandle {
                           return effectRegionHandlePoint(for: activeEffectRegionHandle, in: overlayRect)
                       }
                       return activeEffectRegionPrecisionPoint
                   }() {
                    effectRegionPrecisionLoupe(
                        player: mainPlayer,
                        fittedRect: fittedRect,
                        focusPoint: focusPoint
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 22)
                    .padding(.trailing, 22)
                    .allowsHitTesting(false)
                }
            }

            if let renderingStatusMessage {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(renderingStatusMessage)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.62))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }

            if playbackTransitionPlateState != .hidden {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    Rectangle()
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16))
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.18),
                            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.plusLighter)

                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 330)
                        .opacity(0.96)

                    if playbackPresentationMode == .previewCompletedSlate {
                        VStack {
                            Spacer()
                            Text("Choose another Zoom Marker from the list or use the transport controls below to play the entire timeline.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.bottom, 20)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .opacity(playbackTransitionPlateOpacity(for: playbackTransitionPlateState))
                .animation(
                    .easeInOut(duration: playbackTransitionPlateAnimationDuration(for: playbackTransitionPlateState)),
                    value: playbackTransitionPlateState
                )
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
        let duration = max(summary.duration ?? 0, 0.001)
        let segmentLayouts = timelineSegmentLayouts(for: summary.zoomMarkers, duration: duration)
        let effectLayouts = effectTimelineSegmentLayouts(for: summary.effectMarkers, duration: duration)
        let trackCenterY: CGFloat = 34
        let segmentOriginY: CGFloat = 16
        let hoveredTooltipEntry = hoveredTimelineTooltipEntry(in: summary)
        let hoveredEffectTooltipEntry = hoveredEffectTimelineTooltipEntry(in: summary)
        let timelineInteractionSuppressed = activeTimelineMarkerDragID != nil || NSEvent.modifierFlags.contains(.option)
        let selectedMarker = editorMode == .zoomAndClicks ? viewModel.selectedZoomMarker : nil
        let showsPulseControls = selectedMarker?.isClickFocus == true
        let showsNoZoomFallbackControls = selectedMarker?.zoomType == .noZoom

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ReviewEditorModeControlStrip(editorMode: editorMode) { mode in
                    editorMode = mode
                }
                Spacer()
                if editorMode == .zoomAndClicks {
                    timelineToolbar(
                        summary: summary,
                        selectedMarker: selectedMarker,
                        showsPulseControls: showsPulseControls,
                        showsNoZoomFallbackControls: showsNoZoomFallbackControls,
                        hasSelectedMarker: viewModel.selectedZoomMarkerID != nil,
                        canEditClickFocusMarkers: viewModel.canEditClickFocusMarkers,
                        isPlacingClickFocus: isPlacingClickFocus,
                        isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion,
                        onToggleAddClickFocus: {
                            if isPlacingClickFocus {
                                isPlacingClickFocus = false
                            } else {
                                viewModel.cancelPlaybackPreview()
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                pendingMarkerDragSourcePoint = nil
                                isPlacingClickFocus = true
                            }
                        },
                        onDeleteSelectedMarker: {
                            viewModel.deleteSelectedMarker()
                        },
                        onToggleClickPulse: {
                            guard let selectedMarker else { return }
                            viewModel.setSelectedMarkerClickPulseEnabled(!selectedMarker.isClickPulseEnabled)
                        },
                        onSelectClickPulsePreset: { preset in
                            viewModel.setSelectedMarkerClickPulsePreset(preset)
                        },
                        onSelectNoZoomFallbackMode: { mode in
                            if mode != .scale {
                                isDrawingNoZoomOverflowRegion = false
                            }
                            viewModel.setSelectedMarkerNoZoomFallbackMode(mode)
                        },
                        onToggleOverflowRegion: {
                            guard let selectedMarker else { return }
                            if isDrawingNoZoomOverflowRegion {
                                viewModel.setSelectedMarkerNoZoomOverflowRegion(
                                    pendingNoZoomOverflowRegion ?? selectedMarker.noZoomOverflowRegion
                                )
                                isDrawingNoZoomOverflowRegion = false
                            } else {
                                viewModel.cancelPlaybackPreview()
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                isPlacingClickFocus = false
                                pendingMarkerDragSourcePoint = nil
                                pendingNoZoomOverflowRegion = selectedMarker.noZoomOverflowRegion
                                isDrawingNoZoomOverflowRegion = true
                                isTimelineKeyboardFocused = true
                            }
                        }
                    )
                        .padding(.trailing, 18)
                } else {
                    EffectsTimelineToolbarView(
                        hasSelectedMarker: viewModel.selectedEffectMarkerID != nil,
                        selectedMarker: viewModel.selectedEffectMarker,
                        isDrawingFocusRegion: isDrawingEffectFocusRegion,
                        onAddMarker: {
                            viewModel.cancelPlaybackPreview()
                            inspectorMode = .markers
                            isPlaybackInspectorVisible = true
                            viewModel.addEffectMarker()
                        },
                        onDeleteSelectedMarker: {
                            viewModel.deleteSelectedEffectMarker()
                        },
                        onToggleFocusRegion: {
                            guard let selectedMarker = viewModel.selectedEffectMarker else { return }
                            if isDrawingEffectFocusRegion {
                                viewModel.setSelectedEffectFocusRegion(
                                    pendingEffectFocusRegion ?? selectedMarker.focusRegion
                                )
                                isDrawingEffectFocusRegion = false
                                effectFocusRegionInteractionBase = nil
                                activeEffectRegionPrecisionPoint = nil
                                activeEffectRegionHandle = nil
                            } else {
                                viewModel.cancelPlaybackPreview()
                                isPlacingClickFocus = false
                                pendingMarkerDragSourcePoint = nil
                                isDrawingNoZoomOverflowRegion = false
                                pendingNoZoomOverflowRegion = nil
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                pendingEffectFocusRegion = selectedMarker.focusRegion
                                effectFocusRegionInteractionBase = nil
                                activeEffectRegionPrecisionPoint = nil
                                activeEffectRegionHandle = nil
                                isDrawingEffectFocusRegion = true
                                isTimelineKeyboardFocused = true
                            }
                        }
                    )
                    .padding(.trailing, 18)
                }
                Text(timecodeString(for: viewModel.currentPlaybackTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 28)

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let playheadX = timelineX(for: viewModel.currentPlaybackTime, duration: duration, width: width)

                timelineCanvasView(
                    width: width,
                    duration: duration,
                    trackCenterY: trackCenterY,
                    segmentOriginY: segmentOriginY,
                    editorMode: editorMode,
                    segmentLayouts: segmentLayouts,
                    effectLayouts: effectLayouts,
                    timelineInteractionSuppressed: timelineInteractionSuppressed,
                    selectedZoomMarkerID: viewModel.selectedZoomMarkerID,
                    hoveredTimelineMarkerID: hoveredTimelineMarkerID,
                    hoveredTimelinePhase: hoveredTimelinePhase,
                    activeTimelineMarkerDragID: activeTimelineMarkerDragID,
                    isOptionModifierActive: NSEvent.modifierFlags.contains(.option),
                    hoveredTooltipMarker: hoveredTooltipEntry?.marker,
                    hoveredTooltipMarkerNumber: hoveredTooltipEntry?.markerNumber,
                    hoveredTooltipAnchor: hoveredTimelineTooltipAnchor,
                    hoveredEffectTimelineMarkerID: hoveredEffectTimelineMarkerID,
                    selectedEffectMarkerID: viewModel.selectedEffectMarkerID,
                    hoveredEffectTooltipMarker: hoveredEffectTooltipEntry?.marker,
                    hoveredEffectTooltipMarkerNumber: hoveredEffectTooltipEntry?.markerNumber,
                    hoveredEffectTooltipAnchor: hoveredEffectTimelineTooltipAnchor,
                    playheadX: playheadX,
                    isDraggingTimeline: isDraggingTimeline,
                    displayedPhaseProvider: { marker in
                        displayedTimelinePhase(for: marker)
                    },
                    zoomPlaybackHighlightProvider: { marker in
                        isMarkerPlaybackHighlighted(marker)
                    },
                    effectPlaybackHighlightProvider: { marker in
                        isEffectPlaybackHighlighted(marker)
                    },
                    onTimelineHoverChanged: { markerID, isHovering, phase, anchor in
                        if isHovering {
                            setTimelineHover(markerID: markerID, phase: phase, anchor: anchor)
                        } else if hoveredTimelineMarkerID == markerID {
                            clearTimelineHover()
                        }
                    },
                    onTimelineTap: { markerID in
                        isTimelineKeyboardFocused = true
                        suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                        viewModel.startMarkerPreview(markerID)
                    },
                    onTimelineOptionDragChanged: { markerID, translationX in
                        isTimelineKeyboardFocused = true
                        guard let layout = segmentLayouts.first(where: { $0.marker.id == markerID }) else { return }
                        if activeTimelineMarkerDragID == nil {
                            activeTimelineMarkerDragID = markerID
                            activeTimelineMarkerDragStartTime = layout.marker.sourceEventTimestamp
                            viewModel.beginTimelineMarkerMove(markerID)
                        }
                        guard activeTimelineMarkerDragID == markerID else { return }
                        let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                        let targetTime = startTime + (Double(translationX / width) * duration)
                        viewModel.previewTimelineMarkerMove(markerID, to: targetTime)
                    },
                    onTimelineOptionDragEnded: { markerID, translationX in
                        isTimelineKeyboardFocused = true
                        guard let layout = segmentLayouts.first(where: { $0.marker.id == markerID }) else { return }
                        guard activeTimelineMarkerDragID == markerID else { return }
                        let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                        let targetTime = startTime + (Double(translationX / width) * duration)
                        viewModel.commitTimelineMarkerMove(markerID, to: targetTime)
                        activeTimelineMarkerDragID = nil
                        activeTimelineMarkerDragStartTime = nil
                    },
                    onEffectHoverChanged: { markerID, isHovering, anchor in
                        guard editorMode == .effects else { return }
                        guard !timelineInteractionSuppressed else {
                            clearEffectTimelineHover()
                            return
                        }
                        if isHovering, let anchor {
                            setEffectTimelineHover(markerID: markerID, anchor: anchor)
                        } else if hoveredEffectTimelineMarkerID == markerID {
                            clearEffectTimelineHover()
                        }
                    },
                    onEffectSelect: { markerID in
                        viewModel.selectEffectMarker(markerID, seekPlaybackHead: true)
                    }
                )
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard activeTimelineMarkerDragID == nil else { return }
                            let currentX = min(max(value.location.x, 0), width)
                            let hasMovedEnough = abs(value.translation.width) > 3

                            if !isDraggingTimeline && hasMovedEnough {
                                isDraggingTimeline = true
                                viewModel.beginTimelineScrub()
                            }

                            if isDraggingTimeline {
                                let zoomSnap = editorMode == .zoomAndClicks
                                    ? timelineSnapTarget(at: currentX, width: width, duration: duration, markers: summary.zoomMarkers)
                                    : nil
                                let effectSnap = editorMode == .effects
                                    ? effectTimelineSnapTarget(at: currentX, width: width, duration: duration, markers: summary.effectMarkers)
                                    : nil
                                viewModel.updateTimelineScrub(
                                    to: zoomSnap?.time ?? effectSnap?.time ?? timelineTime(for: currentX, width: width, duration: duration),
                                    snappedMarkerID: zoomSnap?.marker.id,
                                    snappedEffectMarkerID: effectSnap?.marker.id
                                )
                            }
                        }
                        .onEnded { value in
                            guard activeTimelineMarkerDragID == nil else { return }
                            let endX = min(max(value.location.x, 0), width)
                            let zoomSnap = editorMode == .zoomAndClicks
                                ? timelineSnapTarget(at: endX, width: width, duration: duration, markers: summary.zoomMarkers)
                                : nil
                            let effectSnap = editorMode == .effects
                                ? effectTimelineSnapTarget(at: endX, width: width, duration: duration, markers: summary.effectMarkers)
                                : nil
                            let targetTime = zoomSnap?.time ?? effectSnap?.time ?? timelineTime(for: endX, width: width, duration: duration)

                            if isDraggingTimeline {
                                viewModel.endTimelineScrub(
                                    at: targetTime,
                                    snappedMarkerID: zoomSnap?.marker.id,
                                    snappedEffectMarkerID: effectSnap?.marker.id
                                )
                                isDraggingTimeline = false
                            } else if let zoomSnap {
                                isTimelineKeyboardFocused = true
                                suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                                viewModel.startMarkerPreview(zoomSnap.marker.id)
                            } else if let effectSnap {
                                isTimelineKeyboardFocused = true
                                viewModel.seekTimelineDirectly(
                                    to: targetTime,
                                    snappedMarkerID: nil,
                                    snappedEffectMarkerID: effectSnap.marker.id
                                )
                            } else {
                                viewModel.seekTimelineDirectly(
                                    to: targetTime,
                                    snappedMarkerID: nil,
                                    snappedEffectMarkerID: nil
                                )
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.12), value: isDraggingTimeline)
                .onHover { isHovering in
                    if !isHovering || timelineInteractionSuppressed {
                        clearTimelineHover()
                    }
                }
            }
            .frame(height: 60)

            timelineFooterView(
                duration: duration,
                editorMode: editorMode,
                isDrawingEffectFocusRegion: isDrawingEffectFocusRegion,
                isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion
            )
        }
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($isTimelineKeyboardFocused)
        .onKeyPress(.space) {
            guard viewModel.canUsePlaybackTransport || viewModel.isRenderedPreviewActive || viewModel.playbackPresentationMode == .previewCompletedSlate else {
                return .ignored
            }
            viewModel.togglePlayback()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { keyPress in
            if editorMode == .effects,
               let selectedMarker = viewModel.selectedEffectMarker,
               isDrawingEffectFocusRegion,
               let region = pendingEffectFocusRegion ?? selectedMarker.focusRegion {
                let nudgeDistance = keyPress.modifiers.contains(.option) ? 10.0 : 1.0
                let nudgedRegion: EffectFocusRegion?
                switch keyPress.key {
                case .leftArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: -nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .rightArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .upArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: 0, deltaY: -nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                case .downArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: 0, deltaY: nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                default:
                    nudgedRegion = nil
                }
                if let nudgedRegion {
                    pendingEffectFocusRegion = nudgedRegion
                    return .handled
                }
                return .ignored
            }

            if editorMode == .effects {
                guard viewModel.selectedEffectMarkerID != nil else { return .ignored }
                switch keyPress.key {
                case .leftArrow:
                    viewModel.nudgeSelectedEffectTimelineMarker(by: -1)
                    return .handled
                case .rightArrow:
                    viewModel.nudgeSelectedEffectTimelineMarker(by: 1)
                    return .handled
                default:
                    return .ignored
                }
            }

            guard editorMode == .zoomAndClicks else { return .ignored }
            guard viewModel.selectedZoomMarkerID != nil else { return .ignored }
            if isDrawingNoZoomOverflowRegion,
               let selectedMarker = viewModel.selectedZoomMarker,
               let region = pendingNoZoomOverflowRegion ?? selectedMarker.noZoomOverflowRegion {
                let nudgeDistance = keyPress.modifiers.contains(.option) ? 10.0 : 1.0
                let nudgedRegion: NoZoomOverflowRegion?
                switch keyPress.key {
                case .leftArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: -nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .rightArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .upArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: 0, deltaY: -nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                case .downArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: 0, deltaY: nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                default:
                    nudgedRegion = nil
                }
                if let nudgedRegion {
                    pendingNoZoomOverflowRegion = nudgedRegion
                    return .handled
                }
                return .ignored
            }
            switch keyPress.key {
            case .leftArrow:
                viewModel.nudgeSelectedTimelineMarker(by: -1)
                return .handled
            case .rightArrow:
                viewModel.nudgeSelectedTimelineMarker(by: 1)
                return .handled
            default:
                return .ignored
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    private func playbackInfoPopover(_ summary: RecordingInspectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.bundleName)
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), alignment: .leading),
                    GridItem(.flexible(minimum: 120), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                metadataItem("Bundle", summary.bundleName)
                metadataItem("Duration", summary.duration.map { String(format: "%.3f s", $0) } ?? "n/a")
                metadataItem("Events", "\(summary.totalEventCount)")
                metadataItem("Clicks", "\(summary.leftMouseDownCount + summary.rightMouseDownCount)")
                metadataItem("First Event", summary.firstEventTimestamp.map { String(format: "%.6f", $0) } ?? "n/a")
                metadataItem("Last Event", summary.lastEventTimestamp.map { String(format: "%.6f", $0) } ?? "n/a")
            }

            metadataItem("Path", summary.bundleURL.path, multiline: true)

            Button("Reveal in Finder") {
                viewModel.revealInFinder()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
    private func mappedOverlayPoint(
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

    private func settingsCard(title: String, body: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            body
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
        .background(cardBackground)
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

    private func setTimelineHover(markerID: String, phase: MarkerTimingPhase?, anchor: CGPoint) {
        hoveredTimelineMarkerID = markerID
        hoveredTimelinePhase = phase
        hoveredTimelineTooltipAnchor = anchor
        print("hover enter marker \(markerID)")
    }

    private func clearTimelineHover() {
        if let hoveredTimelineMarkerID {
            print("hover exit marker \(hoveredTimelineMarkerID)")
        }
        hoveredTimelineMarkerID = nil
        hoveredTimelinePhase = nil
        hoveredTimelineTooltipAnchor = nil
    }

    private func setEffectTimelineHover(markerID: String, anchor: CGPoint) {
        hoveredEffectTimelineMarkerID = markerID
        hoveredEffectTimelineTooltipAnchor = anchor
    }

    private func clearEffectTimelineHover() {
        hoveredEffectTimelineMarkerID = nil
        hoveredEffectTimelineTooltipAnchor = nil
    }

    private func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
        guard let hoveredTimelineMarkerID else { return nil }
        guard let entry = summary.zoomMarkers.enumerated().first(where: { $0.element.id == hoveredTimelineMarkerID }) else {
            return nil
        }
        print("hovered id = \(hoveredTimelineMarkerID)")
        print("resolved tooltip id = \(entry.element.id)")
        return (entry.element, entry.offset + 1)
    }

    private func hoveredEffectTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: EffectPlanItem, markerNumber: Int)? {
        guard let hoveredEffectTimelineMarkerID else { return nil }
        let displayedMarkers = displayedEffectMarkerList(summary.effectMarkers)
        guard let entry = displayedMarkers.enumerated().first(where: { $0.element.id == hoveredEffectTimelineMarkerID }) else {
            return nil
        }
        return (entry.element, entry.offset + 1)
    }

    private func displayedTimelinePhase(for marker: ZoomPlanItem) -> MarkerTimingPhase? {
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

struct MarkerListTableView: NSViewRepresentable {
    let entries: [MarkerListEntry]
    let selectedMarkerID: String?
    let onSelectMarker: (String) -> Void
    let onToggleMarkerEnabled: (String) -> Void
    let onReorderMarkers: ([String]) -> Void
    @Binding var renamingMarkerID: String?
    @Binding var markerNameDraft: String
    let onBeginRename: (ZoomPlanItem) -> Void
    let onCommitRename: (String, String) -> Void
    let onCancelRename: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = MarkerListNativeTableView()
        tableView.headerView = nil
        tableView.rowHeight = 76
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.style = .plain
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.registerForDraggedTypes([.string])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.handleTableViewAction(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MarkerColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refreshTableIfNeeded()
        context.coordinator.syncSelection()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: MarkerListTableView
        weak var tableView: NSTableView?
        private var isProgrammaticSelectionChange = false
        private var draggedMarkerID: String?
        private var lastRenderedEntryIDs: [String] = []
        private var lastRenderedSelectionID: String?
        private var lastRenderedHighlightSignature: String = ""
        private var lastRenderedRenamingMarkerID: String?

        init(parent: MarkerListTableView) {
            self.parent = parent
        }

        @objc
        func handleTableViewAction(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < parent.entries.count else { return }
            if let renamingMarkerID = parent.renamingMarkerID {
                parent.onCommitRename(renamingMarkerID, parent.markerNameDraft)
            }
            parent.onSelectMarker(parent.entries[row].id)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.entries.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            76
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("MarkerListHostingCellView")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MarkerListHostingCellView) ?? MarkerListHostingCellView(identifier: identifier)
            let entry = parent.entries[row]
            cell.update(
                rootView: MarkerListCellContent(
                    entry: entry,
                    onToggleEnabled: { [weak self] in
                        self?.parent.onToggleMarkerEnabled(entry.id)
                    },
                    renamingMarkerID: parent.$renamingMarkerID,
                    markerNameDraft: parent.$markerNameDraft,
                    onBeginRename: { [weak self] in
                        self?.parent.onBeginRename(entry.marker)
                    },
                    onCommitRename: { [weak self] name in
                        self?.parent.onCommitRename(entry.id, name)
                    },
                    onCancelRename: { [weak self] in
                        self?.parent.onCancelRename()
                    }
                )
            )
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isProgrammaticSelectionChange,
                  let tableView,
                  tableView.selectedRow >= 0,
                  tableView.selectedRow < parent.entries.count else {
                return
            }

            if let renamingMarkerID = parent.renamingMarkerID {
                parent.onCommitRename(renamingMarkerID, parent.markerNameDraft)
            }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < parent.entries.count else { return nil }
            let markerID = parent.entries[row].id
            draggedMarkerID = markerID
            let item = NSPasteboardItem()
            item.setString(markerID, forType: .string)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let markerIDs = parent.entries.map(\.id)
            guard let draggedMarkerID = draggedMarkerID ?? info.draggingPasteboard.string(forType: .string),
                  let fromIndex = markerIDs.firstIndex(of: draggedMarkerID) else {
                return false
            }

            var reordered = markerIDs
            let draggedID = reordered.remove(at: fromIndex)
            let insertionIndex = max(0, min(row > fromIndex ? row - 1 : row, reordered.count))
            reordered.insert(draggedID, at: insertionIndex)
            parent.onReorderMarkers(reordered)
            self.draggedMarkerID = nil
            return true
        }

        func syncSelection() {
            guard let tableView else { return }
            let targetRow = parent.entries.firstIndex { $0.id == parent.selectedMarkerID } ?? -1
            if tableView.selectedRow != targetRow {
                isProgrammaticSelectionChange = true
                if targetRow >= 0 {
                    tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
                    tableView.scrollRowToVisible(targetRow)
                } else {
                    tableView.deselectAll(nil)
                }
                isProgrammaticSelectionChange = false
            } else if targetRow >= 0 {
                tableView.scrollRowToVisible(targetRow)
            }
        }

        func refreshTableIfNeeded() {
            guard let tableView else { return }

            let entryIDs = parent.entries.map(\.id)
            let selectionID = parent.selectedMarkerID
            let highlightSignature = parent.entries.map { "\($0.id):\($0.isSelected):\($0.isPlaybackHighlighted):\($0.marker.markerName ?? ""):\($0.marker.enabled)" }.joined(separator: "|")
            let renamingMarkerID = parent.renamingMarkerID

            let shouldReload: Bool
            if let renamingMarkerID, renamingMarkerID == lastRenderedRenamingMarkerID {
                shouldReload = false
            } else {
                shouldReload =
                    entryIDs != lastRenderedEntryIDs ||
                    selectionID != lastRenderedSelectionID ||
                    highlightSignature != lastRenderedHighlightSignature ||
                    renamingMarkerID != lastRenderedRenamingMarkerID
            }

            if shouldReload {
                tableView.reloadData()
                lastRenderedEntryIDs = entryIDs
                lastRenderedSelectionID = selectionID
                lastRenderedHighlightSignature = highlightSignature
                lastRenderedRenamingMarkerID = renamingMarkerID
            }
        }
    }
}

private struct MarkerListCellContent: View {
    let entry: MarkerListEntry
    let onToggleEnabled: () -> Void
    @Binding var renamingMarkerID: String?
    @Binding var markerNameDraft: String
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void
    @FocusState private var isNameFieldFocused: Bool
    @State private var isRenameButtonHovered = false

    var body: some View {
        let marker = entry.marker
        let resolvedMarkerName = (marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (marker.markerName ?? "")
            : "Unnamed Marker"
        let isRenaming = renamingMarkerID == entry.id
        let backgroundFill: Color = entry.isPlaybackHighlighted
            ? Color.accentColor.opacity(0.20)
            : entry.isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.clear
        let strokeColor: Color = entry.isPlaybackHighlighted
            ? Color.accentColor.opacity(0.55)
            : entry.isSelected
            ? Color.accentColor.opacity(0.35)
            : Color.secondary.opacity(0.08)

        HStack(alignment: .top, spacing: 10) {
            dragGrip

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(timecodeString(marker.sourceEventTimestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 88, alignment: .leading)
                    Spacer(minLength: 0)
                    Button(action: onToggleEnabled) {
                        HStack(spacing: 4) {
                            Image(systemName: marker.enabled ? "checkmark.circle.fill" : "circle")
                            Text(marker.enabled ? "On" : "Off")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(marker.enabled ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    if isRenaming {
                        TextField("", text: $markerNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                            )
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                onCommitRename(markerNameDraft)
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    isNameFieldFocused = true
                                }
                            }
                    } else {
                        Text(resolvedMarkerName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }

                    Button {
                        if !isRenaming {
                            onBeginRename()
                        }
                    } label: {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isRenameButtonHovered ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        isRenameButtonHovered = isHovered
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    Label {
                        Text(String(format: "%.1fx", marker.zoomScale))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "viewfinder.rectangular")
                    }

                    Label {
                        Text(String(format: "%.2fs", marker.totalSegmentDuration))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "timer")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if entry.isPlaybackHighlighted {
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .opacity(marker.enabled ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onChange(of: isNameFieldFocused) { _, isFocused in
            guard isRenaming, !isFocused else { return }
            onCommitRename(markerNameDraft)
        }
    }

    private var dragGrip: some View {
        HStack(spacing: 3) {
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.65))
                        .frame(width: 2.5, height: 2.5)
                }
            }
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.65))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    private func timecodeString(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let totalFrames = Int(clampedSeconds * 30)
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let secs = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }
}

private final class MarkerListHostingCellView: NSTableCellView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setFrameSize(.zero)
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: MarkerListCellContent) {
        hostingView.rootView = AnyView(rootView)
    }
}

private final class MarkerListNativeTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}

private struct MarkerListReorderDropDelegate: DropDelegate {
    let targetMarkerID: String
    @Binding var previewOrder: [String]?
    @Binding var draggedMarkerID: String?
    @Binding var dropTargetMarkerID: String?
    let reorderAction: ([String]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedMarkerID, draggedMarkerID != targetMarkerID else { return }
        dropTargetMarkerID = targetMarkerID
        guard var previewOrder,
              let fromIndex = previewOrder.firstIndex(of: draggedMarkerID),
              let toIndex = previewOrder.firstIndex(of: targetMarkerID),
              fromIndex != toIndex else { return }

        let draggedID = previewOrder.remove(at: fromIndex)
        previewOrder.insert(draggedID, at: toIndex)
        self.previewOrder = previewOrder
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if draggedMarkerID != targetMarkerID {
            dropTargetMarkerID = targetMarkerID
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedMarkerID, draggedMarkerID != targetMarkerID else {
            self.draggedMarkerID = nil
            dropTargetMarkerID = nil
            previewOrder = nil
            return false
        }

        guard let previewOrder else {
            self.draggedMarkerID = nil
            dropTargetMarkerID = nil
            return false
        }

        reorderAction(previewOrder)
        self.draggedMarkerID = nil
        dropTargetMarkerID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.previewOrder = nil
        }
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [UTType.text]), dropTargetMarkerID == targetMarkerID {
            dropTargetMarkerID = nil
        }
    }
}

private struct PlaybackVideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.controlsStyle = .none
        nsView.videoGravity = .resizeAspect
    }
}

struct PlaybackVideoLayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.player = player
    }
}

final class PlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
struct PrecisionTimeField: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let action: (Double) -> Void
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(value: value, range: range, action: action, onBeginEditing: onBeginEditing, onEndEditing: onEndEditing)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .right
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        textField.formatter = nil
        textField.stringValue = context.coordinator.displayString(for: value)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.range = range
        context.coordinator.action = action
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onEndEditing = onEndEditing

        if !context.coordinator.isEditing {
            nsView.stringValue = context.coordinator.displayString(for: value)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var originalValue: Double
        var range: ClosedRange<Double>
        var action: (Double) -> Void
        var onBeginEditing: () -> Void
        var onEndEditing: () -> Void
        var isEditing = false

        init(
            value: Double,
            range: ClosedRange<Double>,
            action: @escaping (Double) -> Void,
            onBeginEditing: @escaping () -> Void,
            onEndEditing: @escaping () -> Void
        ) {
            self.originalValue = value
            self.range = range
            self.action = action
            self.onBeginEditing = onBeginEditing
            self.onEndEditing = onEndEditing
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            onBeginEditing()
            if let textField = obj.object as? NSTextField {
                originalValue = parsedValue(from: textField.stringValue) ?? originalValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commit(from: control)
                control.window?.makeFirstResponder(nil)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancel(on: control)
                control.window?.makeFirstResponder(nil)
                return true
            }

            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            commit(from: textField)
            isEditing = false
            onEndEditing()
        }

        private func commit(from control: NSControl) {
            guard let textField = control as? NSTextField else { return }
            let parsed = parsedValue(from: textField.stringValue) ?? originalValue
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            textField.stringValue = displayString(for: clamped)
            originalValue = clamped
            action(clamped)
        }

        private func cancel(on control: NSControl) {
            guard let textField = control as? NSTextField else { return }
            textField.stringValue = displayString(for: originalValue)
            isEditing = false
        }

        func displayString(for value: Double) -> String {
            String(format: "%.2f", value)
        }

        private func parsedValue(from string: String) -> Double? {
            let cleaned = string.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
    }
}
