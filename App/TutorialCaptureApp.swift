//
//  TutorialCaptureApp.swift
//  Zoom and Track
//

import SwiftUI

@main
struct TutorialCaptureApp: App {
    private let themeStore = FlowTrackThemeStore()
    @State private var activeFlowTrackTheme = FlowTrackThemeDefaults.standard
    @State private var savedThemes: [FlowTrackSavedTheme] = []
    @State private var selectedThemeID: UUID?
    @State private var selectedBuiltInThemeID = flowTrackBuiltInThemeID
    @State private var builtInThemeOverrides: [String: FlowTrackTheme] = [:]
    @State private var isColourLabPresented = false

    var body: some Scene {
        WindowGroup("FlowTrack Capture") {
            ContentView()
                .environment(\.flowTrackTheme, activeFlowTrackTheme)
                .environment(\.flowTrackSavedThemes, savedThemes)
                .environment(\.flowTrackSelectedThemeID, selectedThemeID)
                .environment(\.flowTrackSelectedBuiltInThemeID, selectedBuiltInThemeID)
                .environment(\.flowTrackThemeActions, themeActions)
                .preferredColorScheme(activeFlowTrackTheme.textScheme.preferredColorScheme)
                .background(
                    FlowTrackColourLabShortcutView {
                        isColourLabPresented.toggle()
                    }
                    .frame(width: 0, height: 0)
                )
                .background(
                    FlowTrackColourLabPanelPresenter(
                        isPresented: $isColourLabPresented,
                        theme: $activeFlowTrackTheme,
                        savedThemes: savedThemes,
                        selectedThemeID: selectedThemeID,
                        selectedBuiltInThemeID: selectedBuiltInThemeID,
                        builtInThemeOverrides: builtInThemeOverrides,
                        actions: themeActions
                    )
                    .frame(width: 0, height: 0)
                )
                .onAppear(perform: loadThemes)
        }
        .commands {
            FlowTrackCommands()
        }
    }

    private var themeActions: FlowTrackThemeActions {
        FlowTrackThemeActions(
            selectTheme: selectTheme(_:),
            selectBuiltInTheme: selectBuiltInTheme(_:),
            saveBuiltInOverride: saveBuiltInOverride(id:theme:),
            saveTheme: saveTheme(name:theme:),
            updateTheme: updateTheme(id:name:theme:),
            deleteTheme: deleteTheme(id:),
            resetToBuiltInDefault: resetToBuiltInDefault
        )
    }

    private func loadThemes() {
        let library = themeStore.loadLibrary()
        savedThemes = library.savedThemes
        selectedThemeID = library.selectedThemeID
        selectedBuiltInThemeID = library.selectedBuiltInThemeID ?? flowTrackBuiltInThemeID
        builtInThemeOverrides = library.builtInOverrides

        if let selectedThemeID,
           let savedTheme = savedThemes.first(where: { $0.id == selectedThemeID }) {
            activeFlowTrackTheme = savedTheme.theme
        } else {
            selectedThemeID = nil
            activeFlowTrackTheme = effectiveBuiltInTheme(withID: selectedBuiltInThemeID)
        }
    }

    private func persistThemes() {
        let library = FlowTrackThemeLibrary(
            savedThemes: savedThemes,
            selectedThemeID: selectedThemeID,
            selectedBuiltInThemeID: selectedThemeID == nil ? selectedBuiltInThemeID : nil,
            builtInOverrides: builtInThemeOverrides
        )
        try? themeStore.saveLibrary(library)
    }

    private func selectTheme(_ themeID: UUID?) {
        selectedThemeID = themeID
        if let themeID,
           let savedTheme = savedThemes.first(where: { $0.id == themeID }) {
            activeFlowTrackTheme = savedTheme.theme
        } else {
            selectedThemeID = nil
            activeFlowTrackTheme = effectiveBuiltInTheme(withID: selectedBuiltInThemeID)
        }
        persistThemes()
    }

    private func selectBuiltInTheme(_ themeID: String) {
        selectedThemeID = nil
        selectedBuiltInThemeID = themeID
        activeFlowTrackTheme = effectiveBuiltInTheme(withID: themeID)
        persistThemes()
    }

    private func saveBuiltInOverride(id: String, theme: FlowTrackTheme) {
        guard FlowTrackThemeDefaults.builtInThemes.contains(where: { $0.id == id }) else { return }
        builtInThemeOverrides[id] = theme
        selectedThemeID = nil
        selectedBuiltInThemeID = id
        activeFlowTrackTheme = theme
        persistThemes()
    }

    private func saveTheme(name: String, theme: FlowTrackTheme) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let finalName = uniqueThemeName(startingWith: trimmedName)

        let now = Date()
        let savedTheme = FlowTrackSavedTheme(
            id: UUID(),
            name: finalName,
            theme: theme,
            createdAt: now,
            updatedAt: now
        )
        savedThemes.append(savedTheme)
        savedThemes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedThemeID = savedTheme.id
        activeFlowTrackTheme = savedTheme.theme
        persistThemes()
    }

    private func updateTheme(id: UUID, name: String, theme: FlowTrackTheme) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = savedThemes.firstIndex(where: { $0.id == id }) else {
            return
        }

        savedThemes[index].name = trimmedName
        savedThemes[index].theme = theme
        savedThemes[index].updatedAt = Date()
        savedThemes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedThemeID = id
        activeFlowTrackTheme = theme
        persistThemes()
    }

    private func deleteTheme(id: UUID) {
        savedThemes.removeAll { $0.id == id }
        if selectedThemeID == id {
            selectedThemeID = nil
            selectedBuiltInThemeID = flowTrackBuiltInThemeID
            activeFlowTrackTheme = effectiveBuiltInTheme(withID: flowTrackBuiltInThemeID)
        }
        persistThemes()
    }

    private func resetToBuiltInDefault() {
        selectedThemeID = nil
        selectedBuiltInThemeID = flowTrackBuiltInThemeID
        activeFlowTrackTheme = effectiveBuiltInTheme(withID: flowTrackBuiltInThemeID)
        persistThemes()
    }

    private func uniqueThemeName(startingWith name: String) -> String {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty else { return "Untitled Theme" }

        let existingNames = Set(savedThemes.map { $0.name.lowercased() })
        if !existingNames.contains(baseName.lowercased()) {
            return baseName
        }

        var index = 2
        while existingNames.contains("\(baseName) \(index)".lowercased()) {
            index += 1
        }
        return "\(baseName) \(index)"
    }

    private func effectiveBuiltInTheme(withID id: String) -> FlowTrackTheme {
        builtInThemeOverrides[id] ?? FlowTrackThemeDefaults.builtInTheme(withID: id)
    }
}
