//
//  ContentView.swift
//  Zoom and Track
//

import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CaptureSetupViewModel()
    @State private var selectedTab: AppTab? = .capture
    @State private var playbackVideoHeightOverride: CGFloat?
    @State private var playbackVideoHeightDragOrigin: CGFloat?

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

                Button("Open Recording…") {
                    viewModel.openRecording()
                }
            }

            if let player = viewModel.player, let summary = viewModel.recordingSummary {
                GeometryReader { geometry in
                    let minMetadataHeight: CGFloat = 120
                    let dividerHeight: CGFloat = 24
                    let buttonHeight: CGFloat = 32
                    let totalVerticalSpacing: CGFloat = 36
                    let safeAspectRatio = max(summary.videoAspectRatio, 0.1)
                    let maxVideoHeight = max(180, geometry.size.height - minMetadataHeight - dividerHeight - buttonHeight - totalVerticalSpacing)
                    let minVideoHeight = min(280, maxVideoHeight)
                    let defaultVideoHeight = min(max(geometry.size.width / safeAspectRatio, minVideoHeight), maxVideoHeight)
                    let videoHeight = min(max(playbackVideoHeightOverride ?? defaultVideoHeight, minVideoHeight), maxVideoHeight)

                    VStack(alignment: .leading, spacing: 12) {
                        playbackVideoCard(player: player, aspectRatio: summary.videoAspectRatio)
                            .frame(height: videoHeight)
                            .layoutPriority(1)

                        playbackDivider(currentHeight: videoHeight, minHeight: minVideoHeight, maxHeight: maxVideoHeight)

                        ScrollView {
                            reviewMetadataCard(summary)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: 120, maxHeight: .infinity, alignment: .top)

                        Button("Reveal in Finder") {
                            viewModel.revealInFinder()
                        }
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onChange(of: summary.recordingURL) {
                        playbackVideoHeightOverride = nil
                        playbackVideoHeightDragOrigin = nil
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

    private func reviewMetadataCard(_ summary: RecordingInspectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.bundleName)
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 160), alignment: .leading),
                    GridItem(.flexible(minimum: 160), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                metadataItem("Bundle", summary.bundleName)
                metadataItem("Duration", summary.duration.map { String(format: "%.3f s", $0) } ?? "n/a")
                metadataItem("Events", "\(summary.totalEventCount)")
                metadataItem("Clicks", "\(summary.leftMouseDownCount + summary.rightMouseDownCount)")
                metadataItem("Zoom Markers", "\(summary.zoomMarkers.count)")
                metadataItem("First Event", summary.firstEventTimestamp.map { String(format: "%.6f", $0) } ?? "n/a")
                metadataItem("Last Event", summary.lastEventTimestamp.map { String(format: "%.6f", $0) } ?? "n/a")
            }

            metadataItem("Path", summary.bundleURL.path, multiline: true)

            if !summary.zoomMarkers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zoom Markers")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(summary.zoomMarkers.enumerated()), id: \.element.id) { index, marker in
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, alignment: .leading)
                            Text(String(format: "%.3f s", marker.sourceEventTimestamp))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 72, alignment: .leading)
                            Text(String(format: "x %.1f", marker.centerX))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: "y %.1f", marker.centerY))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1fx", marker.zoomScale))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func playbackVideoCard(player: AVPlayer, aspectRatio: CGFloat) -> some View {
        let safeAspectRatio = max(aspectRatio, 0.1)

        return ZStack {
            cardBackground

            VideoPlayer(player: player)
                .aspectRatio(safeAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .blur(radius: playbackVideoHeightDragOrigin == nil ? 0 : 4)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func playbackDivider(currentHeight: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 24)

            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 72, height: 6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let origin = playbackVideoHeightDragOrigin ?? currentHeight
                    if playbackVideoHeightDragOrigin == nil {
                        playbackVideoHeightDragOrigin = currentHeight
                    }

                    let proposedHeight = origin + value.translation.height
                    playbackVideoHeightOverride = min(max(proposedHeight, minHeight), maxHeight)
                }
                .onEnded { _ in
                    playbackVideoHeightDragOrigin = nil
                }
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

    private func timecodeString(since start: Date, now: Date) -> String {
        let elapsed = max(now.timeIntervalSince(start), 0)
        let totalFrames = Int(elapsed * 30)
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let seconds = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
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
