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

    private enum MotionTuning {
        static let bounceApproachFraction = 0.82
        static let bounceMaxOvershoot = 0.14
        static let bounceMinOvershoot = 0.04
        static let bounceOscillationCount = 2.6
        static let panBounceInfluence = 0.35
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
                title: "Create Recording",
                subtitle: viewModel.selectedOutputFolderPath ?? "Choose an output folder",
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
                value: viewModel.selectedOutputFolderPath ?? "Movies/FlowTrack Capture"
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                sectionHeader(
                    title: "Playback",
                    subtitle: "Review your latest capture",
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

                Button("Open Recording…") {
                    viewModel.openRecording()
                }
            }

            if let player = viewModel.player, let summary = viewModel.recordingSummary {
                GeometryReader { geometry in
                    let safeAspectRatio = max(summary.videoAspectRatio, 0.1)
                    let inspectorWidth: CGFloat = 320
                    let activeInspectorWidth = isPlaybackInspectorVisible ? inspectorWidth : 0
                    let contentWidth = max(geometry.size.width - activeInspectorWidth - (isPlaybackInspectorVisible ? 22 : 0), 320)
                    let transportHeight: CGFloat = 52
                    let totalVerticalSpacing: CGFloat = 20
                    let maxVideoHeight = max(180, geometry.size.height - transportHeight - totalVerticalSpacing)
                    let minVideoHeight = min(280, maxVideoHeight)
                    let defaultVideoHeight = min(max(contentWidth / safeAspectRatio, minVideoHeight), maxVideoHeight)
                    let videoHeight = min(max(playbackVideoHeightOverride ?? defaultVideoHeight, minVideoHeight), maxVideoHeight)

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            playbackVideoCard(
                                player: player,
                                aspectRatio: summary.videoAspectRatio,
                                selectedMarker: viewModel.selectedZoomMarker,
                                contentCoordinateSize: summary.contentCoordinateSize,
                                zoomMarkers: summary.zoomMarkers,
                                currentTime: viewModel.currentPlaybackTime
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
                    .onChange(of: summary.recordingURL) {
                        playbackVideoHeightOverride = nil
                        playbackVideoHeightDragOrigin = nil
                        playbackScrubTime = 0
                        isScrubbingPlayback = false
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
                    Text("Open a `.captureproj` bundle or finish a recording to review it here.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 480, maxHeight: .infinity, alignment: .topLeading)
                .background(cardBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Settings",
                subtitle: "Capture location and permissions",
                accentWidth: 132
            )

            settingsCard(
                title: "Output Folder",
                body: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.selectedOutputFolderPath ?? "Movies/FlowTrack Capture")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Choose Output Folder") {
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
                    Text("Current recordings save into the selected output folder as `.captureproj` bundles.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                )
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    Text(target.subtitle ?? (target.kind == .display ? "Display" : "Window"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
    }

    private func playbackVideoCard(
        player: AVPlayer,
        aspectRatio: CGFloat,
        selectedMarker: ZoomPlanItem?,
        contentCoordinateSize: CGSize,
        zoomMarkers: [ZoomPlanItem],
        currentTime: Double
    ) -> some View {
        let safeAspectRatio = max(aspectRatio, 0.1)

        return ZStack {
            cardBackground

            GeometryReader { geometry in
                let fittedRect = fittedVideoRect(in: geometry.size, aspectRatio: safeAspectRatio)
                let previewState = activeZoomPreviewState(
                    at: currentTime,
                    zoomMarkers: zoomMarkers,
                    contentCoordinateSize: contentCoordinateSize
                )

                ZStack {
                    PlaybackVideoSurface(player: player)
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .scaleEffect(previewState?.scale ?? 1, anchor: .topLeading)
                        .offset(zoomPreviewOffset(for: previewState, in: fittedRect))
                        .blur(radius: playbackVideoHeightDragOrigin == nil ? 0 : 4)
                }
                .frame(width: fittedRect.width, height: fittedRect.height)
                .clipped()
                .position(x: fittedRect.midX, y: fittedRect.midY)

                if let mapping = mappedOverlayPoint(
                    for: selectedMarker,
                    contentCoordinateSize: contentCoordinateSize,
                    in: geometry.size,
                    videoAspectRatio: safeAspectRatio
                ) {
                    let ringSize = 22 + max((selectedMarker?.zoomScale ?? 1.0) - 1.0, 0) * 10
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
                    .position(mapping.point)
                    .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func activeZoomPreviewState(
        at currentTime: Double,
        zoomMarkers: [ZoomPlanItem],
        contentCoordinateSize: CGSize
    ) -> ZoomPreviewState? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let enabledMarkers = zoomMarkers
            .filter(\.enabled)
            .sorted { $0.sourceEventTimestamp < $1.sourceEventTimestamp }
        guard !enabledMarkers.isEmpty else {
            return nil
        }

        var currentState = ZoomPreviewState(scale: 1, normalizedPoint: CGPoint(x: 0.5, y: 0.5))

        for marker in enabledMarkers {
            let timeline = zoomTimeline(for: marker)
            if currentTime < timeline.startTime {
                break
            }

            let normalizedPoint = CGPoint(
                x: min(max(marker.centerX / contentCoordinateSize.width, 0), 1),
                y: min(max(marker.centerY / contentCoordinateSize.height, 0), 1)
            )
            let stateEvent = ZoomStateEvent(
                marker: marker,
                normalizedPoint: normalizedPoint,
                scale: max(CGFloat(marker.zoomScale), 1)
            )

            switch marker.zoomType {
            case .inOut:
                if currentTime <= timeline.endTime {
                    return inOutPreviewState(at: currentTime, stateEvent: stateEvent, timeline: timeline)
                }
                currentState = ZoomPreviewState(scale: 1, normalizedPoint: normalizedPoint)

            case .inOnly:
                if currentTime <= timeline.peakTime {
                    return inOnlyPreviewState(at: currentTime, stateEvent: stateEvent, timeline: timeline)
                }
                currentState = ZoomPreviewState(scale: stateEvent.scale, normalizedPoint: normalizedPoint)

            case .outOnly:
                if currentTime <= timeline.endTime {
                    return outOnlyPreviewState(
                        at: currentTime,
                        currentState: currentState,
                        targetPoint: normalizedPoint,
                        timeline: timeline,
                        easeStyle: marker.easeStyle,
                        bounceAmount: marker.bounceAmount
                    )
                }
                currentState = ZoomPreviewState(scale: 1, normalizedPoint: normalizedPoint)
            }
        }

        return currentState.scale > 1.0001 ? currentState : nil
    }

    private func zoomPreviewOffset(for previewState: ZoomPreviewState?, in fittedRect: CGRect) -> CGSize {
        guard let previewState, fittedRect.width > 0, fittedRect.height > 0 else {
            return .zero
        }

        let scaledWidth = fittedRect.width * previewState.scale
        let scaledHeight = fittedRect.height * previewState.scale
        let targetX = previewState.normalizedPoint.x * fittedRect.width
        let targetY = previewState.normalizedPoint.y * fittedRect.height

        let desiredX = (fittedRect.width / 2) - (targetX * previewState.scale)
        let desiredY = (fittedRect.height / 2) - (targetY * previewState.scale)

        let minX = fittedRect.width - scaledWidth
        let minY = fittedRect.height - scaledHeight

        return CGSize(
            width: min(max(desiredX, minX), 0),
            height: min(max(desiredY, minY), 0)
        )
    }

    private func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
        let peakTime = marker.sourceEventTimestamp
        let fallbackStart = max(0, peakTime - 0.35)
        let fallbackHoldUntil = peakTime + max(marker.duration, 0.5)
        let fallbackEnd = fallbackHoldUntil + 0.4

        let startTime = min(marker.startTime, peakTime)
        let safeStart = startTime.isFinite ? startTime : fallbackStart
        let holdUntil = max(marker.holdUntil, peakTime, fallbackHoldUntil)
        let safeHoldUntil = holdUntil.isFinite ? holdUntil : fallbackHoldUntil
        let endTime = max(marker.endTime, safeHoldUntil, fallbackEnd)
        let safeEndTime = endTime.isFinite ? endTime : fallbackEnd

        return (safeStart, peakTime, safeHoldUntil, safeEndTime)
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

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaybackActive ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)

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
                let playheadX = CGFloat(min(max(viewModel.currentPlaybackTime / duration, 0), 1)) * width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 8)

                    if isDraggingTimeline {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(height: 8)
                    }

                    ForEach(Array(summary.zoomMarkers.enumerated()), id: \.element.id) { index, marker in
                        timelineMarker(
                            marker: marker,
                            markerNumber: index + 1,
                            width: width,
                            duration: duration,
                            isSelected: viewModel.selectedZoomMarkerID == marker.id,
                            isEnabled: marker.enabled
                        )
                    }

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 26)
                        .overlay(alignment: .top) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 9, height: 9)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                                )
                                .offset(y: -7)
                        }
                        .shadow(color: Color.accentColor.opacity(isDraggingTimeline ? 0.42 : 0.22), radius: isDraggingTimeline ? 6 : 3, x: 0, y: 0)
                        .offset(x: min(max(playheadX - 1.5, 0), max(width - 3, 0)), y: -9)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
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
            }
            .frame(height: 22)

            HStack {
                Text("0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timecodeString(for: duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    private func timelineMarker(
        marker: ZoomPlanItem,
        markerNumber: Int,
        width: CGFloat,
        duration: Double,
        isSelected: Bool,
        isEnabled: Bool
    ) -> some View {
        let positionRatio = min(max(marker.sourceEventTimestamp / max(duration, 0.001), 0), 1)
        let markerX = CGFloat(positionRatio) * width
        let isHovered = hoveredTimelineMarkerID == marker.id
        let baseColor: Color = isSelected ? .accentColor : (isEnabled ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.35))

        return ZStack {
            Capsule()
                .fill(baseColor)
                .frame(width: isSelected ? 8 : 6, height: isSelected ? 18 : 14)
            if isSelected {
                Capsule()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 4)
                    .frame(width: 12, height: 22)
            }
        }
        .scaleEffect(isHovered ? 1.12 : 1.0)
        .brightness(isHovered ? 0.08 : 0)
        .offset(x: min(max(markerX - 4, 0), max(width - 8, 0)))
        .help(timelineMarkerTooltip(for: marker, markerNumber: markerNumber, isEnabled: isEnabled))
        .onHover { isHovering in
            hoveredTimelineMarkerID = isHovering ? marker.id : (hoveredTimelineMarkerID == marker.id ? nil : hoveredTimelineMarkerID)
        }
    }

    private func timelineTime(for x: CGFloat, width: CGFloat, duration: Double) -> Double {
        let clampedX = min(max(x, 0), max(width, 1))
        return Double(clampedX / max(width, 1)) * duration
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
                                                        Text(String(format: "%.2fs", marker.duration))
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
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
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
                    HStack {
                        Text("Duration")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f s", marker.duration))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { marker.duration },
                            set: { viewModel.setSelectedMarkerDuration($0) }
                        ),
                        in: 0.5...10.0
                    )
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

    private func timelineMarkerTooltip(for marker: ZoomPlanItem, markerNumber: Int, isEnabled: Bool) -> String {
        [
            "Marker #\(markerNumber)",
            timecodeString(for: marker.sourceEventTimestamp),
            "\(markerTypeSymbol(for: marker.zoomType)) \(marker.zoomType.displayName)",
            "Zoom \(String(format: "%.1fx", marker.zoomScale))",
            "Duration \(String(format: "%.2fs", marker.duration))",
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

#Preview {
    ContentView()
}

private enum AppTab: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case review = "Playback"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .capture:
            return "record.circle"
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
