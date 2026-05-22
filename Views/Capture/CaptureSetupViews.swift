import SwiftUI

extension ContentView {
    var captureView: some View {
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

                            compositionCard
                                .frame(maxWidth: .infinity)

                            recordingSetupCard
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            captureTargetCard
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            captureSetupInspectorCard
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

    var captureTargetCard: some View {
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
        .overlay {
            if isHelpModeEnabled {
                HelpModeRegionHighlight()
            }
        }
        .overlay(alignment: .topTrailing) {
            HelpModeHintView(topic: .captureTarget, isPresented: isHelpModeEnabled, staggerIndex: 0)
                .frame(width: 280, alignment: .leading)
                .padding(12)
                .allowsHitTesting(false)
        }
    }

    var compositionCard: some View {
        compositionContent
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(cardBackground)
            .overlay {
                if isHelpModeEnabled {
                    HelpModeRegionHighlight()
                }
            }
            .overlay(alignment: .topTrailing) {
                HelpModeHintView(topic: .captureComposition, isPresented: isHelpModeEnabled, staggerIndex: 1)
                    .frame(width: 280, alignment: .leading)
                    .padding(12)
                    .allowsHitTesting(false)
            }
    }

    var captureSetupInspectorCard: some View {
        CaptureSetupInspectorContainer(
            background: { cardBackground },
            composition: { compositionContent },
            recordingSetup: { recordingSetupContent },
            controls: { recordingControlButton }
        )
        .overlay {
            if isHelpModeEnabled {
                HelpModeRegionHighlight()
            }
        }
        .overlay(alignment: .topTrailing) {
            HelpModeHintView(topic: .captureSetup, isPresented: isHelpModeEnabled, staggerIndex: 2)
                .frame(width: 280, alignment: .leading)
                .padding(12)
                .allowsHitTesting(false)
        }
    }

    var compositionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Composition")
                .font(.system(size: 16, weight: .semibold))

            Text("Choose the final video shape now. Live framing preview comes next.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            compositionPreviewFrame

            Text("Drag the preview to reframe.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            compositionReadout
            compositionNudgeControls

            VStack(alignment: .leading, spacing: 8) {
                Text("Aspect Ratio")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker(
                    "Aspect Ratio",
                    selection: Binding(
                        get: { viewModel.compositionLayout.outputAspectRatio },
                        set: { viewModel.setCompositionAspectRatio($0) }
                    )
                ) {
                    ForEach(OutputAspectRatio.allCases) { aspectRatio in
                        Text(aspectRatio.displayName).tag(aspectRatio)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Source Scale")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((viewModel.compositionLayout.sourceScale * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { viewModel.compositionLayout.sourceScale },
                        set: { viewModel.setCompositionSourceScale($0) }
                    ),
                    in: CompositionLayout.sourceScaleRange
                )
            }

            ViewThatFits {
                HStack(spacing: 10) {
                    Button("Center Source") {
                        viewModel.resetCompositionSourceTransform()
                    }
                    Button("Reset Composition") {
                        viewModel.resetCompositionLayout()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("Center Source") {
                        viewModel.resetCompositionSourceTransform()
                    }
                    Button("Reset Composition") {
                        viewModel.resetCompositionLayout()
                    }
                }
            }
        }
    }

    var compositionPreviewFrame: some View {
        CompositionPreviewFrame(
            target: viewModel.selectedTarget,
            layout: viewModel.compositionLayout,
            onOffsetChange: { x, y in
                viewModel.setCompositionSourceOffset(x: x, y: y)
            },
            onResetTransform: {
                viewModel.resetCompositionSourceTransform()
            }
        )
        .frame(height: 136)
    }

    var compositionReadout: some View {
        let layout = viewModel.compositionLayout

        return VStack(alignment: .leading, spacing: 3) {
            Text("Scale: \(Int((layout.sourceScale * 100).rounded()))%")
            Text(String(format: "Offset: X %.2f, Y %.2f", layout.sourceOffsetX, layout.sourceOffsetY))
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    var compositionNudgeControls: some View {
        let step = 0.05

        return HStack(spacing: 8) {
            Button {
                nudgeCompositionOffset(x: 0, y: -step)
            } label: {
                Image(systemName: "arrow.up")
            }
            Button {
                nudgeCompositionOffset(x: -step, y: 0)
            } label: {
                Image(systemName: "arrow.left")
            }
            Button {
                nudgeCompositionOffset(x: step, y: 0)
            } label: {
                Image(systemName: "arrow.right")
            }
            Button {
                nudgeCompositionOffset(x: 0, y: step)
            } label: {
                Image(systemName: "arrow.down")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    func nudgeCompositionOffset(x xDelta: Double, y yDelta: Double) {
        let layout = viewModel.compositionLayout
        viewModel.setCompositionSourceOffset(
            x: layout.sourceOffsetX + xDelta,
            y: layout.sourceOffsetY + yDelta
        )
    }

    var recordingSetupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            recordingSetupContent

            Spacer(minLength: 0)

            recordingControlButton
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay {
            if isHelpModeEnabled {
                HelpModeRegionHighlight()
            }
        }
        .overlay(alignment: .topTrailing) {
            HelpModeHintView(topic: .captureSetup, isPresented: isHelpModeEnabled, staggerIndex: 2)
                .frame(width: 280, alignment: .leading)
                .padding(12)
                .allowsHitTesting(false)
        }
    }

    var recordingSetupContent: some View {
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
        }
    }

    var recordingControlButton: some View {
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
            .foregroundStyle(viewModel.canStopRecording || viewModel.sessionState == .stopping ? .white : accentContrastingTextColor(theme: flowTrackTheme))
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

    var primaryButtonEnabled: Bool {
        if viewModel.canStopRecording || viewModel.sessionState == .stopping {
            return viewModel.canStopRecording
        }
        return viewModel.canStartRecording
    }

    func targetSection(title: String, targets: [ShareableCaptureTarget]) -> some View {
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

    func targetRow(_ target: ShareableCaptureTarget) -> some View {
        let isSelected = viewModel.selectedTargetID == target.id
        let accentColor = FlowTrackAccent.color(for: .capture, theme: flowTrackTheme)

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
                    .foregroundStyle(isSelected ? accentColor : .secondary)
            }
            .padding(14)
            .frame(minHeight: 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                viewModel.activateCaptureTarget(target)
            }
        )
    }
}

private enum CaptureSetupInspectorPane: String, CaseIterable, Identifiable {
    case composition
    case recordingSetup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .composition:
            return "Composition"
        case .recordingSetup:
            return "Recording Setup"
        }
    }
}

private struct CompositionPreviewFrame: View {
    let target: ShareableCaptureTarget?
    let layout: CompositionLayout
    let onOffsetChange: (Double, Double) -> Void
    let onResetTransform: () -> Void

    @State private var dragStartOffset: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let maxSize = CGSize(width: geometry.size.width, height: geometry.size.height)
            let canvasSize = aspectFitSize(
                aspectRatio: CGFloat(layout.outputAspectRatio.ratio),
                in: maxSize
            )

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.38), lineWidth: 1)
                    )
                    .overlay {
                        ZStack {
                            if let target {
                                sourcePreview(target: target, canvasSize: canvasSize)
                                    .gesture(dragGesture(canvasSize: canvasSize))
                            } else {
                                Text("Select a display or window to preview framing.")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .contentShape(Rectangle())
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onResetTransform()
                }
            )
        }
    }

    private func sourcePreview(target: ShareableCaptureTarget, canvasSize: CGSize) -> some View {
        let sourceAspectRatio = CGFloat(max(Double(target.width), 1) / max(Double(target.height), 1))
        let fittedSourceSize = aspectFitSize(aspectRatio: sourceAspectRatio, in: canvasSize)
        let sourceSize = CGSize(
            width: fittedSourceSize.width * layout.sourceScale,
            height: fittedSourceSize.height * layout.sourceScale
        )
        let xOffset = CGFloat(layout.sourceOffsetX) * canvasSize.width * 0.5
        let yOffset = CGFloat(layout.sourceOffsetY) * canvasSize.height * 0.5

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.74), lineWidth: 1)
                )

            VStack(spacing: 3) {
                Text(target.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text("\(target.width)x\(target.height)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
        }
        .frame(width: max(sourceSize.width, 1), height: max(sourceSize.height, 1))
        .offset(x: xOffset, y: yOffset)
    }

    private func dragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startOffset = dragStartOffset ?? CGPoint(
                    x: layout.sourceOffsetX,
                    y: layout.sourceOffsetY
                )
                dragStartOffset = startOffset

                let normalizedXDelta = Double(value.translation.width / max(canvasSize.width * 0.5, 1))
                let normalizedYDelta = Double(value.translation.height / max(canvasSize.height * 0.5, 1))
                onOffsetChange(
                    startOffset.x + normalizedXDelta,
                    startOffset.y + normalizedYDelta
                )
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    private func aspectFitSize(aspectRatio: CGFloat, in boundingSize: CGSize) -> CGSize {
        let safeAspectRatio = max(aspectRatio, 0.001)
        let boundingAspectRatio = max(boundingSize.width, 1) / max(boundingSize.height, 1)

        if boundingAspectRatio > safeAspectRatio {
            let height = boundingSize.height
            return CGSize(width: height * safeAspectRatio, height: height)
        } else {
            let width = boundingSize.width
            return CGSize(width: width, height: width / safeAspectRatio)
        }
    }
}

private struct CaptureSetupInspectorContainer<Background: View, Composition: View, RecordingSetup: View, Controls: View>: View {
    @State private var selectedPane: CaptureSetupInspectorPane = .composition

    let background: Background
    let composition: Composition
    let recordingSetup: RecordingSetup
    let controls: Controls

    init(
        @ViewBuilder background: () -> Background,
        @ViewBuilder composition: () -> Composition,
        @ViewBuilder recordingSetup: () -> RecordingSetup,
        @ViewBuilder controls: () -> Controls
    ) {
        self.background = background()
        self.composition = composition()
        self.recordingSetup = recordingSetup()
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Inspector Pane", selection: $selectedPane) {
                ForEach(CaptureSetupInspectorPane.allCases) { pane in
                    Text(pane.displayName).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedPane {
                case .composition:
                    composition
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .recordingSetup:
                    ScrollView {
                        recordingSetup
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.trailing, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            Divider()

            controls
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }
}
