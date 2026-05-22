import AppKit
import SwiftUI

struct FlowTrackColourLabView: View {
    @Binding var theme: FlowTrackTheme
    let savedThemes: [FlowTrackSavedTheme]
    let selectedThemeID: UUID?
    let actions: FlowTrackThemeActions
    @State private var selectedToken: FlowTrackColourLabToken = .cardBackground
    @State private var copiedColor: Color?
    @State private var copiedTokenTitle: String?
    @State private var baselineTheme = FlowTrackThemeDefaults.standard
    @State private var baselineSignature = Data()
    @State private var pendingThemeSelectionID: UUID?
    @State private var isConfirmingThemeSwitch = false
    @State private var namingSheet: ColourLabNamingSheet?
    @State private var deleteCandidate: FlowTrackSavedTheme?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Colour Lab")
                    .font(.headline)
                Text("Runtime preview only. Reset restores built-in defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            themeToolbar

            Divider()

            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(FlowTrackColourLabToken.sections, id: \.title) { section in
                            tokenSection(section.title) {
                                ForEach(section.tokens) { token in
                                    tokenRow(token)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(width: 300)
                .frame(maxHeight: 520)

                Divider()
                    .frame(maxHeight: 520)

                colourEditor
                    .frame(width: 300, alignment: .top)
                    .frame(maxHeight: 520, alignment: .top)
            }

            Divider()

            HStack {
                Text(copiedTokenTitle.map { "Copied \($0)" } ?? "Command-C copies, Command-V pastes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 660)
        .onAppear(perform: syncBaselineToSelection)
        .onChange(of: selectedThemeID) { _, _ in
            syncBaselineToSelection()
        }
        .onChange(of: savedThemes) { _, _ in
            syncBaselineToSelectionIfClean()
        }
        .sheet(item: $namingSheet) { sheet in
            ColourLabThemeNameSheet(sheet: sheet) { name in
                createTheme(named: name, mode: sheet.mode)
            }
        }
        .alert("Do you want to save changes to '\(currentThemeName)'?", isPresented: $isConfirmingThemeSwitch) {
            Button("Don't Save", role: .destructive) {
                discardAndSelectPendingTheme()
            }
            Button("Cancel", role: .cancel) {
                pendingThemeSelectionID = nil
            }
            Button("Save") {
                saveCurrentThemeBeforeSwitch()
            }
        } message: {
            Text("Your Colour Lab edits have not been saved.")
        }
        .confirmationDialog(
            "Delete Theme?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Theme", role: .destructive) {
                deleteSelectedTheme()
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map { "Delete '\($0.name)'? This cannot be undone." } ?? "")
        }
        .background(
            ColourLabCopyPasteShortcutView(
                onCopy: {
                    copiedColor = selectedToken.color(in: theme)
                    copiedTokenTitle = selectedToken.title
                },
                onPaste: {
                    guard let copiedColor else { return }
                    selectedToken.setColor(copiedColor, in: &theme)
                }
            )
            .frame(width: 0, height: 0)
        )
    }

    private var currentSavedTheme: FlowTrackSavedTheme? {
        guard let selectedThemeID else { return nil }
        return savedThemes.first { $0.id == selectedThemeID }
    }

    private var currentThemeName: String {
        currentSavedTheme?.name ?? "Built-in Default"
    }

    private var hasUnsavedChanges: Bool {
        themeSignature(theme) != baselineSignature
    }

    private var themeToolbar: some View {
        HStack(spacing: 8) {
            Picker("Theme", selection: Binding(
                get: { selectedThemeID?.uuidString ?? flowTrackBuiltInThemeID },
                set: requestThemeSelection(_:)
            )) {
                Section("Built-in") {
                    Text("Built-in Default").tag(flowTrackBuiltInThemeID)
                }
                Section("Custom") {
                    ForEach(savedThemes) { savedTheme in
                        Text(savedTheme.name).tag(savedTheme.id.uuidString)
                    }
                }
            }
            .frame(width: 250)

            if hasUnsavedChanges {
                Text("Edited")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            Button("Save", action: saveCurrentTheme)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasUnsavedChanges)

            Button("Revert", action: revertWorkingTheme)
                .disabled(!hasUnsavedChanges)

            Button("New") {
                namingSheet = ColourLabNamingSheet(
                    mode: .new,
                    suggestedName: uniqueThemeName(startingWith: "Untitled Theme")
                )
            }

            Button("Duplicate") {
                namingSheet = ColourLabNamingSheet(
                    mode: .duplicate,
                    suggestedName: uniqueThemeName(startingWith: "\(currentThemeName) Copy")
                )
            }

            Spacer(minLength: 12)

            Divider()
                .frame(height: 18)

            Button("Delete Theme", role: .destructive) {
                deleteCandidate = currentSavedTheme
            }
            .disabled(selectedThemeID == nil)
        }
    }

    private func syncBaselineToSelection() {
        let selectedTheme = themeForSelection(selectedThemeID)
        baselineTheme = selectedTheme
        baselineSignature = themeSignature(selectedTheme)
    }

    private func syncBaselineToSelectionIfClean() {
        guard !hasUnsavedChanges else { return }
        syncBaselineToSelection()
    }

    private func requestThemeSelection(_ selection: String) {
        let requestedID = selection == flowTrackBuiltInThemeID ? nil : UUID(uuidString: selection)
        if requestedID == selectedThemeID {
            return
        }

        pendingThemeSelectionID = requestedID
        if hasUnsavedChanges {
            isConfirmingThemeSwitch = true
        } else {
            selectPendingTheme()
        }
    }

    private func selectPendingTheme() {
        let themeID = pendingThemeSelectionID
        pendingThemeSelectionID = nil
        selectTheme(themeID)
    }

    private func selectTheme(_ themeID: UUID?) {
        actions.selectTheme(themeID)
        let selectedTheme = themeForSelection(themeID)
        theme = selectedTheme
        baselineTheme = selectedTheme
        baselineSignature = themeSignature(selectedTheme)
    }

    private func discardAndSelectPendingTheme() {
        selectPendingTheme()
    }

    private func saveCurrentThemeBeforeSwitch() {
        if let selectedThemeID, let savedTheme = currentSavedTheme {
            actions.updateTheme(selectedThemeID, savedTheme.name, theme)
            baselineTheme = theme
            baselineSignature = themeSignature(theme)
        } else {
            actions.saveTheme(uniqueThemeName(startingWith: "Untitled Theme"), theme)
        }
        selectPendingTheme()
    }

    private func saveCurrentTheme() {
        guard let selectedThemeID, let savedTheme = currentSavedTheme else {
            namingSheet = ColourLabNamingSheet(
                mode: .saveNew,
                suggestedName: uniqueThemeName(startingWith: "Untitled Theme")
            )
            return
        }
        actions.updateTheme(selectedThemeID, savedTheme.name, theme)
        baselineTheme = theme
        baselineSignature = themeSignature(theme)
    }

    private func revertWorkingTheme() {
        theme = baselineTheme
    }

    private func createTheme(named name: String, mode: ColourLabNamingSheet.Mode) {
        let finalName = uniqueThemeName(startingWith: name)
        switch mode {
        case .new, .duplicate, .saveNew:
            actions.saveTheme(finalName, theme)
        }
        baselineTheme = theme
        baselineSignature = themeSignature(theme)
    }

    private func deleteSelectedTheme() {
        guard let themeID = deleteCandidate?.id else { return }
        actions.deleteTheme(themeID)
        deleteCandidate = nil
        theme = FlowTrackThemeDefaults.standard
        baselineTheme = FlowTrackThemeDefaults.standard
        baselineSignature = themeSignature(FlowTrackThemeDefaults.standard)
    }

    private func themeForSelection(_ themeID: UUID?) -> FlowTrackTheme {
        guard let themeID,
              let savedTheme = savedThemes.first(where: { $0.id == themeID }) else {
            return FlowTrackThemeDefaults.standard
        }
        return savedTheme.theme
    }

    private func uniqueThemeName(startingWith name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Untitled Theme" : trimmedName
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

    private func themeSignature(_ theme: FlowTrackTheme) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(theme)) ?? Data()
    }

    private func tokenSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func tokenRow(_ token: FlowTrackColourLabToken) -> some View {
        let isSelected = selectedToken == token

        return Button {
            selectedToken = token
        } label: {
            HStack(spacing: 10) {
                Text(token.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
                colourSwatch(token.color(in: theme), size: CGSize(width: 30, height: 16))
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var colourEditor: some View {
        let rgba = ColourLabRGBA(color: selectedToken.color(in: theme))
        let hsba = ColourLabHSBA(color: selectedToken.color(in: theme))

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedToken.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(selectedToken.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SaturationBrightnessSpectrum(
                hue: hsba.hue,
                saturation: hsba.saturation,
                brightness: hsba.brightness,
                onChange: { saturation, brightness in
                    updateSelectedToken(saturation: saturation, brightness: brightness)
                }
            )
            .frame(width: 300, height: 190)

            HueSpectrumSlider(hue: hsba.hue) { hue in
                updateSelectedToken(hue: hue)
            }
            .frame(width: 300, height: 22)

            alphaSlider(value: rgba.alpha) { alpha in
                updateSelectedToken(alpha: alpha)
            }

            colourSwatch(rgba.color, size: CGSize(width: 300, height: 92))
                .overlay(alignment: .bottomTrailing) {
                    Text(rgba.hexString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.42))
                        )
                        .padding(8)
                }

            Text("RGB \(Int((rgba.red * 255).rounded())), \(Int((rgba.green * 255).rounded())), \(Int((rgba.blue * 255).rounded()))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private func alphaSlider(value: Double, update: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text("Alpha")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value },
                    set: { update($0) }
                ),
                in: 0...1
            )
            .tint(.secondary)

            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 24)
    }

    private func updateSelectedToken(hue: Double? = nil, saturation: Double? = nil, brightness: Double? = nil, alpha: Double? = nil) {
        var hsba = ColourLabHSBA(color: selectedToken.color(in: theme))
        if let hue { hsba.hue = hue }
        if let saturation { hsba.saturation = saturation }
        if let brightness { hsba.brightness = brightness }
        if let alpha { hsba.alpha = alpha }
        selectedToken.setColor(hsba.color, in: &theme)
    }

    private func colourSwatch(_ color: Color, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
            )
    }
}

private struct ColourLabNamingSheet: Identifiable {
    enum Mode {
        case new
        case duplicate
        case saveNew

        var title: String {
            switch self {
            case .new: "New Theme"
            case .duplicate: "Duplicate Theme"
            case .saveNew: "Save New Theme"
            }
        }

        var actionTitle: String {
            switch self {
            case .new: "Create"
            case .duplicate: "Duplicate"
            case .saveNew: "Save"
            }
        }
    }

    let id = UUID()
    let mode: Mode
    let suggestedName: String
}

private struct ColourLabThemeNameSheet: View {
    let sheet: ColourLabNamingSheet
    let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var themeName: String

    init(sheet: ColourLabNamingSheet, onCommit: @escaping (String) -> Void) {
        self.sheet = sheet
        self.onCommit = onCommit
        _themeName = State(initialValue: sheet.suggestedName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheet.mode.title)
                .font(.headline)

            TextField("Theme Name", text: $themeName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(sheet.mode.actionTitle) {
                    onCommit(themeName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(themeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct FlowTrackColourLabSection {
    let title: String
    let tokens: [FlowTrackColourLabToken]
}

private enum FlowTrackColourLabToken: String, CaseIterable, Identifiable {
    case cardBackground
    case cardBorder
    case inspectorBackground
    case inspectorBorder
    case editAccent
    case accentButtonText
    case controlStripText
    case controlStripMutedText
    case controlStripBackground
    case controlStripBorder
    case sidebarButtonBackground
    case sidebarButtonText
    case sidebarButtonSelectedBackground
    case sidebarButtonSelectedText
    case timelineRailLight
    case timelineRailDark
    case timelineRuler
    case timelinePlayhead
    case timelinePlayheadText
    case captureAccent
    case libraryAccent
    case zoomAccent
    case effectsAccent
    case settingsAccent

    var id: String { rawValue }

    static let sections: [FlowTrackColourLabSection] = [
        FlowTrackColourLabSection(title: "Surfaces", tokens: [.cardBackground, .cardBorder, .inspectorBackground, .inspectorBorder]),
        FlowTrackColourLabSection(title: "Editor / Control Strips", tokens: [.editAccent, .accentButtonText, .controlStripText, .controlStripMutedText, .controlStripBackground, .controlStripBorder]),
        FlowTrackColourLabSection(title: "Sidebar", tokens: [.sidebarButtonBackground, .sidebarButtonText, .sidebarButtonSelectedBackground, .sidebarButtonSelectedText]),
        FlowTrackColourLabSection(title: "Timeline", tokens: [.timelineRailLight, .timelineRailDark, .timelineRuler, .timelinePlayhead, .timelinePlayheadText]),
        FlowTrackColourLabSection(title: "Role Accents", tokens: [.captureAccent, .libraryAccent, .zoomAccent, .effectsAccent, .settingsAccent])
    ]

    var title: String {
        switch self {
        case .cardBackground: "Card Background"
        case .cardBorder: "Card Border"
        case .inspectorBackground: "Inspector Background"
        case .inspectorBorder: "Inspector Border"
        case .editAccent: "Edit Accent"
        case .accentButtonText: "Accent Button Text"
        case .controlStripText: "Control Strip Text"
        case .controlStripMutedText: "Control Strip Muted Text"
        case .controlStripBackground: "Control Strip Background"
        case .controlStripBorder: "Control Strip Border"
        case .sidebarButtonBackground: "Sidebar Button Background"
        case .sidebarButtonText: "Sidebar Button Text"
        case .sidebarButtonSelectedBackground: "Sidebar Selected Background"
        case .sidebarButtonSelectedText: "Sidebar Selected Text"
        case .timelineRailLight: "Timeline Rail Light"
        case .timelineRailDark: "Timeline Rail Dark"
        case .timelineRuler: "Timeline Ruler"
        case .timelinePlayhead: "Timeline Playhead"
        case .timelinePlayheadText: "Timeline Playhead Text"
        case .captureAccent: "Capture Accent"
        case .libraryAccent: "Library Accent"
        case .zoomAccent: "Zoom & Clicks Accent"
        case .effectsAccent: "Effects Accent"
        case .settingsAccent: "Settings Accent"
        }
    }

    var section: String {
        FlowTrackColourLabToken.sections.first { $0.tokens.contains(self) }?.title ?? ""
    }

    private var keyPath: WritableKeyPath<FlowTrackTheme, Color> {
        switch self {
        case .cardBackground: \.cardBackground
        case .cardBorder: \.cardBorder
        case .inspectorBackground: \.inspectorBackground
        case .inspectorBorder: \.inspectorBorder
        case .editAccent: \.editAccent
        case .accentButtonText: \.accentButtonText
        case .controlStripText: \.controlStripText
        case .controlStripMutedText: \.controlStripMutedText
        case .controlStripBackground: \.controlStripBackground
        case .controlStripBorder: \.controlStripBorder
        case .sidebarButtonBackground: \.sidebarButtonBackground
        case .sidebarButtonText: \.sidebarButtonText
        case .sidebarButtonSelectedBackground: \.sidebarButtonSelectedBackground
        case .sidebarButtonSelectedText: \.sidebarButtonSelectedText
        case .timelineRailLight: \.timelineRailLight
        case .timelineRailDark: \.timelineRailDark
        case .timelineRuler: \.timelineRuler
        case .timelinePlayhead: \.timelinePlayhead
        case .timelinePlayheadText: \.timelinePlayheadText
        case .captureAccent: \.captureAccent
        case .libraryAccent: \.libraryAccent
        case .zoomAccent: \.zoomAccent
        case .effectsAccent: \.effectsAccent
        case .settingsAccent: \.settingsAccent
        }
    }

    func color(in theme: FlowTrackTheme) -> Color {
        theme[keyPath: keyPath]
    }

    func setColor(_ color: Color, in theme: inout FlowTrackTheme) {
        theme[keyPath: keyPath] = color
    }
}

private struct ColourLabRGBA {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            self.init(red: 1, green: 1, blue: 1, alpha: 1)
            return
        }

        self.init(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        let redValue = Int((red * 255).rounded())
        let greenValue = Int((green * 255).rounded())
        let blueValue = Int((blue * 255).rounded())
        let alphaValue = Int((alpha * 255).rounded())
        return String(format: "#%02X%02X%02X %02X", redValue, greenValue, blueValue, alphaValue)
    }
}

private struct ColourLabHSBA {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var alpha: Double

    init(hue: Double, saturation: Double, brightness: Double, alpha: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        self.alpha = alpha
    }

    init(color: Color) {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            self.init(hue: 0, saturation: 0, brightness: 1, alpha: 1)
            return
        }

        self.init(
            hue: Double(nsColor.hueComponent),
            saturation: Double(nsColor.saturationComponent),
            brightness: Double(nsColor.brightnessComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness, opacity: alpha)
    }
}

private struct SaturationBrightnessSpectrum: View {
    let hue: Double
    let saturation: Double
    let brightness: Double
    let onChange: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let thumbX = saturation * size.width
            let thumbY = (1 - brightness) * size.height

            ZStack {
                Rectangle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white, .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .stroke(.white, lineWidth: 2)
                    .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1))
                    .frame(width: 14, height: 14)
                    .position(x: thumbX, y: thumbY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedX = min(max(value.location.x, 0), max(size.width, 1))
                        let clampedY = min(max(value.location.y, 0), max(size.height, 1))
                        onChange(
                            Double(clampedX / max(size.width, 1)),
                            Double(1 - (clampedY / max(size.height, 1)))
                        )
                    }
            )
        }
    }
}

private struct HueSpectrumSlider: View {
    let hue: Double
    let onChange: (Double) -> Void

    private let hueStops: [Color] = [
        .red, .yellow, .green, .cyan, .blue, .purple, .red
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let thumbX = hue * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: hueStops,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.28), lineWidth: 1)

                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedX = min(max(value.location.x, 0), width)
                        onChange(Double(clampedX / width))
                    }
            )
        }
    }
}

private struct ColourLabCopyPasteShortcutView: NSViewRepresentable {
    let onCopy: () -> Void
    let onPaste: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCopy: onCopy, onPaste: onPaste)
    }

    func makeNSView(context: Context) -> ShortcutMonitorView {
        let view = ShortcutMonitorView()
        view.onWindowChanged = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.installMonitor(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutMonitorView, context: Context) {
        context.coordinator.onCopy = onCopy
        context.coordinator.onPaste = onPaste
        context.coordinator.installMonitor(for: nsView)
    }

    final class Coordinator {
        var onCopy: () -> Void
        var onPaste: () -> Void
        private weak var monitoredWindow: NSWindow?
        private var monitor: Any?

        init(onCopy: @escaping () -> Void, onPaste: @escaping () -> Void) {
            self.onCopy = onCopy
            self.onPaste = onPaste
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installMonitor(for view: NSView) {
            guard let window = view.window, window !== monitoredWindow else { return }

            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            monitoredWindow = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                guard let self, event.window === window else { return event }
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      let key = event.charactersIgnoringModifiers?.lowercased() else {
                    return event
                }

                switch key {
                case "c":
                    self.onCopy()
                    return nil
                case "v":
                    self.onPaste()
                    return nil
                default:
                    return event
                }
            }
        }
    }

    final class ShortcutMonitorView: NSView {
        var onWindowChanged: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?()
        }
    }
}

struct FlowTrackColourLabPanelPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var theme: FlowTrackTheme
    let savedThemes: [FlowTrackSavedTheme]
    let selectedThemeID: UUID?
    let actions: FlowTrackThemeActions

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: $isPresented,
            theme: $theme,
            savedThemes: savedThemes,
            selectedThemeID: selectedThemeID,
            actions: actions
        )
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private var panel: NSPanel?
        private var hostingView: NSHostingView<FlowTrackColourLabView>?
        private var isPresented: Binding<Bool>?

        func update(
            isPresented: Binding<Bool>,
            theme: Binding<FlowTrackTheme>,
            savedThemes: [FlowTrackSavedTheme],
            selectedThemeID: UUID?,
            actions: FlowTrackThemeActions
        ) {
            self.isPresented = isPresented

            if isPresented.wrappedValue {
                showPanel(
                    theme: theme,
                    savedThemes: savedThemes,
                    selectedThemeID: selectedThemeID,
                    actions: actions
                )
            } else {
                panel?.orderOut(nil)
            }
        }

        private func showPanel(
            theme: Binding<FlowTrackTheme>,
            savedThemes: [FlowTrackSavedTheme],
            selectedThemeID: UUID?,
            actions: FlowTrackThemeActions
        ) {
            let content = FlowTrackColourLabView(
                theme: theme,
                savedThemes: savedThemes,
                selectedThemeID: selectedThemeID,
                actions: actions
            )

            if let panel, let hostingView {
                hostingView.rootView = content
                panel.makeKeyAndOrderFront(nil)
                return
            }

            let hostingView = NSHostingView(rootView: content)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Colour Lab"
            panel.contentView = hostingView
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.center()
            panel.makeKeyAndOrderFront(nil)

            self.hostingView = hostingView
            self.panel = panel
        }

        func windowWillClose(_ notification: Notification) {
            isPresented?.wrappedValue = false
        }
    }
}

struct FlowTrackColourLabShortcutView: NSViewRepresentable {
    let onToggle: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggle: onToggle)
    }

    func makeNSView(context: Context) -> ShortcutMonitorView {
        let view = ShortcutMonitorView()
        view.onWindowChanged = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.installMonitor(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutMonitorView, context: Context) {
        context.coordinator.onToggle = onToggle
        context.coordinator.installMonitor(for: nsView)
    }

    final class Coordinator {
        var onToggle: () -> Void
        private weak var monitoredWindow: NSWindow?
        private var monitor: Any?

        init(onToggle: @escaping () -> Void) {
            self.onToggle = onToggle
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installMonitor(for view: NSView) {
            guard let window = view.window, window !== monitoredWindow else { return }

            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            monitoredWindow = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                guard let self, event.window === window else { return event }
                guard self.isColourLabShortcut(event) else { return event }

                self.onToggle()
                return nil
            }
        }

        private func isColourLabShortcut(_ event: NSEvent) -> Bool {
            let requiredModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
            let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return activeModifiers == requiredModifiers && event.charactersIgnoringModifiers?.lowercased() == "c"
        }
    }

    final class ShortcutMonitorView: NSView {
        var onWindowChanged: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?()
        }
    }
}
