//
//  ContentView.swift
//  Zoom and Track
//

import AVFoundation
import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CaptureSetupViewModel()
    @State private var selectedTab: AppTab? = .capture
    @State private var playbackVideoHeightOverride: CGFloat?
    @State private var playbackVideoHeightDragOrigin: CGFloat?
    @State private var isPlaybackInspectorVisible = true
    @State private var isPlaybackInfoPresented = false
    @State private var playbackScrubTime = 0.0
    @State private var isScrubbingPlayback = false
    @State private var suppressMarkerListAutoScrollUntil: Date?
    @State private var hoveredTimelineMarkerID: String?
    @State private var isDraggingTimeline = false
    @State private var inspectorFocusedTimingPhase: MarkerTimingPhase?
    @State private var hoveredTimelinePhase: MarkerTimingPhase?
    @State private var hoveredTimelineTooltipAnchor: CGPoint?
    @State private var exportShareAnchorView: NSView?
    @State private var isPlacingClickFocus = false
    @State private var pendingMarkerDragSourcePoint: CGPoint?
    @State private var activeTimelineMarkerDragID: String?
    @State private var activeTimelineMarkerDragStartTime: Double?
    @State private var librarySearchText = ""
    @State private var inspectorMode: EditInspectorMode = .markers
    @State private var selectedLibraryCollectionFilter: String?
    @State private var selectedLibraryProjectFilter: String?
    @State private var selectedLibraryTypeFilter: CaptureType?
    @State private var captureInfoTitleDraft = ""
    @State private var captureInfoCollectionDraft = ""
    @State private var captureInfoProjectDraft = ""
    @FocusState private var focusedCaptureInfoField: CaptureInfoField?

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
        case leadIn = "Lead-In"
        case zoomIn = "Zoom In"
        case hold = "Hold"
        case zoomOut = "Zoom Out"
    }

    private enum EditInspectorMode: String, CaseIterable, Identifiable {
        case captureInfo = "Capture Info"
        case markers = "Markers"

        var id: String { rawValue }
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
            .foregroundStyle(isSelected ? Color.white : Color.primary)
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
                .foregroundStyle(.white)
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
                    Button(isPlacingClickFocus ? "Cancel Add" : "Add Click Focus") {
                        if isPlacingClickFocus {
                            isPlacingClickFocus = false
                        } else {
                            viewModel.cancelPlaybackPreview()
                            inspectorMode = .markers
                            isPlaybackInspectorVisible = true
                            pendingMarkerDragSourcePoint = nil
                            isPlacingClickFocus = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canEditClickFocusMarkers && !isPlacingClickFocus)
                }

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
                                selectedMarker: viewModel.selectedZoomMarker,
                                contentCoordinateSize: summary.contentCoordinateSize,
                                zoomMarkers: summary.zoomMarkers,
                                currentTime: viewModel.currentPlaybackTime,
                                isRenderedPreviewActive: viewModel.isRenderedPreviewActive,
                                renderingStatusMessage: viewModel.markerPreviewStatusMessage,
                                playbackPresentationMode: viewModel.playbackPresentationMode,
                                playbackTransitionPlateState: viewModel.playbackTransitionPlateState,
                                isPlacingClickFocus: isPlacingClickFocus,
                                draggedMarkerSourcePoint: pendingMarkerDragSourcePoint,
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
                    Text("New captures are saved into the selected library root using Collection and Project folders.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
                TextField("Search captures", text: $librarySearchText)
                    .textFieldStyle(.roundedBorder)

                Button("Refresh") {
                    Task { await viewModel.refreshLibrary() }
                }
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
                        List(filteredItems) { item in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\(item.collectionName) • \(item.projectName)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 10) {
                                        Text(item.captureType.displayName)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        if let duration = item.duration {
                                            Text(String(format: "%.2fs", duration))
                                        }
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    if !item.isAvailable, let statusMessage = item.statusMessage {
                                        Text("\(item.status.displayName) • \(statusMessage)")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Spacer(minLength: 12)

                                VStack(alignment: .trailing, spacing: 8) {
                                    Button("Edit") {
                                        viewModel.openLibraryCapture(item)
                                        selectedTab = .review
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!item.canOpenInEditor)

                                    Button("Reveal") {
                                        viewModel.revealLibraryCapture(item)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listStyle(.inset)
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
                                    .stroke(selectedValue == option.label ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
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
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
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
        contentCoordinateSize: CGSize,
        zoomMarkers: [ZoomPlanItem],
        currentTime: Double,
        isRenderedPreviewActive: Bool,
        renderingStatusMessage: String?,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        playbackTransitionPlateState: CaptureSetupViewModel.PlaybackTransitionPlateState,
        isPlacingClickFocus: Bool,
        draggedMarkerSourcePoint: CGPoint?,
        placeClickFocusAction: @escaping (CGPoint) -> Void,
        dragSelectedMarkerAction: @escaping (CGPoint) -> Void,
        commitDraggedMarkerAction: @escaping (CGPoint) -> Void
    ) -> some View {
        let safeAspectRatio = max(aspectRatio, 0.1)

        return ZStack {
            cardBackground

            GeometryReader { geometry in
                let fittedRect = fittedVideoRect(in: geometry.size, aspectRatio: safeAspectRatio)
                let previewState = isRenderedPreviewActive
                    ? nil
                    : activeZoomPreviewState(
                        at: currentTime,
                        zoomMarkers: zoomMarkers,
                        contentCoordinateSize: contentCoordinateSize
                    )

                ZStack {
                    PlaybackVideoSurface(player: mainPlayer)
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .scaleEffect(previewState?.scale ?? 1, anchor: .topLeading)
                        .offset(zoomPreviewOffset(for: previewState, in: fittedRect))
                        .blur(radius: playbackVideoHeightDragOrigin == nil ? 0 : 4)

                    if let previewPlayer {
                        PlaybackVideoSurface(player: previewPlayer)
                            .frame(width: fittedRect.width, height: fittedRect.height)
                            .opacity(playbackPresentationMode == .playingRenderedPreview ? 1 : 0)
                            .animation(.easeInOut(duration: 0.16), value: playbackPresentationMode == .playingRenderedPreview)
                    }
                }
                .frame(width: fittedRect.width, height: fittedRect.height)
                .clipped()
                .position(x: fittedRect.midX, y: fittedRect.midY)
                .coordinateSpace(name: "videoOverlay")

                if !isRenderedPreviewActive,
                   let mapping = mappedOverlayPoint(
                    for: selectedMarker,
                    contentCoordinateSize: contentCoordinateSize,
                    in: geometry.size,
                    videoAspectRatio: safeAspectRatio
                ) {
                    let ringSize = 22 + max((selectedMarker?.zoomScale ?? 1.0) - 1.0, 0) * 10
                    let handlePoint = draggedMarkerSourcePoint.flatMap {
                        overlayPoint(
                            for: $0,
                            contentCoordinateSize: contentCoordinateSize,
                            in: geometry.size,
                            videoAspectRatio: safeAspectRatio
                        )
                    } ?? mapping.point
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
                    Color.black
                        .opacity(0.8)
                    Color.accentColor
                        .opacity(0.2)

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
        let peakTime = marker.sourceEventTimestamp
        let safeLeadIn = max(marker.leadInTime, 0)
        let safeZoomIn = max(marker.zoomInDuration, 0.05)
        let safeHold = max(marker.holdDuration, 0.05)
        let safeZoomOut = max(marker.zoomOutDuration, 0.05)
        let fallbackStart = max(0, peakTime - safeLeadIn - safeZoomIn)
        let fallbackHoldUntil = peakTime + safeHold
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
        let trackCenterY: CGFloat = 34
        let segmentOriginY: CGFloat = 16
        let hoveredTooltipEntry = hoveredTimelineTooltipEntry(in: summary)
        let timelineInteractionSuppressed = activeTimelineMarkerDragID != nil || NSEvent.modifierFlags.contains(.option)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timecodeString(for: viewModel.currentPlaybackTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

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
                                guard activeTimelineMarkerDragID == layout.marker.id else { return }
                                let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                                let targetTime = startTime + (Double(translationX / width) * duration)
                                viewModel.commitTimelineMarkerMove(layout.marker.id, to: targetTime)
                                activeTimelineMarkerDragID = nil
                                activeTimelineMarkerDragStartTime = nil
                            }
                        )
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
                                let snap = timelineSnapTarget(at: currentX, width: width, duration: duration, markers: summary.zoomMarkers)
                                viewModel.updateTimelineScrub(
                                    to: snap?.time ?? timelineTime(for: currentX, width: width, duration: duration),
                                    snappedMarkerID: snap?.marker.id
                                )
                            }
                        }
                        .onEnded { value in
                            guard activeTimelineMarkerDragID == nil else { return }
                            let endX = min(max(value.location.x, 0), width)
                            let snap = timelineSnapTarget(at: endX, width: width, duration: duration, markers: summary.zoomMarkers)
                            let targetTime = snap?.time ?? timelineTime(for: endX, width: width, duration: duration)

                            if isDraggingTimeline {
                                viewModel.endTimelineScrub(at: targetTime, snappedMarkerID: snap?.marker.id)
                                isDraggingTimeline = false
                            } else if let snap {
                                suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                                viewModel.startMarkerPreview(snap.marker.id)
                            } else {
                                viewModel.seekTimelineDirectly(to: targetTime, snappedMarkerID: nil)
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

                Text("⌥ Click to select a Marker, ⌥ Click + Drag to reposition a Marker")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
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

    private func timelineSegmentWindow(for marker: ZoomPlanItem) -> (start: Double, end: Double) {
        let timeline = zoomTimeline(for: marker)

        switch marker.zoomType {
        case .inOut:
            return (start: max(timeline.startTime, 0), end: max(timeline.endTime, timeline.startTime))
        case .inOnly:
            return (start: max(timeline.startTime, 0), end: max(timeline.holdUntil, timeline.startTime))
        case .outOnly:
            return (start: max(timeline.startTime, 0), end: max(timeline.endTime, timeline.startTime))
        }
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.system(size: 16, weight: .semibold))

            Picker("Inspector Mode", selection: $inspectorMode) {
                ForEach(EditInspectorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch inspectorMode {
                case .captureInfo:
                    captureInfoInspector(summary)
                case .markers:
                    markersInspector(summary)
                }
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Markers")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if summary.zoomMarkers.isEmpty {
                                Text("No markers")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(Array(summary.zoomMarkers.enumerated()), id: \.element.id) { index, marker in
                                    Button {
                                        suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                                        viewModel.startMarkerPreview(marker.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 10) {
                                                Text("#\(index + 1)")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .frame(width: 26, alignment: .leading)
                                                Text(timecodeString(for: marker.sourceEventTimestamp))
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .frame(width: 88, alignment: .leading)
                                                Image(systemName: markerTypeSymbol(for: marker.zoomType))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                                Spacer(minLength: 0)
                                                HStack(spacing: 4) {
                                                    Image(systemName: marker.enabled ? "checkmark.circle.fill" : "circle")
                                                    Text(marker.enabled ? "On" : "Off")
                                                }
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(marker.enabled ? Color.accentColor : Color.secondary)
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
                                                .fill(viewModel.selectedZoomMarkerID == marker.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(viewModel.selectedZoomMarkerID == marker.id ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
                                        )
                                        .opacity(marker.enabled ? 1.0 : 0.5)
                                    }
                                    .buttonStyle(.plain)
                                    .id(marker.id)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                markerEditorSection
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
            }
            .onChange(of: viewModel.selectedZoomMarkerID) {
                guard let selectedZoomMarkerID = viewModel.selectedZoomMarkerID else { return }
                if let suppressUntil = suppressMarkerListAutoScrollUntil, Date() < suppressUntil {
                    return
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedZoomMarkerID, anchor: .center)
                }
            }
        }
    }

    private func captureInfoInspector(_ summary: RecordingInspectionSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title / Short Description")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Untitled Capture", text: $captureInfoTitleDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedCaptureInfoField, equals: .title)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Collection")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Default Collection", text: $captureInfoCollectionDraft)
                        .textFieldStyle(.roundedBorder)
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
                        .textFieldStyle(.roundedBorder)
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
                        .foregroundStyle(selectedType == type ? Color.white : Color.primary)
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
                    Text("Marker \(markerDisplayNumber(for: marker))")
                        .font(.headline)
                    Text(timecodeString(for: marker.sourceEventTimestamp))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button("Delete Marker") {
                    viewModel.deleteSelectedMarker()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)

                Toggle("Enabled", isOn: Binding(
                    get: { marker.enabled },
                    set: { viewModel.setSelectedMarkerEnabled($0) }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Zoom Type")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
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

                if marker.zoomType != .outOnly {
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
                    Text("Timing")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    switch marker.zoomType {
                    case .inOut:
                        timingSliderRow(
                            title: "Lead-In Time",
                            value: marker.leadInTime,
                            range: 0...2,
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
                            title: "Lead-In Time",
                            value: marker.leadInTime,
                            range: 0...2,
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
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits {
                        HStack(alignment: .top, spacing: 12) {
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
                                .frame(maxWidth: .infinity)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
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

    private func markerTypeSymbol(for zoomType: ZoomType) -> String {
        switch zoomType {
        case .inOnly:
            return "arrow.right"
        case .outOnly:
            return "arrow.left"
        case .inOut:
            return "arrow.left.arrow.right"
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
            Text("Zoom \(String(format: "%.1fx", marker.zoomScale))")
                .font(.system(size: 11))
            Text("Lead-In \(String(format: "%.2fs", marker.leadInTime))")
                .font(.system(size: 11))
            if marker.zoomType != .outOnly {
                Text("Zoom In \(String(format: "%.2fs", marker.zoomInDuration))")
                    .font(.system(size: 11))
            }
            if marker.zoomType != .outOnly {
                Text("Hold \(String(format: "%.2fs", marker.holdDuration))")
                    .font(.system(size: 11))
            }
            Text("Zoom Out \(String(format: "%.2fs", marker.zoomOutDuration))")
                .font(.system(size: 11))
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
