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
    @StateObject private var viewModel = CaptureSetupViewModel()
    @State private var selectedTab: AppTab? = .capture
    @State private var playbackVideoHeightOverride: CGFloat?
    @State private var playbackVideoHeightDragOrigin: CGFloat?
    @State private var isPlaybackInspectorVisible = true
    @State private var isPlaybackInfoPresented = false
    @State private var playbackScrubTime = 0.0
    @State private var isScrubbingPlayback = false
    @State private var suppressMarkerListAutoScrollUntil: Date?
    @State private var draggedMarkerListID: String?
    @State private var markerListDropTargetID: String?
    @State private var markerListPreviewOrder: [String]?
    @State private var renamingMarkerID: String?
    @State private var markerNameDraft: String = ""
    @State private var renamingEffectMarkerID: String?
    @State private var effectMarkerNameDraft: String = ""
    @State private var hoveredTimelineMarkerID: String?
    @State private var isDraggingTimeline = false
    @State private var inspectorFocusedTimingPhase: MarkerTimingPhase?
    @State private var hoveredTimelinePhase: MarkerTimingPhase?
    @State private var hoveredTimelineTooltipAnchor: CGPoint?
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
    @State private var librarySearchText = ""
    @State private var editorMode: ReviewEditorMode = .zoomAndClicks
    @State private var inspectorMode: EditInspectorMode = .markers
    @State private var selectedLibraryCollectionFilter: String?
    @State private var selectedLibraryProjectFilter: String?
    @State private var selectedLibraryTypeFilter: CaptureType?
    @State private var captureInfoTitleDraft = ""
    @State private var captureInfoCollectionDraft = ""
    @State private var captureInfoProjectDraft = ""
    @FocusState private var focusedCaptureInfoField: CaptureInfoField?
    @FocusState private var isTimelineKeyboardFocused: Bool

    private struct OverlayMapping {
        let point: CGPoint
        let fittedRect: CGRect
        let sourceSize: CGSize
        let sourcePoint: CGPoint
        let rawPoint: CGPoint?
        let captureSourceLabel: String
    }

    private struct ZoomPreviewState {
        let scale: CGFloat
        let normalizedPoint: CGPoint
    }

    private struct EffectPreviewState {
        let style: EffectStyle
        let region: EffectFocusRegion
        let blurIntensity: Double
        let darkenIntensity: Double
        let tintIntensity: Double
        let cornerRadius: CGFloat
        let feather: CGFloat
        let tintColor: Color
    }

    private enum EffectRegionHandle: Hashable {
        case topLeading
        case topCenter
        case topTrailing
        case centerLeading
        case centerTrailing
        case bottomLeading
        case bottomCenter
        case bottomTrailing
    }

    private struct ZoomStateEvent {
        let marker: ZoomPlanItem
        let normalizedPoint: CGPoint
        let scale: CGFloat
    }

    private enum MotionDirection {
        case entering
        case exiting
    }

    private struct MotionProgressSample {
        let scale: Double
        let pan: Double
    }

    private struct TimelineSegmentLayout: Identifiable {
        let marker: ZoomPlanItem
        let markerNumber: Int
        let lane: Int
        let startRatio: Double
        let eventRatio: Double
        let endRatio: Double

        var id: String { marker.id }
    }

private enum MarkerTimingPhase: String {
        case leadIn = "Motion to Click Offset"
        case zoomIn = "Zoom In"
        case hold = "Hold"
        case zoomOut = "Zoom Out"
    }

    private enum CaptureInfoField: Hashable {
        case title
        case collection
        case project
    }

    private enum MotionTuning {
        static let bounceApproachFraction = 0.82
        static let bounceMaxOvershoot = 0.14
        static let bounceMinOvershoot = 0.04
        static let bounceOscillationCount = 2.6
        static let panBounceInfluence = 0.35
    }

    private struct LibraryFilterOption: Identifiable {
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

    private var captureView: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Capture",
                subtitle: viewModel.selectedOutputFolderPath ?? "Choose a library root",
                accentWidth: 132
            )

            GeometryReader { geometry in
                let useVerticalLayout = geometry.size.width < 980

                Group {
                    if useVerticalLayout {
                        VStack(alignment: .leading, spacing: 22) {
                            captureTargetCard
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 320, maxHeight: .infinity, alignment: .topLeading)

                            recordingSetupCard
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            captureTargetCard
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            recordingSetupCard
                                .frame(width: 330)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var captureTargetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capture Target")
                .font(.system(size: 16, weight: .semibold))

            Text("Choose one display or window")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    targetSection(title: "Displays", targets: viewModel.displays)
                    targetSection(title: "Windows", targets: viewModel.windows)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var recordingSetupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Setup")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Collection")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Default Collection", text: $viewModel.collectionName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("General Project", text: $viewModel.projectName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Type")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("Type", selection: $viewModel.captureType) {
                        ForEach(CaptureType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Short Description of Clip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Describe this capture", text: $viewModel.captureTitle)
                        .textFieldStyle(.roundedBorder)
                }
            }

            infoRow(
                title: "Permission",
                value: viewModel.hasScreenRecordingPermission ? "Screen Recording Enabled" : "Screen Recording Required"
            )

            infoRow(
                title: "Selected Target",
                value: viewModel.selectedTarget?.displayTitle ?? "None selected"
            )

            infoRow(
                title: "Output Folder",
                value: viewModel.selectedOutputFolderPath ?? "Movies/FlowTrack Capture Library"
            )

            ViewThatFits {
                HStack(spacing: 10) {
                    Button("Reload Targets") {
                        Task { await viewModel.load() }
                    }
                    Button("Choose Output Folder") {
                        viewModel.chooseOutputFolder()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("Reload Targets") {
                        Task { await viewModel.load() }
                    }
                    Button("Choose Output Folder") {
                        viewModel.chooseOutputFolder()
                    }
                }
            }

            Divider()

            if viewModel.canStopRecording || viewModel.sessionState == .stopping {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.sessionState == .stopping ? "Stopping Recording" : "Recording")
                        .font(.headline)
                    Text(viewModel.activeRecordingTargetName ?? "No target")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if let recordingStartedAt = viewModel.recordingStartedAt {
                        HStack {
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                                Text(timecodeString(since: recordingStartedAt, now: context.date))
                                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 176, alignment: .center)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black.opacity(0.88))
                                    )
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready to Record")
                        .font(.headline)
                    Text("Select a display or window to begin.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(viewModel.canStopRecording || viewModel.sessionState == .stopping ? "Stop Recording" : "Start Recording") {
                    if viewModel.canStopRecording || viewModel.sessionState == .stopping {
                        Task { await viewModel.stopRecording() }
                    } else {
                        Task { await viewModel.startRecording() }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(viewModel.canStopRecording || viewModel.sessionState == .stopping ? .white : accentContrastingTextColor())
                .frame(width: 190, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(viewModel.canStopRecording || viewModel.sessionState == .stopping ? Color.red : Color.accentColor)
                )
                .opacity(primaryButtonEnabled ? 1.0 : 0.45)
                .disabled(!primaryButtonEnabled)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var primaryButtonEnabled: Bool {
        if viewModel.canStopRecording || viewModel.sessionState == .stopping {
            return viewModel.canStopRecording
        }
        return viewModel.canStartRecording
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

    private var libraryView: some View {
        let filteredItems = filteredLibraryItems
        let resultSummary = "\(filteredItems.count) capture" + (filteredItems.count == 1 ? "" : "s")

        return VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Library",
                subtitle: viewModel.selectedOutputFolderPath ?? "Managed captures by Collection and Project",
                accentWidth: 132
            )

            HStack(spacing: 12) {
                librarySearchField
            }

            if let libraryStatusMessage = viewModel.libraryStatusMessage, !libraryStatusMessage.isEmpty {
                Text(libraryStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text(resultSummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if hasActiveLibraryFilters {
                            Button("Reset Filters") {
                                clearLibraryFilters()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12, weight: .medium))
                        }
                    }

                    if hasActiveLibraryFilters {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if let selectedLibraryCollectionFilter {
                                    activeLibraryFilterChip(title: selectedLibraryCollectionFilter) {
                                        self.selectedLibraryCollectionFilter = nil
                                    }
                                }
                                if let selectedLibraryProjectFilter {
                                    activeLibraryFilterChip(title: selectedLibraryProjectFilter) {
                                        self.selectedLibraryProjectFilter = nil
                                    }
                                }
                                if let selectedLibraryTypeFilter {
                                    activeLibraryFilterChip(title: selectedLibraryTypeFilter.displayName) {
                                        self.selectedLibraryTypeFilter = nil
                                    }
                                }
                            }
                        }
                    }

                    if filteredItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No captures match current filters")
                                .font(.headline)
                            Text(hasActiveLibraryFilters ? "Try clearing one or more filters." : "Create a capture or adjust the library root in Settings.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(cardBackground)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(filteredItems) { item in
                                    libraryCaptureRow(item)
                                }
                            }
                            .padding(16)
                        }
                        .background(cardBackground)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                libraryFilterRail
                    .frame(width: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredLibraryItems: [CaptureLibraryItem] {
        viewModel.libraryItems.filter { item in
            matchesLibrarySearch(item)
            && matchesLibraryCollectionFilter(item)
            && matchesLibraryProjectFilter(item)
            && matchesLibraryTypeFilter(item)
        }
    }

    private func libraryCaptureRow(_ item: CaptureLibraryItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))

                Text("\(item.collectionName) • \(item.projectName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.revealLibraryCapture(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.forward.folder.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reveal in Finder")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                HStack(spacing: 10) {
                    libraryMetadataPill(text: item.captureType.displayName, systemName: "tag")
                    libraryMetadataPill(
                        text: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                        systemName: "calendar"
                    )
                    if let duration = item.duration {
                        libraryMetadataPill(
                            text: String(format: "%.2fs", duration),
                            systemName: "timer"
                        )
                    }
                }

                if !item.isAvailable, let statusMessage = item.statusMessage {
                    Label("\(item.status.displayName) • \(statusMessage)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    viewModel.openLibraryCapture(item)
                    selectedTab = .review
                } label: {
                    Label("Edit Screen Capture", systemImage: "play.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(accentContrastingTextColor())
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .opacity(item.canOpenInEditor ? 1 : 0.45)
                .disabled(!item.canOpenInEditor)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search captures", text: $librarySearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !librarySearchText.isEmpty {
                Button {
                    librarySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func libraryMetadataPill(text: String, systemName: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
    }

    private var hasActiveLibraryFilters: Bool {
        selectedLibraryCollectionFilter != nil || selectedLibraryProjectFilter != nil || selectedLibraryTypeFilter != nil
    }

    private func matchesLibrarySearch(_ item: CaptureLibraryItem) -> Bool {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [
            item.title,
            item.collectionName,
            item.projectName,
            item.captureType.displayName
        ].joined(separator: " ").localizedLowercase
        return haystack.contains(query.localizedLowercase)
    }

    private func matchesLibraryCollectionFilter(_ item: CaptureLibraryItem) -> Bool {
        guard let selectedLibraryCollectionFilter else { return true }
        return item.collectionName == selectedLibraryCollectionFilter
    }

    private func matchesLibraryProjectFilter(_ item: CaptureLibraryItem) -> Bool {
        guard let selectedLibraryProjectFilter else { return true }
        return item.projectName == selectedLibraryProjectFilter
    }

    private func matchesLibraryTypeFilter(_ item: CaptureLibraryItem) -> Bool {
        guard let selectedLibraryTypeFilter else { return true }
        return item.captureType == selectedLibraryTypeFilter
    }

    private var libraryFilterRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Drill Down")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if hasActiveLibraryFilters {
                        Button("Reset") {
                            clearLibraryFilters()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .medium))
                    }
                }

                libraryFilterSection(
                    title: "Collections",
                    options: libraryCollectionOptions,
                    selectedValue: selectedLibraryCollectionFilter,
                    action: toggleLibraryCollectionFilter
                )

                libraryFilterSection(
                    title: "Projects",
                    options: libraryProjectOptions,
                    selectedValue: selectedLibraryProjectFilter,
                    action: toggleLibraryProjectFilter
                )

                libraryTypeSection
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var libraryCollectionOptions: [LibraryFilterOption] {
        buildLibraryFilterOptions(
            from: viewModel.libraryItems.filter { item in
                matchesLibrarySearch(item)
                && matchesLibraryProjectFilter(item)
                && matchesLibraryTypeFilter(item)
            },
            value: \.collectionName
        )
    }

    private var libraryProjectOptions: [LibraryFilterOption] {
        buildLibraryFilterOptions(
            from: viewModel.libraryItems.filter { item in
                matchesLibrarySearch(item)
                && matchesLibraryCollectionFilter(item)
                && matchesLibraryTypeFilter(item)
            },
            value: \.projectName
        )
    }

    private var libraryTypeOptions: [CaptureType: Int] {
        let items = viewModel.libraryItems.filter { item in
            matchesLibrarySearch(item)
            && matchesLibraryCollectionFilter(item)
            && matchesLibraryProjectFilter(item)
        }
        return Dictionary(items.map { ($0.captureType, 1) }, uniquingKeysWith: +)
    }

    private func buildLibraryFilterOptions(
        from items: [CaptureLibraryItem],
        value: KeyPath<CaptureLibraryItem, String>
    ) -> [LibraryFilterOption] {
        let counts = Dictionary(items.map { ($0[keyPath: value], 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { key in
            LibraryFilterOption(label: key, count: counts[key] ?? 0)
        }
    }

    private func libraryFilterSection(
        title: String,
        options: [LibraryFilterOption],
        selectedValue: String?,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if options.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(options) { option in
                        Button {
                            action(option.label)
                        } label: {
                            HStack(spacing: 10) {
                                Text(option.label)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(option.count)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12, weight: selectedValue == option.label ? .semibold : .medium))
                            .foregroundStyle(selectedValue == option.label ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedValue == option.label ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selectedValue == option.label ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var libraryTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Types")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(CaptureType.allCases) { type in
                    if let count = libraryTypeOptions[type], count > 0 {
                        Button {
                            toggleLibraryTypeFilter(type)
                        } label: {
                            HStack(spacing: 6) {
                                Text(type.displayName)
                                    .lineLimit(1)
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .font(.system(size: 12, weight: selectedLibraryTypeFilter == type ? .semibold : .medium))
                            .foregroundStyle(selectedLibraryTypeFilter == type ? Color.white : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedLibraryTypeFilter == type ? Color.accentColor : Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func activeLibraryFilterChip(title: String, removeAction: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    private func toggleLibraryCollectionFilter(_ collectionName: String) {
        if selectedLibraryCollectionFilter == collectionName {
            selectedLibraryCollectionFilter = nil
        } else {
            selectedLibraryCollectionFilter = collectionName
            if let currentProjectFilter = selectedLibraryProjectFilter,
               !viewModel.libraryItems.contains(where: { $0.collectionName == collectionName && $0.projectName == currentProjectFilter }) {
                selectedLibraryProjectFilter = nil
            }
        }
    }

    private func toggleLibraryProjectFilter(_ projectName: String) {
        if selectedLibraryProjectFilter == projectName {
            selectedLibraryProjectFilter = nil
        } else {
            selectedLibraryProjectFilter = projectName
        }
    }

    private func toggleLibraryTypeFilter(_ type: CaptureType) {
        selectedLibraryTypeFilter = selectedLibraryTypeFilter == type ? nil : type
    }

    private func clearLibraryFilters() {
        selectedLibraryCollectionFilter = nil
        selectedLibraryProjectFilter = nil
        selectedLibraryTypeFilter = nil
    }

    private func targetSection(title: String, targets: [ShareableCaptureTarget]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if targets.isEmpty {
                Text("No \(title.lowercased()) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(targets) { target in
                    targetRow(target)
                }
            }
        }
    }

    private func targetRow(_ target: ShareableCaptureTarget) -> some View {
        let isSelected = viewModel.selectedTargetID == target.id

        return Button {
            viewModel.selectedTargetID = target.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let ownerName = target.ownerName, !ownerName.isEmpty {
                        Text(ownerName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(target.kind == .display ? "Display" : "Window")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(target.width)x\(target.height)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(14)
            .frame(minHeight: 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                viewModel.activateCaptureTarget(target)
            }
        )
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

    private func playbackTransitionPlateOpacity(
        for state: CaptureSetupViewModel.PlaybackTransitionPlateState
    ) -> Double {
        switch state {
        case .hidden:
            return 0
        case .fadingIn, .visible:
            return 1
        case .fadingOut:
            return 0
        }
    }

    private func playbackTransitionPlateAnimationDuration(
        for state: CaptureSetupViewModel.PlaybackTransitionPlateState
    ) -> Double {
        switch state {
        case .hidden:
            return 0
        case .fadingIn:
            return 0.12
        case .visible:
            return 0
        case .fadingOut:
            return 0.16
        }
    }

    private func activeZoomPreviewState(
        at currentTime: Double,
        zoomMarkers: [ZoomPlanItem],
        contentCoordinateSize: CGSize
    ) -> ZoomPreviewState? {
        guard let state = SharedMotionEngine.activeZoomState(
            at: currentTime,
            zoomMarkers: zoomMarkers,
            contentCoordinateSize: contentCoordinateSize,
            coordinateSpace: .topLeft
        ) else {
            return nil
        }
        return ZoomPreviewState(scale: state.scale, normalizedPoint: state.normalizedPoint)
    }

    private func activeEffectPreviewState(
        at currentTime: Double,
        effectMarkers: [EffectPlanItem]
    ) -> EffectPreviewState? {
        let eligibleMarkers = effectMarkers
            .filter { $0.enabled && $0.focusRegion != nil && currentTime >= $0.startTime && currentTime <= $0.endTime }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.sourceEventTimestamp < rhs.sourceEventTimestamp
                }
                return lhs.startTime < rhs.startTime
            }

        guard let marker = eligibleMarkers.last,
              let region = marker.focusRegion else {
            return nil
        }

        let fadeInDuration = max(marker.fadeInDuration, 0)
        let fadeOutDuration = max(marker.fadeOutDuration, 0)
        let fadeInProgress: Double
        if fadeInDuration <= 0.0001 {
            fadeInProgress = 1
        } else {
            fadeInProgress = min(max((currentTime - marker.startTime) / fadeInDuration, 0), 1)
        }

        let fadeOutProgress: Double
        if fadeOutDuration <= 0.0001 {
            fadeOutProgress = 1
        } else {
            fadeOutProgress = min(max((marker.endTime - currentTime) / fadeOutDuration, 0), 1)
        }

        let timingIntensity = min(fadeInProgress, fadeOutProgress)
        let blurIntensity = timingIntensity * min(max(marker.blurAmount, 0), 1)
        let darkenIntensity = timingIntensity * min(max(marker.darkenAmount, 0), 1)
        let tintIntensity = timingIntensity * min(max(marker.tintAmount, 0), 1)
        guard max(blurIntensity, darkenIntensity, tintIntensity) > 0 else { return nil }

        return EffectPreviewState(
            style: marker.style,
            region: region,
            blurIntensity: blurIntensity,
            darkenIntensity: darkenIntensity,
            tintIntensity: tintIntensity,
            cornerRadius: CGFloat(max(marker.cornerRadius, 0)),
            feather: CGFloat(max(marker.feather, 0)),
            tintColor: color(for: marker.tintColor)
        )
    }

    private func effectPreviewOverlay(
        effectState: EffectPreviewState,
        overlayRect: CGRect,
        fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> some View {
        let overlayColor = effectPreviewOverlayColor(for: effectState)
        guard overlayColor != .clear else {
            return AnyView(EmptyView())
        }
        let transformedRect = transformedOverlayRect(
            overlayRect,
            in: fittedRect,
            previewState: previewState
        )
        let cornerRadii = overflowRegionCornerRadii(
            for: transformedRect,
            within: fittedRect,
            baseRadius: effectState.cornerRadius
        )
        let localOverlayRect = CGRect(
            x: transformedRect.minX - fittedRect.minX,
            y: transformedRect.minY - fittedRect.minY,
            width: transformedRect.width,
            height: transformedRect.height
        )
        return AnyView(
            Rectangle()
                .fill(overlayColor)
                .mask {
                    effectOutsideMask(
                        localOverlayRect: localOverlayRect,
                        cornerRadii: cornerRadii,
                        canvasSize: fittedRect.size,
                        feather: effectState.feather
                    )
                }
            .frame(width: fittedRect.width, height: fittedRect.height)
        )
    }

    private func effectBlurLayer(
        mainPlayer: AVPlayer,
        effectState: EffectPreviewState,
        overlayRect: CGRect,
        fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> some View {
        let transformedRect = transformedOverlayRect(
            overlayRect,
            in: fittedRect,
            previewState: previewState
        )
        let cornerRadii = overflowRegionCornerRadii(
            for: transformedRect,
            within: fittedRect,
            baseRadius: effectState.cornerRadius
        )
        let localOverlayRect = CGRect(
            x: transformedRect.minX - fittedRect.minX,
            y: transformedRect.minY - fittedRect.minY,
            width: transformedRect.width,
            height: transformedRect.height
        )

        return AnyView(PlaybackVideoLayerSurface(player: mainPlayer)
            .frame(width: fittedRect.width, height: fittedRect.height)
            .scaleEffect(previewState?.scale ?? 1, anchor: .topLeading)
            .offset(zoomPreviewOffset(for: previewState, in: fittedRect))
            .blur(radius: 28 * effectState.blurIntensity)
            .mask {
                effectOutsideMask(
                    localOverlayRect: localOverlayRect,
                    cornerRadii: cornerRadii,
                    canvasSize: fittedRect.size,
                    feather: effectState.feather
                )
            })
    }

    private func effectOutsideMask(
        localOverlayRect: CGRect,
        cornerRadii: RectangleCornerRadii,
        canvasSize: CGSize,
        feather: CGFloat
    ) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay {
                UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                    .fill(Color.white)
                    .frame(width: localOverlayRect.width, height: localOverlayRect.height)
                    .position(x: localOverlayRect.midX, y: localOverlayRect.midY)
                    .blur(radius: max(feather, 0))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
    }

    private func effectPreviewOverlayColor(for effectState: EffectPreviewState) -> Color {
        switch effectState.style {
        case .darken:
            return Color.black.opacity(effectState.darkenIntensity)
        case .blurDarken:
            return Color.black.opacity(effectState.darkenIntensity)
        case .tint:
            return effectState.tintColor.opacity(0.42 * effectState.tintIntensity)
        case .blur:
            return .clear
        }
    }

    private func color(for tintColor: EffectTintColor) -> Color {
        Color(
            .sRGB,
            red: min(max(tintColor.red, 0), 1),
            green: min(max(tintColor.green, 0), 1),
            blue: min(max(tintColor.blue, 0), 1),
            opacity: min(max(tintColor.alpha, 0), 1)
        )
    }

    private func effectTintColorBinding(for marker: EffectPlanItem) -> Binding<Color> {
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

    private func transformedOverlayRect(
        _ rect: CGRect,
        in fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> CGRect {
        guard let previewState else { return rect }

        let topLeft = transformedOverlayPoint(
            CGPoint(x: rect.minX, y: rect.minY),
            in: fittedRect,
            previewState: previewState
        )
        let bottomRight = transformedOverlayPoint(
            CGPoint(x: rect.maxX, y: rect.maxY),
            in: fittedRect,
            previewState: previewState
        )

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).standardized
    }


    private func zoomPreviewOffset(for previewState: ZoomPreviewState?, in fittedRect: CGRect) -> CGSize {
        guard let previewState, fittedRect.width > 0, fittedRect.height > 0 else {
            return .zero
        }
        return SharedMotionEngine.previewOffset(
            for: SharedMotionEngine.PreviewState(
                scale: previewState.scale,
                normalizedPoint: previewState.normalizedPoint
            ),
            outputSize: fittedRect.size
        )
    }

    private func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
        let safeLeadIn = max(marker.leadInTime, 0)
        let safeZoomIn = max(marker.zoomInDuration, 0.05)
        let safeHold = max(marker.holdDuration, 0.05)
        let safeZoomOut = max(marker.zoomOutDuration, 0.05)
        let peakTime = marker.zoomType == .outOnly
            ? marker.sourceEventTimestamp
            : max(0, marker.sourceEventTimestamp - safeLeadIn)
        let fallbackStart = max(0, marker.sourceEventTimestamp - safeLeadIn - safeZoomIn)
        let fallbackHoldUntil = marker.sourceEventTimestamp + safeHold
        let fallbackEnd = fallbackHoldUntil + safeZoomOut

        switch marker.zoomType {
        case .inOut:
            let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
            let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
            let safeEndTime = marker.endTime.isFinite ? max(marker.endTime, safeHoldUntil) : fallbackEnd
            return (safeStart, peakTime, safeHoldUntil, safeEndTime)

        case .inOnly:
            let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
            let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
            return (safeStart, peakTime, safeHoldUntil, safeHoldUntil)

        case .noZoom:
            let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
            let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
            return (safeStart, peakTime, safeHoldUntil, safeHoldUntil)

        case .outOnly:
            let safeStart = marker.startTime.isFinite ? max(marker.startTime, peakTime) : peakTime
            let safeEndTime = marker.endTime.isFinite ? max(marker.endTime, safeStart) : peakTime + safeZoomOut
            return (safeStart, peakTime, safeStart, safeEndTime)
        }
    }

    private func zoomScale(
        at currentTime: Double,
        for marker: ZoomPlanItem,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)
    ) -> CGFloat {
        let maxScale = max(marker.zoomScale, 1)
        if currentTime <= timeline.peakTime {
            let progress = motionProgress(
                currentTime: currentTime,
                startTime: timeline.startTime,
                endTime: timeline.peakTime,
                easeStyle: marker.easeStyle,
                direction: .entering,
                bounceAmount: marker.bounceAmount
            )
            return interpolate(from: 1, to: maxScale, progress: progress.scale)
        }

        if currentTime <= timeline.holdUntil {
            return CGFloat(maxScale)
        }

        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.holdUntil,
            endTime: timeline.endTime,
            easeStyle: marker.easeStyle,
            direction: .exiting,
            bounceAmount: marker.bounceAmount
        )
        return max(interpolate(from: maxScale, to: 1, progress: progress.scale), 1)
    }

    private func normalizedProgress(_ value: Double, start: Double, end: Double) -> Double {
        guard end > start else { return 1 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private func interpolate(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        from + ((to - from) * CGFloat(progress))
    }

    private func motionProgress(
        currentTime: Double,
        startTime: Double,
        endTime: Double,
        easeStyle: ZoomEaseStyle,
        direction: MotionDirection,
        bounceAmount: Double
    ) -> MotionProgressSample {
        let progress = normalizedProgress(currentTime, start: startTime, end: endTime)
        let scaleProgress = easeStyle == .bounce
            ? bounceProgress(progress, amount: bounceAmount)
            : eased(progress, style: easeStyle, direction: direction)
        let panProgress: Double
        if easeStyle == .bounce {
            let smoothProgress = eased(progress, style: .smooth, direction: direction)
            panProgress = smoothProgress + ((scaleProgress - smoothProgress) * MotionTuning.panBounceInfluence)
        } else {
            panProgress = eased(progress, style: easeStyle, direction: direction)
        }
        return MotionProgressSample(scale: scaleProgress, pan: panProgress)
    }

    private func bounceProgress(_ progress: Double, amount: Double) -> Double {
        let clampedAmount = min(max(amount, 0), 1)
        let approachFraction = MotionTuning.bounceApproachFraction
        if progress <= approachFraction {
            let approachProgress = normalizedProgress(progress, start: 0, end: approachFraction)
            return eased(approachProgress, style: .smooth, direction: .entering)
        }

        let bounceProgress = normalizedProgress(progress, start: approachFraction, end: 1)
        let overshoot = MotionTuning.bounceMinOvershoot + (MotionTuning.bounceMaxOvershoot * clampedAmount)
        let envelope = pow(1 - bounceProgress, 2.2) * overshoot
        let oscillation = sin(bounceProgress * .pi * MotionTuning.bounceOscillationCount)
        return 1 + (envelope * oscillation)
    }

    private func eased(_ progress: Double, style: ZoomEaseStyle, direction: MotionDirection) -> Double {
        switch style {
        case .smooth:
            return 0.5 - (cos(progress * .pi) * 0.5)
        case .fastIn:
            return direction == .entering ? (1 - pow(1 - progress, 3)) : pow(progress, 3)
        case .fastOut:
            return direction == .entering ? pow(progress, 3) : (1 - pow(1 - progress, 3))
        case .linear:
            return progress
        case .bounce:
            return bounceProgress(progress, amount: 0.35)
        }
    }

    private func inOutPreviewState(
        at currentTime: Double,
        stateEvent: ZoomStateEvent,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)
    ) -> ZoomPreviewState {
        let scale = zoomScale(at: currentTime, for: stateEvent.marker, timeline: timeline)
        return ZoomPreviewState(scale: max(scale, 1), normalizedPoint: stateEvent.normalizedPoint)
    }

    private func inOnlyPreviewState(
        at currentTime: Double,
        stateEvent: ZoomStateEvent,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)
    ) -> ZoomPreviewState {
        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.startTime,
            endTime: timeline.peakTime,
            easeStyle: stateEvent.marker.easeStyle,
            direction: .entering,
            bounceAmount: stateEvent.marker.bounceAmount
        )
        let scale = interpolate(from: 1, to: stateEvent.scale, progress: progress.scale)
        return ZoomPreviewState(scale: max(scale, 1), normalizedPoint: stateEvent.normalizedPoint)
    }

    private func outOnlyPreviewState(
        at currentTime: Double,
        currentState: ZoomPreviewState,
        targetPoint: CGPoint,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
        easeStyle: ZoomEaseStyle,
        bounceAmount: Double
    ) -> ZoomPreviewState {
        let startScale = max(currentState.scale, 1)
        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.startTime,
            endTime: timeline.endTime,
            easeStyle: easeStyle,
            direction: .exiting,
            bounceAmount: bounceAmount
        )
        let scale = max(interpolate(from: startScale, to: 1, progress: progress.scale), 1)
        let x = currentState.normalizedPoint.x + ((targetPoint.x - currentState.normalizedPoint.x) * progress.pan)
        let y = currentState.normalizedPoint.y + ((targetPoint.y - currentState.normalizedPoint.y) * progress.pan)
        return ZoomPreviewState(scale: scale, normalizedPoint: CGPoint(x: x, y: y))
    }

    private func playbackTransportBar(_ summary: RecordingInspectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    viewModel.jumpPlaybackToStart()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canUsePlaybackTransport && !viewModel.isRenderedPreviewActive)

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaybackActive ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canUsePlaybackTransport && !viewModel.isRenderedPreviewActive && viewModel.playbackPresentationMode != .previewCompletedSlate)

                Text(timecodeString(for: viewModel.currentPlaybackTime))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    private func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
        let duration = max(summary.duration ?? 0, 0.001)
        let segmentLayouts = timelineSegmentLayouts(for: summary.zoomMarkers, duration: duration)
        let effectLayouts = effectTimelineSegmentLayouts(for: summary.effectMarkers, duration: duration)
        let trackCenterY: CGFloat = 34
        let segmentOriginY: CGFloat = 16
        let hoveredTooltipEntry = hoveredTimelineTooltipEntry(in: summary)
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
                        showsNoZoomFallbackControls: showsNoZoomFallbackControls
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

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 8)
                        .position(x: width / 2, y: trackCenterY)

                    if isDraggingTimeline {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(height: 8)
                            .position(x: width / 2, y: trackCenterY)
                    }

                    if editorMode == .zoomAndClicks {
                        ForEach(effectLayouts) { layout in
                            referenceTimelineSegment(
                                startRatio: layout.startRatio,
                                eventRatio: layout.eventRatio,
                                endRatio: layout.endRatio,
                                lane: layout.lane,
                                width: width,
                                verticalOrigin: segmentOriginY,
                                tint: Color.secondary,
                                opacity: 0.24
                            )
                        }

                        ForEach(segmentLayouts) { layout in
                            let displayedPhase = displayedTimelinePhase(for: layout.marker)
                            timelineSegment(
                                layout: layout,
                                width: width,
                                duration: duration,
                                verticalOrigin: segmentOriginY,
                                isSelected: viewModel.selectedZoomMarkerID == layout.marker.id,
                                isEnabled: layout.marker.enabled,
                                activePhase: displayedPhase,
                                onOptionDragChanged: { translationX in
                                    isTimelineKeyboardFocused = true
                                    if activeTimelineMarkerDragID == nil {
                                        activeTimelineMarkerDragID = layout.marker.id
                                        activeTimelineMarkerDragStartTime = layout.marker.sourceEventTimestamp
                                        viewModel.beginTimelineMarkerMove(layout.marker.id)
                                    }
                                    guard activeTimelineMarkerDragID == layout.marker.id else { return }
                                    let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                                    let targetTime = startTime + (Double(translationX / width) * duration)
                                    viewModel.previewTimelineMarkerMove(layout.marker.id, to: targetTime)
                                },
                                onOptionDragEnded: { translationX in
                                    isTimelineKeyboardFocused = true
                                    guard activeTimelineMarkerDragID == layout.marker.id else { return }
                                    let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                                    let targetTime = startTime + (Double(translationX / width) * duration)
                                    viewModel.commitTimelineMarkerMove(layout.marker.id, to: targetTime)
                                    activeTimelineMarkerDragID = nil
                                    activeTimelineMarkerDragStartTime = nil
                                }
                            )
                        }
                    } else {
                        ForEach(segmentLayouts) { layout in
                            referenceTimelineSegment(
                                startRatio: layout.startRatio,
                                eventRatio: layout.eventRatio,
                                endRatio: layout.endRatio,
                                lane: layout.lane,
                                width: width,
                                verticalOrigin: segmentOriginY,
                                tint: Color.secondary,
                                opacity: 0.34
                            )
                        }

                        ForEach(effectLayouts) { layout in
                            EffectTimelineSegmentView(
                                layout: layout,
                                width: width,
                                verticalOrigin: segmentOriginY,
                                isSelected: viewModel.selectedEffectMarkerID == layout.marker.id,
                                isEnabled: layout.marker.enabled,
                                isPlaybackHighlighted: isEffectPlaybackHighlighted(layout.marker),
                                onSelect: {
                                    viewModel.selectEffectMarker(layout.marker.id, seekPlaybackHead: true)
                                }
                            )
                        }

                        if effectLayouts.isEmpty {
                            Text("Effects bars will appear here")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    if !timelineInteractionSuppressed,
                       let hoveredTooltipEntry,
                       let hoveredAnchor = hoveredTimelineTooltipAnchor {
                        timelineMarkerTooltipOverlay(
                            markerID: hoveredTooltipEntry.marker.id,
                            markerNumber: hoveredTooltipEntry.markerNumber,
                            marker: hoveredTooltipEntry.marker,
                            phase: hoveredTimelinePhase,
                            anchor: hoveredAnchor,
                            width: width
                        )
                    }

                    ZStack {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 40)

                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                            .offset(y: -19)

                        Circle()
                            .fill(Color.accentColor.opacity(0.001))
                            .frame(width: 22, height: 22)
                            .offset(y: -19)
                    }
                    .frame(width: 22, height: 52)
                    .shadow(color: Color.accentColor.opacity(isDraggingTimeline ? 0.42 : 0.22), radius: isDraggingTimeline ? 6 : 3, x: 0, y: 0)
                    .position(
                        x: min(max(playheadX, 11), max(width - 11, 11)),
                        y: trackCenterY - 2
                    )
                }
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

            ZStack {
                HStack {
                    Text("0")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timecodeString(for: duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(
                    isDrawingEffectFocusRegion
                    ? "←/→/↑/↓ to nudge the focus region, ⌥ + Arrow for 10x speed"
                    : editorMode == .effects
                    ? "Zoom & Click bars are shown as grey reference guides while editing effects."
                    : isDrawingNoZoomOverflowRegion
                    ? "←/→/↑/↓ to nudge the overflow region, ⌥ + Arrow for 10x speed"
                    : "⌥ Click to select a Marker, ⌥ Click + Drag to reposition, ←/→ to nudge 0.1s"
                )
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.secondary)
            }
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

    @ViewBuilder
    private func timelineToolbar(
        summary: RecordingInspectionSummary,
        selectedMarker: ZoomPlanItem?,
        showsPulseControls: Bool,
        showsNoZoomFallbackControls: Bool
    ) -> some View {
        TimelineToolbarView(
            hasSelectedMarker: viewModel.selectedZoomMarkerID != nil,
            canEditClickFocusMarkers: viewModel.canEditClickFocusMarkers,
            isPlacingClickFocus: isPlacingClickFocus,
            selectedMarker: selectedMarker,
            showsPulseControls: showsPulseControls,
            showsNoZoomFallbackControls: showsNoZoomFallbackControls,
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
    }

    private func timelineSegment(
        layout: TimelineSegmentLayout,
        width: CGFloat,
        duration: Double,
        verticalOrigin: CGFloat,
        isSelected: Bool,
        isEnabled: Bool,
        activePhase: MarkerTimingPhase?,
        onOptionDragChanged: @escaping (CGFloat) -> Void,
        onOptionDragEnded: @escaping (CGFloat) -> Void
    ) -> some View {
        let marker = layout.marker
        let interactionSuppressed = activeTimelineMarkerDragID != nil || NSEvent.modifierFlags.contains(.option)
        let isHovered = !interactionSuppressed && hoveredTimelineMarkerID == marker.id
        let baseColor: Color = isSelected ? .accentColor : (isEnabled ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.35))
        let laneHeight: CGFloat = 9
        let laneSpacing: CGFloat = 4
        let laneY = verticalOrigin + (CGFloat(layout.lane) * (laneHeight + laneSpacing))
        let startX = CGFloat(layout.startRatio) * width
        let endX = CGFloat(layout.endRatio) * width
        let eventX = CGFloat(layout.eventRatio) * width
        let barWidth = max(endX - startX, 10)
        let emphasisWidth: CGFloat = min(max(barWidth * 0.28, 8), 18)
        let markerBodyHeight: CGFloat = isSelected ? 18 : 14
        let markerBodyWidth: CGFloat = isSelected ? 8 : 6
        let hoverHighlightColor = (isSelected ? Color.accentColor : baseColor).opacity(isHovered ? (isEnabled ? 0.22 : 0.12) : 0)
        let hoverTargetPadding: CGFloat = 7
        let hoverTargetWidth = max(barWidth + (hoverTargetPadding * 2), 18)
        let hoverTargetHeight: CGFloat = 28
        let hoverAnchor = CGPoint(x: startX + (barWidth / 2), y: max(laneY - 20, 10))
        let localMinX = max(min(startX, eventX - 8) - hoverTargetPadding, 0)
        let localMaxX = min(max(endX, eventX + 8) + hoverTargetPadding, width)
        let localWidth = max(localMaxX - localMinX, hoverTargetWidth)
        let localCenterX = localMinX + (localWidth / 2)
        let localBarCenterX = (startX + (barWidth / 2)) - localMinX
        let localEventX = eventX - localMinX
        let localHoverCenterX = localBarCenterX
        let localHeight: CGFloat = 34
        let localCenterY = localHeight / 2
        let localMarkerCenterY = localCenterY + 0.5
        let labelY: CGFloat = 6
        let highlightedBarWidth = barWidth + 10
        let highlightedBarX = min(
            max(localBarCenterX, highlightedBarWidth / 2),
            max(localWidth - (highlightedBarWidth / 2), highlightedBarWidth / 2)
        )
        let optionDragGesture = DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard activeTimelineMarkerDragID == marker.id || NSEvent.modifierFlags.contains(.option) else {
                    return
                }
                clearTimelineHover()
                onOptionDragChanged(value.translation.width)
            }
            .onEnded { value in
                guard activeTimelineMarkerDragID == marker.id || NSEvent.modifierFlags.contains(.option) else {
                    return
                }
                onOptionDragEnded(value.translation.width)
            }

        return ZStack {
            timelineSegmentBar(
                marker: marker,
                baseColor: baseColor,
                isSelected: isSelected,
                isEnabled: isEnabled,
                width: barWidth,
                emphasisWidth: emphasisWidth,
                absoluteBarStartX: startX
            )
            .frame(width: barWidth, height: laneHeight)
            .position(x: localBarCenterX, y: localCenterY)

            Capsule()
                .fill(baseColor)
                .frame(width: markerBodyWidth, height: markerBodyHeight)
                .position(
                    x: min(max(localEventX, markerBodyWidth / 2), max(localWidth - (markerBodyWidth / 2), markerBodyWidth / 2)),
                    y: localMarkerCenterY
                )

            if isSelected {
                Capsule()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 4)
                    .frame(width: 12, height: 22)
                    .position(
                        x: min(max(localEventX, 6), max(localWidth - 6, 6)),
                        y: localMarkerCenterY
                    )
            }

            if let activePhase {
                let labelX = timelinePhaseCenterX(for: marker, phase: activePhase, width: width) - localMinX

                Text(activePhase.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .position(
                        x: labelX,
                        y: labelY
                    )
                    .allowsHitTesting(false)
            }

            if isHovered {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(hoverHighlightColor, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hoverHighlightColor.opacity(0.28))
                    )
                    .frame(width: highlightedBarWidth, height: 22)
                    .position(
                        x: highlightedBarX,
                        y: localCenterY
                    )
                    .allowsHitTesting(false)
            }

            Rectangle()
                .fill(Color.clear)
                .frame(width: hoverTargetWidth, height: hoverTargetHeight)
                .position(
                    x: min(max(localHoverCenterX, hoverTargetWidth / 2), max(localWidth - (hoverTargetWidth / 2), hoverTargetWidth / 2)),
                    y: localCenterY
                )
                .contentShape(Rectangle())
                .onHover { isHovering in
                    guard !interactionSuppressed else {
                        clearTimelineHover()
                        return
                    }
                    if isHovering {
                        setTimelineHover(markerID: marker.id, phase: nil, anchor: hoverAnchor)
                    } else if hoveredTimelineMarkerID == marker.id {
                        clearTimelineHover()
                    }
                }
                .onTapGesture {
                    guard !interactionSuppressed else { return }
                    isTimelineKeyboardFocused = true
                    suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                    viewModel.startMarkerPreview(marker.id)
                }
        }
        .frame(width: localWidth, height: localHeight)
        .position(x: localCenterX, y: laneY + (localHeight / 2))
        .brightness(isHovered ? 0.06 : 0)
        .simultaneousGesture(optionDragGesture)
    }

    @ViewBuilder
    private func timelineSegmentBar(
        marker: ZoomPlanItem,
        baseColor: Color,
        isSelected: Bool,
        isEnabled: Bool,
        width: CGFloat,
        emphasisWidth: CGFloat,
        absoluteBarStartX: CGFloat
    ) -> some View {
        let timeline = zoomTimeline(for: marker)
        let fillOpacity = isEnabled ? 0.82 : 0.34
        let leadColor = baseColor.opacity(isEnabled ? 0.24 : 0.14)
        let zoomInColor = baseColor.opacity(fillOpacity)
        let holdColor = baseColor.opacity(isEnabled ? 0.58 : 0.26)
        let zoomOutColor = baseColor.opacity(isEnabled ? 0.42 : 0.22)
        let totalWidth = max(width, 1)
        let leadWidth = max(phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? 0 : 2)
        let zoomInWidth = max(phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? 0 : 4)
        let holdWidth = max(phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? 0 : 2)
        let zoomOutWidth = max(phaseWidth(from: timeline.holdUntil, to: timeline.endTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? totalWidth : 4)

        Capsule()
            .fill(Color.clear)
            .overlay {
                HStack(spacing: 0) {
                    switch marker.zoomType {
                    case .inOut:
                        timelinePhaseBlock(color: leadColor, width: leadWidth)
                        timelinePhaseBlock(color: zoomInColor, width: zoomInWidth)
                        timelinePhaseBlock(color: holdColor, width: holdWidth)
                        timelinePhaseBlock(color: zoomOutColor, width: zoomOutWidth)
                    case .inOnly:
                        timelinePhaseBlock(color: leadColor, width: leadWidth)
                        timelinePhaseBlock(color: zoomInColor, width: zoomInWidth)
                        timelinePhaseBlock(color: holdColor, width: holdWidth)
                    case .noZoom:
                        timelinePhaseBlock(color: leadColor, width: leadWidth)
                        timelinePhaseBlock(color: zoomInColor, width: zoomInWidth)
                        timelinePhaseBlock(color: holdColor, width: holdWidth)
                    case .outOnly:
                        timelinePhaseBlock(color: zoomOutColor, width: max(totalWidth, emphasisWidth))
                    }
                }
                .clipShape(Capsule())
            }
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .overlay {
                if isSelected {
                    selectedTimelinePhaseOverlay(
                        marker: marker,
                        timeline: timeline,
                        width: totalWidth,
                        isEnabled: isEnabled,
                        absoluteBarStartX: absoluteBarStartX
                    )
                }
            }
    }

    private func timelinePhaseBlock(color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0))
    }

    private func selectedTimelinePhaseOverlay(
        marker: ZoomPlanItem,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
        width: CGFloat,
        isEnabled: Bool,
        absoluteBarStartX: CGFloat
    ) -> some View {
        let phaseBounds = timelinePhaseBoundsMap(for: marker, timeline: timeline, width: width)
        let dividerTimes = phaseDividerTimes(for: marker, timeline: timeline)
        let dividerColor = Color.white.opacity(isEnabled ? 0.38 : 0.22)

        return ZStack(alignment: .leading) {
            ForEach(dividerTimes, id: \.self) { time in
                Rectangle()
                    .fill(dividerColor)
                    .frame(width: 1, height: 9)
                    .position(
                        x: min(max(phaseX(for: time, timeline: timeline, width: width), 0.5), max(width - 0.5, 0.5)),
                        y: 4.5
                    )
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                ForEach(phaseBounds, id: \.phase.rawValue) { item in
                    let phaseAnchor = CGPoint(
                        x: absoluteBarStartX + phaseStartOffset(for: item.phase, marker: marker, timeline: timeline, width: width) + (item.width / 2),
                        y: -8
                    )
                    Color.clear
                        .frame(width: max(item.width, 0))
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering {
                                setTimelineHover(markerID: marker.id, phase: item.phase, anchor: phaseAnchor)
                            } else if hoveredTimelineMarkerID == marker.id, hoveredTimelinePhase == item.phase {
                                setTimelineHover(markerID: marker.id, phase: nil, anchor: CGPoint(x: width / 2, y: -8))
                            }
                        }
                }
            }
        }
        .clipShape(Capsule())
        .onHover { isHovering in
            if !isHovering, hoveredTimelineMarkerID == marker.id, hoveredTimelinePhase != nil {
                setTimelineHover(markerID: marker.id, phase: nil, anchor: CGPoint(x: width / 2, y: -8))
            }
        }
    }

    private func phaseWidth(from start: Double, to end: Double, timelineStart: Double, timelineEnd: Double, totalWidth: CGFloat) -> CGFloat {
        let totalDuration = max(timelineEnd - timelineStart, 0.001)
        let clampedStart = min(max(start, timelineStart), timelineEnd)
        let clampedEnd = min(max(end, clampedStart), timelineEnd)
        return CGFloat((clampedEnd - clampedStart) / totalDuration) * totalWidth
    }

    private func phaseX(for time: Double, timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double), width: CGFloat) -> CGFloat {
        let totalDuration = max(timeline.endTime - timeline.startTime, 0.001)
        let clampedTime = min(max(time, timeline.startTime), timeline.endTime)
        return CGFloat((clampedTime - timeline.startTime) / totalDuration) * width
    }

    private func phaseDividerTimes(for marker: ZoomPlanItem, timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)) -> [Double] {
        let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)

        switch marker.zoomType {
        case .inOut:
            return [zoomInStart, timeline.peakTime, timeline.holdUntil]
        case .inOnly:
            return [zoomInStart, timeline.peakTime]
        case .noZoom:
            return [zoomInStart, timeline.peakTime]
        case .outOnly:
            return []
        }
    }

    private func timelinePhaseBoundsMap(
        for marker: ZoomPlanItem,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
        width: CGFloat
    ) -> [(phase: MarkerTimingPhase, width: CGFloat)] {
        var items: [(phase: MarkerTimingPhase, width: CGFloat)] = []

        switch marker.zoomType {
        case .inOut:
            items.append((.leadIn, phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.zoomIn, phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.hold, phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.zoomOut, phaseWidth(from: timeline.holdUntil, to: timeline.endTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        case .inOnly:
            items.append((.leadIn, phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.zoomIn, phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.hold, phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        case .noZoom:
            items.append((.leadIn, phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.zoomIn, phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
            items.append((.hold, phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        case .outOnly:
            items.append((.zoomOut, width))
        }

        return items.map { item in
            (item.phase, item.width)
        }
    }

    private func phaseStartOffset(
        for phase: MarkerTimingPhase,
        marker: ZoomPlanItem,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
        width: CGFloat
    ) -> CGFloat {
        let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)

        switch phase {
        case .leadIn:
            return phaseX(for: timeline.startTime, timeline: timeline, width: width)
        case .zoomIn:
            return phaseX(for: zoomInStart, timeline: timeline, width: width)
        case .hold:
            return phaseX(for: timeline.peakTime, timeline: timeline, width: width)
        case .zoomOut:
            return phaseX(for: timeline.holdUntil, timeline: timeline, width: width)
        }
    }

    private func timelineSegmentLayouts(for markers: [ZoomPlanItem], duration: Double) -> [TimelineSegmentLayout] {
        let safeDuration = max(duration, 0.001)
        let maxLaneCount = 3
        var laneEndRatios = Array(repeating: -Double.infinity, count: maxLaneCount)
        let sortedMarkers = markers.enumerated().sorted { lhs, rhs in
            let lhsWindow = timelineSegmentWindow(for: lhs.element)
            let rhsWindow = timelineSegmentWindow(for: rhs.element)

            if lhsWindow.start != rhsWindow.start {
                return lhsWindow.start < rhsWindow.start
            }

            return lhs.element.sourceEventTimestamp < rhs.element.sourceEventTimestamp
        }

        return sortedMarkers.map { entry in
            let marker = entry.element
            let window = timelineSegmentWindow(for: marker)
            let startRatio = min(max(window.start / safeDuration, 0), 1)
            let eventRatio = min(max(marker.sourceEventTimestamp / safeDuration, 0), 1)
            let endRatio = min(max(window.end / safeDuration, eventRatio), 1)
            let lane = timelineLane(for: startRatio, endRatio: endRatio, laneEndRatios: &laneEndRatios)

            return TimelineSegmentLayout(
                marker: marker,
                markerNumber: entry.offset + 1,
                lane: lane,
                startRatio: startRatio,
                eventRatio: eventRatio,
                endRatio: endRatio
            )
        }
        .sorted { lhs, rhs in
            if lhs.lane != rhs.lane {
                return lhs.lane < rhs.lane
            }

            return lhs.startRatio < rhs.startRatio
        }
    }

    private func effectTimelineSegmentLayouts(for markers: [EffectPlanItem], duration: Double) -> [EffectTimelineSegmentLayout] {
        let safeDuration = max(duration, 0.001)
        let maxLaneCount = 3
        var laneEndRatios = Array(repeating: -Double.infinity, count: maxLaneCount)

        return markers
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.sourceEventTimestamp < $1.sourceEventTimestamp
                }
                return $0.startTime < $1.startTime
            }
            .map { marker in
                let eventRatio = min(max(marker.snapTime / safeDuration, 0), 1)
                let startRatio = min(max(marker.startTime / safeDuration, 0), eventRatio)
                let endRatio = min(max(marker.endTime / safeDuration, eventRatio), 1)
                let lane = timelineLane(for: startRatio, endRatio: endRatio, laneEndRatios: &laneEndRatios)

                return EffectTimelineSegmentLayout(
                    marker: marker,
                    lane: lane,
                    startRatio: startRatio,
                    eventRatio: eventRatio,
                    endRatio: endRatio
                )
            }
    }

    private func timelineSegmentWindow(for marker: ZoomPlanItem) -> (start: Double, end: Double) {
        let timeline = zoomTimeline(for: marker)

        switch marker.zoomType {
        case .inOut:
            return (start: max(timeline.startTime, 0), end: max(timeline.endTime, timeline.startTime))
        case .inOnly:
            return (start: max(timeline.startTime, 0), end: max(timeline.holdUntil, timeline.startTime))
        case .noZoom:
            return (start: max(timeline.startTime, 0), end: max(timeline.holdUntil, timeline.startTime))
        case .outOnly:
            return (start: max(timeline.startTime, 0), end: max(timeline.endTime, timeline.startTime))
        }
    }

    @ViewBuilder
    private func referenceTimelineSegment(
        startRatio: Double,
        eventRatio: Double,
        endRatio: Double,
        lane: Int,
        width: CGFloat,
        verticalOrigin: CGFloat,
        tint: Color,
        opacity: Double
    ) -> some View {
        let laneHeight: CGFloat = 9
        let laneSpacing: CGFloat = 4
        let laneY = verticalOrigin + (CGFloat(lane) * (laneHeight + laneSpacing))
        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width
        let eventX = CGFloat(eventRatio) * width
        let barWidth = max(endX - startX, 10)

        ZStack {
            Capsule(style: .continuous)
                .fill(tint.opacity(opacity))
                .frame(width: barWidth, height: laneHeight)
                .position(x: startX + (barWidth / 2), y: laneY + (laneHeight / 2))

            Capsule(style: .continuous)
                .fill(tint.opacity(min(opacity + 0.12, 1)))
                .frame(width: 5, height: 14)
                .position(x: eventX, y: laneY + (laneHeight / 2))
        }
        .allowsHitTesting(false)
    }

    private func timelineLane(for startRatio: Double, endRatio: Double, laneEndRatios: inout [Double]) -> Int {
        let lanePadding = 0.008

        for index in laneEndRatios.indices {
            if startRatio >= laneEndRatios[index] + lanePadding {
                laneEndRatios[index] = endRatio
                return index
            }
        }

        if let bestIndex = laneEndRatios.enumerated().min(by: { $0.element < $1.element })?.offset {
            laneEndRatios[bestIndex] = endRatio
            return bestIndex
        }

        return 0
    }

    private func timelineTime(for x: CGFloat, width: CGFloat, duration: Double) -> Double {
        let clampedX = min(max(x, 0), max(width, 1))
        return Double(clampedX / max(width, 1)) * duration
    }

    private func timelineX(for time: Double, duration: Double, width: CGFloat) -> CGFloat {
        let safeDuration = max(duration, 0.001)
        let clampedTime = min(max(time, 0), safeDuration)
        return CGFloat(clampedTime / safeDuration) * width
    }

    private func timelineSnapTarget(
        at x: CGFloat,
        width: CGFloat,
        duration: Double,
        markers: [ZoomPlanItem]
    ) -> (marker: ZoomPlanItem, time: Double)? {
        let snapThreshold: CGFloat = 10
        let markerPositions = markers.map { marker in
            let ratio = min(max(marker.sourceEventTimestamp / max(duration, 0.001), 0), 1)
            return (marker, CGFloat(ratio) * width)
        }

        guard let nearest = markerPositions.min(by: { abs($0.1 - x) < abs($1.1 - x) }),
              abs(nearest.1 - x) <= snapThreshold else {
            return nil
        }

        return (nearest.0, nearest.0.sourceEventTimestamp)
    }

    private func effectTimelineSnapTarget(
        at x: CGFloat,
        width: CGFloat,
        duration: Double,
        markers: [EffectPlanItem]
    ) -> (marker: EffectPlanItem, time: Double)? {
        let snapThreshold: CGFloat = 10
        let markerPositions = markers.map { marker in
            let ratio = min(max(marker.sourceEventTimestamp / max(duration, 0.001), 0), 1)
            return (marker, CGFloat(ratio) * width)
        }

        guard let nearest = markerPositions.min(by: { abs($0.1 - x) < abs($1.1 - x) }),
              abs(nearest.1 - x) <= snapThreshold else {
            return nil
        }

        return (nearest.0, nearest.0.sourceEventTimestamp)
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

    private func overlayPoint(
        for sourcePoint: CGPoint,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGPoint? {
        guard contentCoordinateSize.width > 0,
              contentCoordinateSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return nil
        }

        let fittedRect = fittedVideoRect(in: containerSize, aspectRatio: videoAspectRatio)
        guard fittedRect.width > 0, fittedRect.height > 0 else {
            return nil
        }

        let normalizedX = min(max(sourcePoint.x / contentCoordinateSize.width, 0), 1)
        let normalizedY = min(max(sourcePoint.y / contentCoordinateSize.height, 0), 1)
        let x = fittedRect.minX + (normalizedX * fittedRect.width)
        let y = fittedRect.minY + (normalizedY * fittedRect.height)
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func sourcePoint(
        for overlayPoint: CGPoint,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGPoint? {
        guard contentCoordinateSize.width > 0,
              contentCoordinateSize.height > 0 else {
            return nil
        }

        let fittedRect = fittedVideoRect(in: containerSize, aspectRatio: videoAspectRatio)
        guard fittedRect.contains(overlayPoint),
              fittedRect.width > 0,
              fittedRect.height > 0 else {
            return nil
        }

        let normalizedX = (overlayPoint.x - fittedRect.minX) / fittedRect.width
        let normalizedY = (overlayPoint.y - fittedRect.minY) / fittedRect.height
        return CGPoint(
            x: min(max(normalizedX, 0), 1) * contentCoordinateSize.width,
            y: min(max(normalizedY, 0), 1) * contentCoordinateSize.height
        )
    }

    private func noZoomOverflowRegion(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> NoZoomOverflowRegion? {
        guard let rect = aspectLockedSourceRect(
            from: startPoint,
            to: endPoint,
            contentCoordinateSize: contentCoordinateSize
        ) else {
            return nil
        }

        return NoZoomOverflowRegion(
            centerX: rect.midX / contentCoordinateSize.width,
            centerY: rect.midY / contentCoordinateSize.height,
            width: rect.width / contentCoordinateSize.width,
            height: rect.height / contentCoordinateSize.height
        )
    }

    private func effectFocusRegion(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion? {
        guard let rect = freeformSourceRect(
            from: startPoint,
            to: endPoint,
            contentCoordinateSize: contentCoordinateSize
        ) else {
            return nil
        }

        return effectFocusRegion(for: rect, contentCoordinateSize: contentCoordinateSize)
    }

    private func aspectLockedSourceRect(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let aspectRatio = contentCoordinateSize.width / contentCoordinateSize.height
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let horizontalLimit = deltaX >= 0 ? contentCoordinateSize.width - startPoint.x : startPoint.x
        let verticalLimit = deltaY >= 0 ? contentCoordinateSize.height - startPoint.y : startPoint.y
        let maxWidth = min(horizontalLimit, verticalLimit * aspectRatio)
        guard maxWidth.isFinite, maxWidth > 1 else {
            return nil
        }

        let desiredWidth = max(abs(deltaX), abs(deltaY) * aspectRatio)
        let width = min(max(desiredWidth, 1), maxWidth)
        let height = width / aspectRatio
        let originX = deltaX >= 0 ? startPoint.x : startPoint.x - width
        let originY = deltaY >= 0 ? startPoint.y : startPoint.y - height

        let rect = CGRect(x: originX, y: originY, width: width, height: height)
        return rect.standardized
    }

    private func freeformSourceRect(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let clampedStart = CGPoint(
            x: min(max(startPoint.x, 0), contentCoordinateSize.width),
            y: min(max(startPoint.y, 0), contentCoordinateSize.height)
        )
        let clampedEnd = CGPoint(
            x: min(max(endPoint.x, 0), contentCoordinateSize.width),
            y: min(max(endPoint.y, 0), contentCoordinateSize.height)
        )
        let rect = CGRect(
            x: min(clampedStart.x, clampedEnd.x),
            y: min(clampedStart.y, clampedEnd.y),
            width: abs(clampedEnd.x - clampedStart.x),
            height: abs(clampedEnd.y - clampedStart.y)
        ).standardized
        guard rect.width > 1, rect.height > 1 else {
            return nil
        }
        return rect
    }

    private func effectFocusSourceRect(
        for region: EffectFocusRegion,
        contentCoordinateSize: CGSize
    ) -> CGRect {
        CGRect(
            x: (region.centerX - (region.width / 2)) * contentCoordinateSize.width,
            y: (region.centerY - (region.height / 2)) * contentCoordinateSize.height,
            width: region.width * contentCoordinateSize.width,
            height: region.height * contentCoordinateSize.height
        )
    }

    private func effectFocusRegion(
        for sourceRect: CGRect,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion {
        EffectFocusRegion(
            centerX: sourceRect.midX / contentCoordinateSize.width,
            centerY: sourceRect.midY / contentCoordinateSize.height,
            width: sourceRect.width / contentCoordinateSize.width,
            height: sourceRect.height / contentCoordinateSize.height
        )
    }

    private func overlayRect(
        for region: NoZoomOverflowRegion,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let sourceRect = CGRect(
            x: (region.centerX - (region.width / 2)) * contentCoordinateSize.width,
            y: (region.centerY - (region.height / 2)) * contentCoordinateSize.height,
            width: region.width * contentCoordinateSize.width,
            height: region.height * contentCoordinateSize.height
        )

        guard let topLeft = overlayPoint(
            for: sourceRect.origin,
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ), let bottomRight = overlayPoint(
            for: CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ) else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).standardized
    }

    private func overlayRect(
        for region: EffectFocusRegion,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let sourceRect = effectFocusSourceRect(for: region, contentCoordinateSize: contentCoordinateSize)

        guard let topLeft = overlayPoint(
            for: sourceRect.origin,
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ), let bottomRight = overlayPoint(
            for: CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ) else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).standardized
    }

    private func overflowRegionCornerRadii(
        for overlayRect: CGRect,
        within fittedRect: CGRect,
        baseRadius: CGFloat = 10
    ) -> RectangleCornerRadii {
        let canvasCornerRadius: CGFloat = 18
        let edgeTolerance: CGFloat = 0.5

        let touchesLeft = abs(overlayRect.minX - fittedRect.minX) <= edgeTolerance
        let touchesRight = abs(overlayRect.maxX - fittedRect.maxX) <= edgeTolerance
        let touchesTop = abs(overlayRect.minY - fittedRect.minY) <= edgeTolerance
        let touchesBottom = abs(overlayRect.maxY - fittedRect.maxY) <= edgeTolerance

        return RectangleCornerRadii(
            topLeading: touchesTop && touchesLeft ? canvasCornerRadius : baseRadius,
            bottomLeading: touchesBottom && touchesLeft ? canvasCornerRadius : baseRadius,
            bottomTrailing: touchesBottom && touchesRight ? canvasCornerRadius : baseRadius,
            topTrailing: touchesTop && touchesRight ? canvasCornerRadius : baseRadius
        )
    }

    private func nudgedNoZoomOverflowRegion(
        _ region: NoZoomOverflowRegion,
        deltaX: Double,
        deltaY: Double,
        contentCoordinateSize: CGSize
    ) -> NoZoomOverflowRegion? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let normalizedDeltaX = deltaX / contentCoordinateSize.width
        let normalizedDeltaY = deltaY / contentCoordinateSize.height
        let halfWidth = region.width / 2
        let halfHeight = region.height / 2
        let minCenterX = halfWidth
        let maxCenterX = 1 - halfWidth
        let minCenterY = halfHeight
        let maxCenterY = 1 - halfHeight

        return NoZoomOverflowRegion(
            centerX: min(max(region.centerX + normalizedDeltaX, minCenterX), maxCenterX),
            centerY: min(max(region.centerY + normalizedDeltaY, minCenterY), maxCenterY),
            width: region.width,
            height: region.height
        )
    }

    private func nudgedEffectFocusRegion(
        _ region: EffectFocusRegion,
        deltaX: Double,
        deltaY: Double,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let normalizedDeltaX = deltaX / contentCoordinateSize.width
        let normalizedDeltaY = deltaY / contentCoordinateSize.height
        let halfWidth = region.width / 2
        let halfHeight = region.height / 2
        let minCenterX = halfWidth
        let maxCenterX = 1 - halfWidth
        let minCenterY = halfHeight
        let maxCenterY = 1 - halfHeight

        return EffectFocusRegion(
            centerX: min(max(region.centerX + normalizedDeltaX, minCenterX), maxCenterX),
            centerY: min(max(region.centerY + normalizedDeltaY, minCenterY), maxCenterY),
            width: region.width,
            height: region.height
        )
    }

    private func movedEffectFocusRegion(
        _ region: EffectFocusRegion,
        deltaX: Double,
        deltaY: Double,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion? {
        nudgedEffectFocusRegion(region, deltaX: deltaX, deltaY: deltaY, contentCoordinateSize: contentCoordinateSize)
    }

    private func effectRegionHandlePoint(for handle: EffectRegionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topCenter:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topTrailing:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .centerLeading:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .centerTrailing:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeading:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomCenter:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomTrailing:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func resizedEffectFocusRegion(
        _ region: EffectFocusRegion,
        dragging handle: EffectRegionHandle,
        to overlayPoint: CGPoint,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> EffectFocusRegion? {
        guard let currentPoint = sourcePoint(
            for: overlayPoint,
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ) else {
            return nil
        }

        let sourceRect = effectFocusSourceRect(for: region, contentCoordinateSize: contentCoordinateSize)
        let anchorPoint: CGPoint
        let resizedRect: CGRect?
        switch handle {
        case .topLeading:
            anchorPoint = CGPoint(x: sourceRect.maxX, y: sourceRect.maxY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        case .topCenter:
            anchorPoint = CGPoint(x: sourceRect.midX, y: sourceRect.maxY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: sourceRect.minX, y: currentPoint.y),
                to: CGPoint(x: sourceRect.maxX, y: anchorPoint.y),
                contentCoordinateSize: contentCoordinateSize
            )
        case .topTrailing:
            anchorPoint = CGPoint(x: sourceRect.minX, y: sourceRect.maxY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        case .centerLeading:
            anchorPoint = CGPoint(x: sourceRect.maxX, y: sourceRect.midY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: currentPoint.x, y: sourceRect.minY),
                to: CGPoint(x: anchorPoint.x, y: sourceRect.maxY),
                contentCoordinateSize: contentCoordinateSize
            )
        case .centerTrailing:
            anchorPoint = CGPoint(x: sourceRect.minX, y: sourceRect.midY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: anchorPoint.x, y: sourceRect.minY),
                to: CGPoint(x: currentPoint.x, y: sourceRect.maxY),
                contentCoordinateSize: contentCoordinateSize
            )
        case .bottomLeading:
            anchorPoint = CGPoint(x: sourceRect.maxX, y: sourceRect.minY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        case .bottomCenter:
            anchorPoint = CGPoint(x: sourceRect.midX, y: sourceRect.minY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: sourceRect.minX, y: anchorPoint.y),
                to: CGPoint(x: sourceRect.maxX, y: currentPoint.y),
                contentCoordinateSize: contentCoordinateSize
            )
        case .bottomTrailing:
            anchorPoint = CGPoint(x: sourceRect.minX, y: sourceRect.minY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        }

        guard let resizedRect else {
            return nil
        }

        return effectFocusRegion(for: resizedRect, contentCoordinateSize: contentCoordinateSize)
    }

    private func fittedVideoRect(in containerSize: CGSize, aspectRatio: CGFloat) -> CGRect {
        let safeAspectRatio = max(aspectRatio, 0.1)
        let containerAspectRatio = containerSize.width / max(containerSize.height, 1)

        if containerAspectRatio > safeAspectRatio {
            let height = containerSize.height
            let width = height * safeAspectRatio
            let originX = (containerSize.width - width) / 2
            return CGRect(x: originX, y: 0, width: width, height: height)
        } else {
            let width = containerSize.width
            let height = width / safeAspectRatio
            let originY = (containerSize.height - height) / 2
            return CGRect(x: 0, y: originY, width: width, height: height)
        }
    }

    private func effectRegionPrecisionLoupe(
        player: AVPlayer,
        fittedRect: CGRect,
        focusPoint: CGPoint
    ) -> some View {
        let loupeSize = CGSize(width: 190, height: 132)
        let loupeScale: CGFloat = 2.8
        let clampedX = min(max(focusPoint.x, fittedRect.minX), fittedRect.maxX)
        let clampedY = min(max(focusPoint.y, fittedRect.minY), fittedRect.maxY)
        let localX = clampedX - fittedRect.minX
        let localY = clampedY - fittedRect.minY

        return VStack(alignment: .leading, spacing: 6) {
            Text("Precision")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            PlaybackVideoLayerSurface(player: player)
                .frame(width: fittedRect.width, height: fittedRect.height)
                .scaleEffect(loupeScale, anchor: .topLeading)
                .offset(
                    x: (-localX * loupeScale) + (loupeSize.width / 2),
                    y: (-localY * loupeScale) + (loupeSize.height / 2)
                )
                .frame(width: loupeSize.width, height: loupeSize.height, alignment: .topLeading)
                .clipped()
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1, height: loupeSize.height)
                }
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: loupeSize.width, height: 1)
                }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange, lineWidth: 2)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.64))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func transformedOverlayPoint(
        _ point: CGPoint,
        in fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> CGPoint {
        guard let previewState else { return point }
        let localX = point.x - fittedRect.minX
        let localY = point.y - fittedRect.minY
        let offset = zoomPreviewOffset(for: previewState, in: fittedRect)
        return CGPoint(
            x: fittedRect.minX + (localX * previewState.scale) + offset.width,
            y: fittedRect.minY + (localY * previewState.scale) + offset.height
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

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }

    private func metadataItem(_ title: String, _ value: String, multiline: Bool = false) -> some View {
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

    private var cardBackground: some View {
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

    private func sectionHeader(title: String, subtitle: String, accentWidth: CGFloat) -> some View {
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

    private func markerInspectorCard(_ summary: RecordingInspectionSummary) -> some View {
        ReviewInspectorCard(
            editorMode: editorMode,
            inspectorMode: $inspectorMode,
            effectMarkerCount: summary.effectMarkers.count
        ) {
            Group {
                switch inspectorMode {
                case .captureInfo:
                    captureInfoInspector(summary)
                case .markers:
                    markersInspector(summary)
                }
            }
        } effectsContent: {
            effectsInspector(summary)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func effectsInspector(_ summary: RecordingInspectionSummary) -> some View {
        let displayedMarkers = displayedEffectMarkerList(summary.effectMarkers)
        let entries = displayedMarkers.enumerated().map { index, marker in
            EffectListEntry(
                marker: marker,
                markerNumber: index + 1,
                isSelected: viewModel.selectedEffectMarkerID == marker.id,
                isPlaybackHighlighted: isEffectPlaybackHighlighted(marker)
            )
        }

        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionHeaderView(title: "Effects")

                if entries.isEmpty {
                    Text("No effect markers")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    EffectListTableView(
                        entries: entries,
                        selectedMarkerID: viewModel.selectedEffectMarkerID,
                        onSelectMarker: { markerID in
                            guard renamingEffectMarkerID == nil else { return }
                            viewModel.startEffectMarkerPreview(markerID)
                        },
                        onToggleMarkerEnabled: viewModel.toggleEffectMarkerEnabled(_:),
                        onReorderMarkers: viewModel.reorderEffectMarkerList(to:),
                        renamingMarkerID: $renamingEffectMarkerID,
                        markerNameDraft: $effectMarkerNameDraft,
                        onBeginRename: { marker in
                            renamingEffectMarkerID = marker.id
                            effectMarkerNameDraft = marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? marker.markerName ?? ""
                                : "Unnamed Effect"
                        },
                        onCommitRename: { markerID, name in
                            viewModel.setEffectMarkerName(name, for: markerID)
                            renamingEffectMarkerID = nil
                        },
                        onCancelRename: {
                            renamingEffectMarkerID = nil
                        }
                    )
                    .frame(minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            effectEditorSection
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
        }
    }

    private func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
        let displayedMarkers = displayedMarkerList(summary.zoomMarkers)
        let entries = displayedMarkers.enumerated().map { index, marker in
            MarkerListEntry(
                marker: marker,
                markerNumber: index + 1,
                isSelected: viewModel.selectedZoomMarkerID == marker.id,
                isPlaybackHighlighted: isMarkerPlaybackHighlighted(marker)
            )
        }

        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionHeaderView(title: "Markers")

                if entries.isEmpty {
                    Text("No markers")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkerListTableView(
                        entries: entries,
                        selectedMarkerID: viewModel.selectedZoomMarkerID,
                        onSelectMarker: { markerID in
                            guard renamingMarkerID == nil else { return }
                            suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                            viewModel.startMarkerPreview(markerID)
                        },
                        onToggleMarkerEnabled: viewModel.toggleMarkerEnabled(_:),
                        onReorderMarkers: viewModel.reorderMarkerList(to:),
                        renamingMarkerID: $renamingMarkerID,
                        markerNameDraft: $markerNameDraft,
                        onBeginRename: { marker in
                            renamingMarkerID = marker.id
                            markerNameDraft = marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? marker.markerName ?? ""
                                : "Unnamed Marker"
                        },
                        onCommitRename: { markerID, name in
                            viewModel.setMarkerName(name, for: markerID)
                            renamingMarkerID = nil
                        },
                        onCancelRename: {
                            renamingMarkerID = nil
                        }
                    )
                    .frame(minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            markerEditorSection
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
        }
    }

    private func markerListRow(
        marker: ZoomPlanItem,
        markerNumber: Int,
        isSelected: Bool,
        isPlaybackHighlighted: Bool,
        isGhosted: Bool,
        isLiftedPreview: Bool,
        showsDropTarget: Bool,
        dragProvider: (() -> NSItemProvider)? = nil
    ) -> AnyView {
        let backgroundFill: Color = isPlaybackHighlighted
            ? Color.accentColor.opacity(0.20)
            : isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.clear
        let strokeColor: Color = isPlaybackHighlighted
            ? Color.accentColor.opacity(0.55)
            : isSelected
            ? Color.accentColor.opacity(0.35)
            : Color.secondary.opacity(0.08)

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if let dragProvider {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .onDrag(dragProvider) {
                                markerListDragPreview(
                                    marker: marker,
                                    markerNumber: markerNumber,
                                    isSelected: isSelected,
                                    isPlaybackHighlighted: isPlaybackHighlighted
                                )
                            }
                    } else {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("#\(markerNumber)")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, alignment: .leading)
                Text(timecodeString(for: marker.sourceEventTimestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 88, alignment: .leading)
                Image(systemName: markerTypeSymbol(for: marker.zoomType))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    viewModel.toggleMarkerEnabled(marker.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: marker.enabled ? "checkmark.circle.fill" : "circle")
                        Text(marker.enabled ? "On" : "Off")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(marker.enabled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
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
            if isPlaybackHighlighted {
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .overlay(alignment: .top) {
            if showsDropTarget {
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: 110, height: 4)
                    .offset(y: -2)
            }
        }
        .opacity(isGhosted ? 0.26 : (marker.enabled ? 1.0 : 0.5))
        .scaleEffect(isLiftedPreview ? 1.03 : 1, anchor: .center)
        .shadow(
            color: isLiftedPreview ? Color.black.opacity(0.18) : Color.clear,
            radius: isLiftedPreview ? 14 : 0,
            x: 0,
            y: isLiftedPreview ? 8 : 0
        ))
    }

    private func markerListDragPreview(
        marker: ZoomPlanItem,
        markerNumber: Int,
        isSelected: Bool,
        isPlaybackHighlighted: Bool
    ) -> AnyView {
        AnyView(markerListRow(
            marker: marker,
            markerNumber: markerNumber,
            isSelected: isSelected,
            isPlaybackHighlighted: isPlaybackHighlighted,
            isGhosted: false,
            isLiftedPreview: true,
            showsDropTarget: false,
            dragProvider: nil
        )
        .frame(width: 280))
    }

    private func captureInfoInspector(_ summary: RecordingInspectionSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title / Short Description")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Untitled Capture", text: $captureInfoTitleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    focusedCaptureInfoField == .title ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedCaptureInfoField, equals: .title)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Collection")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Default Collection", text: $captureInfoCollectionDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    focusedCaptureInfoField == .collection ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedCaptureInfoField, equals: .collection)
                        .overlay(alignment: .topLeading) {
                            if focusedCaptureInfoField == .collection,
                               !collectionAutocompleteSuggestions.isEmpty {
                                autocompleteSuggestionPanel(
                                    suggestions: collectionAutocompleteSuggestions,
                                    selectionAction: selectCollectionSuggestion
                                )
                                .offset(y: 34)
                            }
                        }
                }
                .zIndex(focusedCaptureInfoField == .collection ? 2 : 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("General Project", text: $captureInfoProjectDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    focusedCaptureInfoField == .project ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedCaptureInfoField, equals: .project)
                        .overlay(alignment: .topLeading) {
                            if focusedCaptureInfoField == .project,
                               !projectAutocompleteSuggestions.isEmpty {
                                autocompleteSuggestionPanel(
                                    suggestions: projectAutocompleteSuggestions,
                                    selectionAction: selectProjectSuggestion
                                )
                                .offset(y: 34)
                            }
                        }
                }
                .zIndex(focusedCaptureInfoField == .project ? 2 : 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    captureTypeChips(selectedType: viewModel.captureType)
                }

                Divider()

                metadataItem("Created", summary.createdAt.formatted(date: .abbreviated, time: .shortened))

                if let duration = summary.duration {
                    metadataItem("Duration", String(format: "%.2fs", duration))
                }

                metadataItem("Bundle Path", summary.bundleURL.path, multiline: true)

                Button("Reveal in Finder") {
                    viewModel.revealInFinder()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            syncCaptureInfoDrafts(from: summary, force: true)
        }
        .onChange(of: summary.captureID) {
            syncCaptureInfoDrafts(from: summary, force: true)
        }
        .onChange(of: summary.updatedAt) {
            syncCaptureInfoDrafts(from: summary)
        }
        .onChange(of: focusedCaptureInfoField) {
            guard focusedCaptureInfoField == nil else { return }
            syncCaptureInfoDrafts(from: summary, force: true)
        }
        .onChange(of: captureInfoTitleDraft) {
            viewModel.setCurrentCaptureTitle(captureInfoTitleDraft)
        }
        .onChange(of: captureInfoCollectionDraft) {
            viewModel.setCurrentCaptureCollectionName(captureInfoCollectionDraft)
        }
        .onChange(of: captureInfoProjectDraft) {
            viewModel.setCurrentCaptureProjectName(captureInfoProjectDraft)
        }
    }

    private func syncCaptureInfoDrafts(from summary: RecordingInspectionSummary, force: Bool = false) {
        if force || focusedCaptureInfoField != .title {
            captureInfoTitleDraft = viewModel.captureTitle
        }
        if force || focusedCaptureInfoField != .collection {
            captureInfoCollectionDraft = viewModel.collectionName
        }
        if force || focusedCaptureInfoField != .project {
            captureInfoProjectDraft = viewModel.projectName
        }
    }

    private var collectionAutocompleteSuggestions: [String] {
        autocompleteSuggestions(
            from: viewModel.libraryItems
                .map(\.collectionName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            matching: captureInfoCollectionDraft
        )
    }

    private var projectAutocompleteSuggestions: [String] {
        let query = captureInfoProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let preferredCollection = captureInfoCollectionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = viewModel.libraryItems

        let preferredProjects = autocompleteSuggestions(
            from: items
                .filter { preferredCollection.isEmpty ? false : $0.collectionName.compare(preferredCollection, options: .caseInsensitive) == .orderedSame }
                .map(\.projectName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            matching: query
        )

        if preferredProjects.count >= 6 {
            return Array(preferredProjects.prefix(6))
        }

        let allProjects = autocompleteSuggestions(
            from: items
                .map(\.projectName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            matching: query
        )

        var combined = preferredProjects
        for project in allProjects where !combined.contains(where: { $0.compare(project, options: .caseInsensitive) == .orderedSame }) {
            combined.append(project)
            if combined.count == 6 {
                break
            }
        }
        return combined
    }

    private func autocompleteSuggestions(from values: [String], matching query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let uniqueValues = Array(Set(values)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return uniqueValues
            .filter { value in
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedValue.isEmpty else { return false }
                if trimmedQuery.isEmpty {
                    return true
                }
                guard trimmedValue.compare(trimmedQuery, options: .caseInsensitive) != .orderedSame else { return false }
                return trimmedValue.localizedCaseInsensitiveContains(trimmedQuery)
            }
            .prefix(6)
            .map { $0 }
    }

    private func selectCollectionSuggestion(_ suggestion: String) {
        captureInfoCollectionDraft = suggestion
        viewModel.setCurrentCaptureCollectionName(suggestion)
        focusedCaptureInfoField = nil
    }

    private func selectProjectSuggestion(_ suggestion: String) {
        captureInfoProjectDraft = suggestion
        viewModel.setCurrentCaptureProjectName(suggestion)
        focusedCaptureInfoField = nil
    }

    private func autocompleteSuggestionPanel(
        suggestions: [String],
        selectionAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    selectionAction(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .opacity(0.35)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func captureTypeChips(selectedType: CaptureType) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(CaptureType.allCases) { type in
                Button {
                    viewModel.setCurrentCaptureType(type)
                } label: {
                    Text(type.displayName)
                        .font(.system(size: 12, weight: selectedType == type ? .semibold : .medium))
                        .foregroundStyle(selectedType == type ? accentContrastingTextColor() : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedType == type ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var markerEditorSection: some View {
        if let marker = viewModel.selectedZoomMarker {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Marker \(markerDisplayNumber(for: marker))")
                            .font(.headline)
                        Spacer()
                        Text(timecodeString(for: marker.sourceEventTimestamp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if marker.zoomType == .inOut || marker.zoomType == .inOnly {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Zoom Amount")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1fx", marker.zoomScale))
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Slider(
                            value: Binding(
                                get: { marker.zoomScale },
                                set: { viewModel.setSelectedMarkerZoomScale($0) }
                            ),
                            in: 1.0...3.0
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Timing")

                    switch marker.zoomType {
                    case .inOut:
                        timingSliderRow(
                            title: "Motion to Click Offset",
                            value: marker.leadInTime,
                            range: 0...20,
                            phase: .leadIn,
                            action: viewModel.setSelectedMarkerLeadInTime
                        )
                        timingSliderRow(
                            title: "Zoom In",
                            value: marker.zoomInDuration,
                            range: 0.05...3,
                            phase: .zoomIn,
                            action: viewModel.setSelectedMarkerZoomInDuration
                        )
                        timingSliderRow(
                            title: "Hold",
                            value: marker.holdDuration,
                            range: 0.05...10,
                            phase: .hold,
                            action: viewModel.setSelectedMarkerHoldDuration
                        )
                        timingSliderRow(
                            title: "Zoom Out",
                            value: marker.zoomOutDuration,
                            range: 0.05...3,
                            phase: .zoomOut,
                            action: viewModel.setSelectedMarkerZoomOutDuration
                        )
                    case .inOnly:
                        timingSliderRow(
                            title: "Motion to Click Offset",
                            value: marker.leadInTime,
                            range: 0...20,
                            phase: .leadIn,
                            action: viewModel.setSelectedMarkerLeadInTime
                        )
                        timingSliderRow(
                            title: "Zoom In",
                            value: marker.zoomInDuration,
                            range: 0.05...3,
                            phase: .zoomIn,
                            action: viewModel.setSelectedMarkerZoomInDuration
                        )
                        timingSliderRow(
                            title: "Hold",
                            value: marker.holdDuration,
                            range: 0.05...10,
                            phase: .hold,
                            action: viewModel.setSelectedMarkerHoldDuration
                        )
                    case .outOnly:
                        timingSliderRow(
                            title: "Zoom Out",
                            value: marker.zoomOutDuration,
                            range: 0.05...3,
                            phase: .zoomOut,
                            action: viewModel.setSelectedMarkerZoomOutDuration
                        )
                    case .noZoom:
                        timingSliderRow(
                            title: "Motion to Click Offset",
                            value: marker.leadInTime,
                            range: 0...20,
                            phase: .leadIn,
                            action: viewModel.setSelectedMarkerLeadInTime
                        )
                        timingSliderRow(
                            title: marker.noZoomFallbackMode == .pan ? "Pan Speed" : "Scale Speed",
                            value: marker.zoomInDuration,
                            range: 0.05...3,
                            phase: .zoomIn,
                            action: viewModel.setSelectedMarkerZoomInDuration
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            InspectorSectionHeaderView(title: "Zoom Type")
                            Picker("Zoom Type", selection: Binding(
                                get: { marker.zoomType },
                                set: { viewModel.setSelectedMarkerZoomType($0) }
                            )) {
                                ForEach(ZoomType.allCases) { zoomType in
                                    Text(zoomType.displayName).tag(zoomType)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ease Style")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Picker("Ease Style", selection: Binding(
                                get: { marker.easeStyle },
                                set: { viewModel.setSelectedMarkerEaseStyle($0) }
                            )) {
                                ForEach(ZoomEaseStyle.allCases) { easeStyle in
                                    Text(easeStyle.displayName).tag(easeStyle)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    if marker.easeStyle == .bounce {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Bounce Amount")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", marker.bounceAmount))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { marker.bounceAmount },
                                    set: { viewModel.setSelectedMarkerBounceAmount($0) }
                                ),
                                in: 0...1
                            )
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a marker to edit")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var effectEditorSection: some View {
        if let marker = viewModel.selectedEffectMarker {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(marker.markerName?.isEmpty == false ? (marker.markerName ?? "Unnamed Effect") : "Unnamed Effect")
                            .font(.headline)
                        Spacer()
                        Text(timecodeString(for: marker.sourceEventTimestamp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                effectAmountEditorSection(for: marker)

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Timing")
                    timingSliderRow(
                        title: "Hold",
                        value: max(marker.endTime - marker.sourceEventTimestamp, 0.05),
                        range: 0.05...10,
                        phase: .hold,
                        action: viewModel.setSelectedEffectHoldDuration
                    )
                    timingSliderRow(
                        title: "Fade In",
                        value: marker.fadeInDuration,
                        range: 0.05...3,
                        phase: .leadIn,
                        action: viewModel.setSelectedEffectFadeInDuration
                    )
                    timingSliderRow(
                        title: "Fade Out",
                        value: marker.fadeOutDuration,
                        range: 0.05...3,
                        phase: .zoomOut,
                        action: viewModel.setSelectedEffectFadeOutDuration
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Style")
                    Picker("Effect Style", selection: Binding(
                        get: { marker.style },
                        set: { viewModel.setSelectedEffectStyle($0) }
                    )) {
                        ForEach(EffectStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if marker.style == .tint {
                        ColorPicker(
                            "Tint Color",
                            selection: effectTintColorBinding(for: marker),
                            supportsOpacity: false
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Corner Radius")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { marker.cornerRadius },
                                set: { viewModel.setSelectedEffectCornerRadius($0) }
                            ),
                            in: 0...80
                        )
                        Text(String(format: "%.0f", marker.cornerRadius))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Feather")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { marker.feather },
                                set: { viewModel.setSelectedEffectFeather($0) }
                            ),
                            in: 0...60
                        )
                        Text(String(format: "%.0f", marker.feather))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select an effect marker to edit")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func markerDisplayNumber(for marker: ZoomPlanItem) -> Int {
        guard let summary = viewModel.recordingSummary,
              let index = summary.zoomMarkers.firstIndex(where: { $0.id == marker.id }) else {
            return 0
        }
        return index + 1
    }

    private func timingSliderRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PrecisionTimeField(
                    value: value,
                    range: range,
                    action: action,
                    onBeginEditing: {
                        inspectorFocusedTimingPhase = phase
                    },
                    onEndEditing: {
                        if inspectorFocusedTimingPhase == phase {
                            inspectorFocusedTimingPhase = nil
                        }
                    }
                )
                    .frame(width: 72, height: 22)
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: action
                ),
                in: range,
                onEditingChanged: { isEditing in
                    inspectorFocusedTimingPhase = isEditing ? phase : (inspectorFocusedTimingPhase == phase ? nil : inspectorFocusedTimingPhase)
                }
            )
        }
    }

    @ViewBuilder
    private func effectAmountEditorSection(for marker: EffectPlanItem) -> some View {
        switch marker.style {
        case .blur:
            effectAmountSliderRow(
                title: "Blur Amount",
                value: marker.blurAmount,
                action: viewModel.setSelectedEffectBlurAmount
            )
        case .darken:
            effectAmountSliderRow(
                title: "Darken Amount",
                value: marker.darkenAmount,
                action: viewModel.setSelectedEffectDarkenAmount
            )
        case .tint:
            effectAmountSliderRow(
                title: "Tint Amount",
                value: marker.tintAmount,
                action: viewModel.setSelectedEffectTintAmount
            )
        case .blurDarken:
            VStack(alignment: .leading, spacing: 10) {
                effectAmountSliderRow(
                    title: "Blur Amount",
                    value: marker.blurAmount,
                    action: viewModel.setSelectedEffectBlurAmount
                )
                effectAmountSliderRow(
                    title: "Darken Amount",
                    value: marker.darkenAmount,
                    action: viewModel.setSelectedEffectDarkenAmount
                )
            }
        }
    }

    private func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack {
                Slider(
                    value: Binding(
                        get: { value },
                        set: action
                    ),
                    in: 0...1
                )
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func markerTypeSymbol(for zoomType: ZoomType) -> String {
        switch zoomType {
        case .inOnly:
            return "arrow.right"
        case .outOnly:
            return "arrow.left"
        case .inOut:
            return "arrow.left.arrow.right"
        case .noZoom:
            return "smallcircle.filled.circle"
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

    private func hoveredTimelineTooltipEntry(in summary: RecordingInspectionSummary) -> (marker: ZoomPlanItem, markerNumber: Int)? {
        guard let hoveredTimelineMarkerID else { return nil }
        guard let entry = summary.zoomMarkers.enumerated().first(where: { $0.element.id == hoveredTimelineMarkerID }) else {
            return nil
        }
        print("hovered id = \(hoveredTimelineMarkerID)")
        print("resolved tooltip id = \(entry.element.id)")
        return (entry.element, entry.offset + 1)
    }

    private func timelineMarkerTooltipOverlay(markerID: String, markerNumber: Int, marker: ZoomPlanItem, phase: MarkerTimingPhase?, anchor: CGPoint, width: CGFloat) -> some View {
        let tooltipWidth: CGFloat = 240
        let tooltipHalfWidth = tooltipWidth / 2
        let tooltipX = min(max(anchor.x, tooltipHalfWidth), max(width - tooltipHalfWidth, tooltipHalfWidth))
        let tooltipY: CGFloat = -120

        return VStack(alignment: .leading, spacing: 4) {
            Text("Marker #\(markerNumber)")
                .font(.system(size: 11, weight: .semibold))
            Text(timecodeString(for: marker.sourceEventTimestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if let phase {
                Text(phase.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("\(markerTypeSymbol(for: marker.zoomType)) \(marker.zoomType.displayName)")
                .font(.system(size: 11))
            if marker.zoomType != .noZoom && marker.zoomType != .outOnly {
                Text("Zoom \(String(format: "%.1fx", marker.zoomScale))")
                    .font(.system(size: 11))
            }
            Text("Motion to Click Offset \(String(format: "%.2fs", marker.leadInTime))")
                .font(.system(size: 11))
            if marker.zoomType != .outOnly {
                Text("Zoom In \(String(format: "%.2fs", marker.zoomInDuration))")
                    .font(.system(size: 11))
            }
            if marker.zoomType != .outOnly {
                Text("Hold \(String(format: "%.2fs", marker.holdDuration))")
                    .font(.system(size: 11))
            }
            if marker.zoomType == .inOut || marker.zoomType == .outOnly {
                Text("Zoom Out \(String(format: "%.2fs", marker.zoomOutDuration))")
                    .font(.system(size: 11))
            }
            Text("Total \(String(format: "%.2fs", marker.totalSegmentDuration))")
                .font(.system(size: 11))
            Text(marker.enabled ? "Enabled" : "Disabled")
                .font(.system(size: 11))
                .foregroundStyle(marker.enabled ? .primary : .secondary)
            Divider()
            Text("hoveredTimelineMarkerID: \(hoveredTimelineMarkerID ?? "nil")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("displayed marker id: \(markerID)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("displayed marker number: \(markerNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize()
        .frame(width: tooltipWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        .position(
            x: tooltipX,
            y: tooltipY
        )
        .allowsHitTesting(false)
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

    private func isMarkerPlaybackHighlighted(_ marker: ZoomPlanItem) -> Bool {
        guard timelinePhase(for: marker, at: viewModel.currentPlaybackTime) != nil else {
            return false
        }

        if viewModel.activePreviewMarkerID == marker.id {
            return true
        }

        return viewModel.isPlaybackActive && viewModel.selectedZoomMarkerID == marker.id
    }

    private func isEffectPlaybackHighlighted(_ marker: EffectPlanItem) -> Bool {
        viewModel.currentPlaybackTime >= marker.startTime && viewModel.currentPlaybackTime <= marker.endTime
    }

    private func displayedMarkerList(_ markers: [ZoomPlanItem], previewOrder: [String]? = nil) -> [ZoomPlanItem] {
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

    private func displayedEffectMarkerList(_ markers: [EffectPlanItem]) -> [EffectPlanItem] {
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

    private func timelinePhaseCenterX(for marker: ZoomPlanItem, phase: MarkerTimingPhase, width: CGFloat) -> CGFloat {
        let bounds = timelinePhaseBounds(for: marker, phase: phase)
        let startX = timelineX(for: bounds.start, duration: max(viewModel.recordingSummary?.duration ?? 0, 0.001), width: width)
        let endX = timelineX(for: bounds.end, duration: max(viewModel.recordingSummary?.duration ?? 0, 0.001), width: width)
        return startX + max((endX - startX) / 2, 0)
    }

    private func timelinePhaseBounds(for marker: ZoomPlanItem, phase: MarkerTimingPhase) -> (start: Double, end: Double) {
        let timeline = zoomTimeline(for: marker)
        let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)

        switch phase {
        case .leadIn:
            return (timeline.startTime, zoomInStart)
        case .zoomIn:
            return (zoomInStart, timeline.peakTime)
        case .hold:
            return (timeline.peakTime, timeline.holdUntil)
        case .zoomOut:
            return (timeline.holdUntil, timeline.endTime)
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

    private func timecodeString(since start: Date, now: Date) -> String {
        let elapsed = max(now.timeIntervalSince(start), 0)
        let totalFrames = Int(elapsed * 30)
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let seconds = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    private func timecodeString(for seconds: Double) -> String {
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

private enum AppTab: String, CaseIterable, Identifiable {
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

private struct MarkerListEntry: Identifiable {
    let marker: ZoomPlanItem
    let markerNumber: Int
    let isSelected: Bool
    let isPlaybackHighlighted: Bool

    var id: String { marker.id }
}

private struct MarkerListTableView: NSViewRepresentable {
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

private struct PlaybackVideoLayerSurface: NSViewRepresentable {
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

private final class PlayerLayerHostView: NSView {
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
private struct PrecisionTimeField: NSViewRepresentable {
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
