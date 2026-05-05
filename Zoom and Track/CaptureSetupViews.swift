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
    }

    var recordingSetupCard: some View {
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
}
