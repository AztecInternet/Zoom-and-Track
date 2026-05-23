import SwiftUI

extension ContentView {
    var settingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Settings",
                subtitle: "Capture location and permissions",
                accentWidth: 132
            )

            settingsCard(
                title: "Appearance",
                body: AnyView(appearanceSettingsCardBody)
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

            settingsCard(
                title: "Distortion Presets",
                body: AnyView(distortionPresetsSettingsCardBody)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func settingsCard(title: String, body: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            body
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
        .background(cardBackground)
    }

    var appearanceSettingsCardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a saved colour theme for the app interface.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Picker("Colour Theme", selection: Binding(
                get: {
                    flowTrackSelectedThemeID?.uuidString ?? flowTrackSelectedBuiltInThemeID
                },
                set: { selection in
                    if let themeID = UUID(uuidString: selection) {
                        flowTrackThemeActions.selectTheme(themeID)
                    } else {
                        flowTrackThemeActions.selectBuiltInTheme(selection)
                    }
                }
            )) {
                Section("Built-in") {
                    ForEach(FlowTrackThemeDefaults.builtInThemes) { builtInTheme in
                        Text(builtInTheme.name).tag(builtInTheme.id)
                    }
                }
                Section("Custom") {
                    ForEach(flowTrackSavedThemes) { savedTheme in
                        Text(savedTheme.name).tag(savedTheme.id.uuidString)
                    }
                }
            }
            .frame(width: 260)
        }
    }

    var distortionPresetsSettingsCardBody: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom presets save automatically and appear in the Preset dropdown for the Distortion effect.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                List(selection: Binding(
                    get: { viewModel.selectedDistortionPresetLibraryID },
                    set: { newValue in
                        if let newValue {
                            viewModel.selectDistortionPresetLibraryPreset(newValue)
                        }
                    }
                )) {
                    ForEach(viewModel.distortionPresetLibrary.presets.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }) { descriptor in
                        Text(descriptor.displayName)
                            .tag(Optional(descriptor.id))
                    }
                }
                .frame(width: 220, height: 250)

                Button("Add Preset from Image…") {
                    viewModel.createDistortionPresetFromImportedMap()
                }
            }

            distortionPresetDetailEditor
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var distortionPresetDetailEditor: some View {
        if let descriptor = viewModel.selectedCustomDistortionPresetDescriptor {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField(
                        "Preset Name",
                        text: Binding(
                            get: { descriptor.displayName },
                            set: { viewModel.renameSelectedDistortionPreset($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Delete", role: .destructive) {
                        isConfirmingDistortionPresetDelete = true
                    }
                }
                .confirmationDialog(
                    "Delete Distortion Preset?",
                    isPresented: $isConfirmingDistortionPresetDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Preset", role: .destructive) {
                        viewModel.deleteSelectedDistortionPreset()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the selected custom preset from Settings. Existing effect markers keep their saved values.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Imported Map")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(distortionMapSourceSummary(for: descriptor))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let importedMap = distortionImportedMapDetails(for: descriptor) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let width = importedMap.pixelWidth,
                           let height = importedMap.pixelHeight {
                            Text("Resolution: \(width) × \(height)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text("Map ID: \(importedMap.id)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }

                Text("Tune Amount, Turbulence Size, Distortion Blend, and Background Blur in the Distortion effect inspector while viewing the realtime preview.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a custom preset by importing a displacement map image.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if !viewModel.distortionPresetLibrary.presets.isEmpty {
                    Text("Select a custom preset to rename or delete it.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func distortionMapSourceSummary(for descriptor: DistortionPresetDescriptor) -> String {
        switch descriptor.mapSource {
        case .preset:
            return "Built-in displacement map"
        case .importedMap(let id):
            let assetName = viewModel.distortionImportedMapAssets.first(where: { $0.id == id })?.displayName ?? "Imported map"
            return assetName
        }
    }

    func distortionImportedMapDetails(for descriptor: DistortionPresetDescriptor) -> DistortionImportedMapAsset? {
        guard case .importedMap(let id) = descriptor.mapSource else {
            return nil
        }
        return viewModel.distortionImportedMapAssets.first(where: { $0.id == id })
    }
}
