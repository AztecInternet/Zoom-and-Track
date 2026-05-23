import AppKit
import SwiftUI

let flowTrackBuiltInThemeID = "built-in-default"

struct FlowTrackBuiltInTheme: Identifiable, Equatable {
    var id: String
    var name: String
    var theme: FlowTrackTheme

    static func == (lhs: FlowTrackBuiltInTheme, rhs: FlowTrackBuiltInTheme) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

enum FlowTrackThemeTextScheme: String, Codable, CaseIterable {
    case system
    case lightText
    case darkText

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .lightText:
            return .dark
        case .darkText:
            return .light
        }
    }
}

struct FlowTrackTheme: Codable {
    var textScheme: FlowTrackThemeTextScheme
    var appBackground: Color
    var appBackgroundTint: Color
    var cardBackground: Color
    var cardBorder: Color
    var inspectorBackground: Color
    var inspectorBorder: Color
    var primaryText: Color
    var secondaryText: Color
    var mutedText: Color
    var captureAccent: Color
    var libraryAccent: Color
    var zoomAccent: Color
    var effectsAccent: Color
    var settingsAccent: Color
    var editAccent: Color
    var sidebarButtonBackground: Color
    var sidebarButtonText: Color
    var sidebarButtonSelectedBackground: Color
    var sidebarButtonSelectedText: Color
    var accentButtonText: Color
    var controlStripText: Color
    var controlStripMutedText: Color
    var controlStripBackground: Color
    var controlStripBorder: Color
    var timelineRailLight: Color
    var timelineRailDark: Color
    var timelineRuler: Color
    var timelinePlayhead: Color
    var timelinePlayheadText: Color

    func timelineRailColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light ? timelineRailLight : timelineRailDark
    }

    func accentColor(for role: FlowTrackAccentRole) -> Color {
        switch role {
        case .zoomAndClicks:
            return zoomAccent
        case .effects:
            return effectsAccent
        case .capture:
            return captureAccent
        case .library:
            return libraryAccent
        case .settings:
            return settingsAccent
        }
    }

    enum CodingKeys: String, CodingKey {
        case textScheme
        case appBackground
        case appBackgroundTint
        case cardBackground
        case cardBorder
        case inspectorBackground
        case inspectorBorder
        case primaryText
        case secondaryText
        case mutedText
        case captureAccent
        case libraryAccent
        case zoomAccent
        case effectsAccent
        case settingsAccent
        case editAccent
        case sidebarButtonBackground
        case sidebarButtonText
        case sidebarButtonSelectedBackground
        case sidebarButtonSelectedText
        case accentButtonText
        case controlStripText
        case controlStripMutedText
        case controlStripBackground
        case controlStripBorder
        case timelineRailLight
        case timelineRailDark
        case timelineRuler
        case timelinePlayhead
        case timelinePlayheadText
    }

    init(
        textScheme: FlowTrackThemeTextScheme = .system,
        appBackground: Color,
        appBackgroundTint: Color,
        cardBackground: Color,
        cardBorder: Color,
        inspectorBackground: Color,
        inspectorBorder: Color,
        primaryText: Color,
        secondaryText: Color,
        mutedText: Color,
        captureAccent: Color,
        libraryAccent: Color,
        zoomAccent: Color,
        effectsAccent: Color,
        settingsAccent: Color,
        editAccent: Color,
        sidebarButtonBackground: Color,
        sidebarButtonText: Color,
        sidebarButtonSelectedBackground: Color,
        sidebarButtonSelectedText: Color,
        accentButtonText: Color,
        controlStripText: Color,
        controlStripMutedText: Color,
        controlStripBackground: Color,
        controlStripBorder: Color,
        timelineRailLight: Color,
        timelineRailDark: Color,
        timelineRuler: Color,
        timelinePlayhead: Color,
        timelinePlayheadText: Color
    ) {
        self.textScheme = textScheme
        self.appBackground = appBackground
        self.appBackgroundTint = appBackgroundTint
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.inspectorBackground = inspectorBackground
        self.inspectorBorder = inspectorBorder
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.mutedText = mutedText
        self.captureAccent = captureAccent
        self.libraryAccent = libraryAccent
        self.zoomAccent = zoomAccent
        self.effectsAccent = effectsAccent
        self.settingsAccent = settingsAccent
        self.editAccent = editAccent
        self.sidebarButtonBackground = sidebarButtonBackground
        self.sidebarButtonText = sidebarButtonText
        self.sidebarButtonSelectedBackground = sidebarButtonSelectedBackground
        self.sidebarButtonSelectedText = sidebarButtonSelectedText
        self.accentButtonText = accentButtonText
        self.controlStripText = controlStripText
        self.controlStripMutedText = controlStripMutedText
        self.controlStripBackground = controlStripBackground
        self.controlStripBorder = controlStripBorder
        self.timelineRailLight = timelineRailLight
        self.timelineRailDark = timelineRailDark
        self.timelineRuler = timelineRuler
        self.timelinePlayhead = timelinePlayhead
        self.timelinePlayheadText = timelinePlayheadText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            textScheme: try container.decodeIfPresent(FlowTrackThemeTextScheme.self, forKey: .textScheme) ?? .system,
            appBackground: try container.decode(FlowTrackCodableColor.self, forKey: .appBackground).color,
            appBackgroundTint: try container.decode(FlowTrackCodableColor.self, forKey: .appBackgroundTint).color,
            cardBackground: try container.decode(FlowTrackCodableColor.self, forKey: .cardBackground).color,
            cardBorder: try container.decode(FlowTrackCodableColor.self, forKey: .cardBorder).color,
            inspectorBackground: try container.decode(FlowTrackCodableColor.self, forKey: .inspectorBackground).color,
            inspectorBorder: try container.decode(FlowTrackCodableColor.self, forKey: .inspectorBorder).color,
            primaryText: try container.decode(FlowTrackCodableColor.self, forKey: .primaryText).color,
            secondaryText: try container.decode(FlowTrackCodableColor.self, forKey: .secondaryText).color,
            mutedText: try container.decode(FlowTrackCodableColor.self, forKey: .mutedText).color,
            captureAccent: try container.decode(FlowTrackCodableColor.self, forKey: .captureAccent).color,
            libraryAccent: try container.decode(FlowTrackCodableColor.self, forKey: .libraryAccent).color,
            zoomAccent: try container.decode(FlowTrackCodableColor.self, forKey: .zoomAccent).color,
            effectsAccent: try container.decode(FlowTrackCodableColor.self, forKey: .effectsAccent).color,
            settingsAccent: try container.decode(FlowTrackCodableColor.self, forKey: .settingsAccent).color,
            editAccent: try container.decode(FlowTrackCodableColor.self, forKey: .editAccent).color,
            sidebarButtonBackground: try container.decode(FlowTrackCodableColor.self, forKey: .sidebarButtonBackground).color,
            sidebarButtonText: try container.decode(FlowTrackCodableColor.self, forKey: .sidebarButtonText).color,
            sidebarButtonSelectedBackground: try container.decode(FlowTrackCodableColor.self, forKey: .sidebarButtonSelectedBackground).color,
            sidebarButtonSelectedText: try container.decode(FlowTrackCodableColor.self, forKey: .sidebarButtonSelectedText).color,
            accentButtonText: try container.decode(FlowTrackCodableColor.self, forKey: .accentButtonText).color,
            controlStripText: try container.decode(FlowTrackCodableColor.self, forKey: .controlStripText).color,
            controlStripMutedText: try container.decode(FlowTrackCodableColor.self, forKey: .controlStripMutedText).color,
            controlStripBackground: try container.decode(FlowTrackCodableColor.self, forKey: .controlStripBackground).color,
            controlStripBorder: try container.decode(FlowTrackCodableColor.self, forKey: .controlStripBorder).color,
            timelineRailLight: try container.decode(FlowTrackCodableColor.self, forKey: .timelineRailLight).color,
            timelineRailDark: try container.decode(FlowTrackCodableColor.self, forKey: .timelineRailDark).color,
            timelineRuler: try container.decode(FlowTrackCodableColor.self, forKey: .timelineRuler).color,
            timelinePlayhead: try container.decode(FlowTrackCodableColor.self, forKey: .timelinePlayhead).color,
            timelinePlayheadText: try container.decode(FlowTrackCodableColor.self, forKey: .timelinePlayheadText).color
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(textScheme, forKey: .textScheme)
        try container.encode(FlowTrackCodableColor(appBackground), forKey: .appBackground)
        try container.encode(FlowTrackCodableColor(appBackgroundTint), forKey: .appBackgroundTint)
        try container.encode(FlowTrackCodableColor(cardBackground), forKey: .cardBackground)
        try container.encode(FlowTrackCodableColor(cardBorder), forKey: .cardBorder)
        try container.encode(FlowTrackCodableColor(inspectorBackground), forKey: .inspectorBackground)
        try container.encode(FlowTrackCodableColor(inspectorBorder), forKey: .inspectorBorder)
        try container.encode(FlowTrackCodableColor(primaryText), forKey: .primaryText)
        try container.encode(FlowTrackCodableColor(secondaryText), forKey: .secondaryText)
        try container.encode(FlowTrackCodableColor(mutedText), forKey: .mutedText)
        try container.encode(FlowTrackCodableColor(captureAccent), forKey: .captureAccent)
        try container.encode(FlowTrackCodableColor(libraryAccent), forKey: .libraryAccent)
        try container.encode(FlowTrackCodableColor(zoomAccent), forKey: .zoomAccent)
        try container.encode(FlowTrackCodableColor(effectsAccent), forKey: .effectsAccent)
        try container.encode(FlowTrackCodableColor(settingsAccent), forKey: .settingsAccent)
        try container.encode(FlowTrackCodableColor(editAccent), forKey: .editAccent)
        try container.encode(FlowTrackCodableColor(sidebarButtonBackground), forKey: .sidebarButtonBackground)
        try container.encode(FlowTrackCodableColor(sidebarButtonText), forKey: .sidebarButtonText)
        try container.encode(FlowTrackCodableColor(sidebarButtonSelectedBackground), forKey: .sidebarButtonSelectedBackground)
        try container.encode(FlowTrackCodableColor(sidebarButtonSelectedText), forKey: .sidebarButtonSelectedText)
        try container.encode(FlowTrackCodableColor(accentButtonText), forKey: .accentButtonText)
        try container.encode(FlowTrackCodableColor(controlStripText), forKey: .controlStripText)
        try container.encode(FlowTrackCodableColor(controlStripMutedText), forKey: .controlStripMutedText)
        try container.encode(FlowTrackCodableColor(controlStripBackground), forKey: .controlStripBackground)
        try container.encode(FlowTrackCodableColor(controlStripBorder), forKey: .controlStripBorder)
        try container.encode(FlowTrackCodableColor(timelineRailLight), forKey: .timelineRailLight)
        try container.encode(FlowTrackCodableColor(timelineRailDark), forKey: .timelineRailDark)
        try container.encode(FlowTrackCodableColor(timelineRuler), forKey: .timelineRuler)
        try container.encode(FlowTrackCodableColor(timelinePlayhead), forKey: .timelinePlayhead)
        try container.encode(FlowTrackCodableColor(timelinePlayheadText), forKey: .timelinePlayheadText)
    }
}

struct FlowTrackCodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: Color) {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            self.red = 1
            self.green = 1
            self.blue = 1
            self.alpha = 1
            return
        }

        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        self.alpha = Double(nsColor.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct FlowTrackSavedTheme: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var theme: FlowTrackTheme
    var createdAt: Date
    var updatedAt: Date

    static func == (lhs: FlowTrackSavedTheme, rhs: FlowTrackSavedTheme) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt
    }
}

struct FlowTrackThemeLibrary: Codable {
    var savedThemes: [FlowTrackSavedTheme] = []
    var selectedThemeID: UUID?
    var selectedBuiltInThemeID: String?
    var builtInOverrides: [String: FlowTrackTheme] = [:]

    enum CodingKeys: String, CodingKey {
        case savedThemes
        case selectedThemeID
        case selectedBuiltInThemeID
        case builtInOverrides
    }

    init(
        savedThemes: [FlowTrackSavedTheme] = [],
        selectedThemeID: UUID? = nil,
        selectedBuiltInThemeID: String? = nil,
        builtInOverrides: [String: FlowTrackTheme] = [:]
    ) {
        self.savedThemes = savedThemes
        self.selectedThemeID = selectedThemeID
        self.selectedBuiltInThemeID = selectedBuiltInThemeID
        self.builtInOverrides = builtInOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedThemes = try container.decodeIfPresent([FlowTrackSavedTheme].self, forKey: .savedThemes) ?? []
        selectedThemeID = try container.decodeIfPresent(UUID.self, forKey: .selectedThemeID)
        selectedBuiltInThemeID = try container.decodeIfPresent(String.self, forKey: .selectedBuiltInThemeID)
        builtInOverrides = try container.decodeIfPresent([String: FlowTrackTheme].self, forKey: .builtInOverrides) ?? [:]
    }
}

struct FlowTrackThemeActions {
    var selectTheme: (UUID?) -> Void = { _ in }
    var selectBuiltInTheme: (String) -> Void = { _ in }
    var saveBuiltInOverride: (String, FlowTrackTheme) -> Void = { _, _ in }
    var saveTheme: (String, FlowTrackTheme) -> Void = { _, _ in }
    var updateTheme: (UUID, String, FlowTrackTheme) -> Void = { _, _, _ in }
    var deleteTheme: (UUID) -> Void = { _ in }
    var resetToBuiltInDefault: () -> Void = {}
}

enum FlowTrackThemeDefaults {
    static var standard: FlowTrackTheme {
        builtInTheme(withID: flowTrackBuiltInThemeID)
    }

    static var builtInThemes: [FlowTrackBuiltInTheme] {
        [
            FlowTrackBuiltInTheme(id: flowTrackBuiltInThemeID, name: "Built-in Default", theme: defaultTheme),
            FlowTrackBuiltInTheme(id: "midnight-neon", name: "Midnight Neon", theme: theme(
                textScheme: .lightText, app: c(0.035, 0.040, 0.060), tint: c(0.08, 0.20, 0.34, 0.28), card: c(0.070, 0.080, 0.110, 0.92), border: c(0.45, 0.65, 0.95, 0.20),
                text: c(0.92, 0.96, 1.0), secondary: c(0.66, 0.73, 0.82), muted: c(0.46, 0.53, 0.63),
                capture: c(0.18, 0.86, 0.55), library: c(1.0, 0.58, 0.22), zoom: c(0.16, 0.52, 1.0), effects: c(0.95, 0.21, 0.68), settings: c(0.52, 0.45, 1.0),
                edit: c(0.95, 0.22, 0.58), sidebar: c(0.04, 0.05, 0.07, 0), sidebarText: c(0.88, 0.92, 1.0), sidebarSelected: c(0.95, 0.22, 0.58), sidebarSelectedText: c(1, 1, 1),
                buttonText: c(1, 1, 1), stripText: c(0.42, 0.68, 1.0), stripMuted: c(0.60, 0.66, 0.76), stripBackground: c(0.12, 0.14, 0.18, 0.82), stripBorder: c(0.40, 0.55, 0.78, 0.22),
                railLight: c(0.30, 0.34, 0.44), railDark: c(0.24, 0.28, 0.36, 0.743102669716), ruler: c(0.82, 0.88, 0.96), playhead: c(0.22, 0.55, 1.0), playheadText: c(0.86, 0.91, 0.98)
            )),
            FlowTrackBuiltInTheme(id: "graphite-pro", name: "Graphite Pro", theme: theme(
                textScheme: .lightText, app: c(0.10, 0.105, 0.11), tint: c(0.18, 0.18, 0.20, 0.25), card: c(0.145, 0.15, 0.16, 0.92), border: c(0.58, 0.60, 0.64, 0.22),
                text: c(0.92, 0.93, 0.95), secondary: c(0.70, 0.72, 0.76), muted: c(0.50, 0.52, 0.56),
                capture: c(0.35, 0.78, 0.48), library: c(0.94, 0.56, 0.24), zoom: c(0.33, 0.58, 0.95), effects: c(0.92, 0.36, 0.55), settings: c(0.60, 0.58, 0.82),
                edit: c(0.74, 0.37, 0.52), sidebar: c(0, 0, 0, 0), sidebarText: c(0.90, 0.91, 0.93), sidebarSelected: c(0.74, 0.37, 0.52), sidebarSelectedText: c(1, 1, 1),
                buttonText: c(1, 1, 1), stripText: c(0.33, 0.58, 0.95), stripMuted: c(0.62, 0.64, 0.68), stripBackground: c(0.18, 0.19, 0.20, 0.88), stripBorder: c(0.56, 0.58, 0.62, 0.18),
                railLight: c(0.34, 0.35, 0.38), railDark: c(0.30, 0.31, 0.34, 0.565464913845), ruler: c(0.90, 0.91, 0.93), playhead: c(0.34, 0.58, 0.95), playheadText: c(0.82, 0.84, 0.88)
            )),
            FlowTrackBuiltInTheme(id: "oled-night", name: "OLED Night", theme: theme(
                textScheme: .lightText, app: .black, tint: c(0.0, 0.08, 0.16, 0.35), card: c(0.018, 0.020, 0.025, 0.98), border: c(0.34, 0.44, 0.56, 0.24),
                text: c(0.96, 0.98, 1.0), secondary: c(0.72, 0.76, 0.82), muted: c(0.48, 0.52, 0.60),
                capture: c(0.13, 0.92, 0.58), library: c(1.0, 0.48, 0.14), zoom: c(0.05, 0.48, 1.0), effects: c(0.96, 0.12, 0.44), settings: c(0.47, 0.42, 1.0),
                edit: c(0.96, 0.12, 0.44), sidebar: .clear, sidebarText: c(0.92, 0.95, 1.0), sidebarSelected: c(0.96, 0.12, 0.44), sidebarSelectedText: .white,
                buttonText: .white, stripText: c(0.15, 0.58, 1.0), stripMuted: c(0.66, 0.70, 0.78), stripBackground: c(0.06, 0.07, 0.09, 0.94), stripBorder: c(0.30, 0.38, 0.50, 0.24),
                railLight: c(0.22, 0.24, 0.30), railDark: c(0.16, 0.18, 0.23), ruler: c(0.92, 0.95, 1.0), playhead: c(0.10, 0.48, 1.0), playheadText: c(0.82, 0.88, 0.96)
            )),
            FlowTrackBuiltInTheme(id: "matcha-studio", name: "Matcha Studio", theme: theme(
                textScheme: .darkText, app: c(0.83, 0.87, 0.80), tint: c(0.49, 0.63, 0.42, 0.22), card: c(0.90, 0.92, 0.86, 0.90), border: c(0.37, 0.45, 0.33, 0.22),
                text: c(0.13, 0.17, 0.13), secondary: c(0.33, 0.38, 0.31), muted: c(0.48, 0.53, 0.44),
                capture: c(0.20, 0.58, 0.32), library: c(0.74, 0.46, 0.20), zoom: c(0.22, 0.48, 0.68), effects: c(0.64, 0.34, 0.48), settings: c(0.44, 0.42, 0.68),
                edit: c(0.20, 0.50, 0.36), sidebar: c(0, 0, 0, 0), sidebarText: c(0.14, 0.18, 0.14), sidebarSelected: c(0.20, 0.50, 0.36), sidebarSelectedText: c(1, 1, 1),
                buttonText: c(1, 1, 1), stripText: c(0.18, 0.42, 0.30), stripMuted: c(0.44, 0.49, 0.40), stripBackground: c(0.78, 0.82, 0.74, 0.70), stripBorder: c(0.42, 0.50, 0.36, 0.22),
                railLight: c(0.50, 0.57, 0.46, 0.243236601353), railDark: c(0.40, 0.48, 0.38), ruler: c(0.18, 0.22, 0.18), playhead: c(0.16, 0.46, 0.34), playheadText: c(0.22, 0.26, 0.22)
            )),
            FlowTrackBuiltInTheme(id: "amber-edit", name: "Amber Edit", theme: theme(
                textScheme: .lightText, app: c(0.14, 0.105, 0.075), tint: c(0.70, 0.38, 0.12, 0.24), card: c(0.20, 0.155, 0.115, 0.92), border: c(0.95, 0.61, 0.26, 0.22),
                text: c(0.98, 0.91, 0.82), secondary: c(0.78, 0.68, 0.58), muted: c(0.58, 0.49, 0.42),
                capture: c(0.44, 0.78, 0.38), library: c(1.0, 0.58, 0.18), zoom: c(0.98, 0.64, 0.22), effects: c(0.90, 0.34, 0.24), settings: c(0.78, 0.50, 0.26),
                edit: c(0.92, 0.42, 0.20), sidebar: .clear, sidebarText: c(0.96, 0.88, 0.78), sidebarSelected: c(0.92, 0.42, 0.20), sidebarSelectedText: c(0.10, 0.07, 0.05),
                buttonText: c(0.10, 0.07, 0.05), stripText: c(1.0, 0.64, 0.24), stripMuted: c(0.74, 0.64, 0.54), stripBackground: c(0.25, 0.19, 0.14, 0.86), stripBorder: c(0.84, 0.54, 0.24, 0.22),
                railLight: c(0.55, 0.40, 0.28), railDark: c(0.38, 0.29, 0.22), ruler: c(0.96, 0.86, 0.74), playhead: c(1.0, 0.58, 0.18), playheadText: c(0.92, 0.82, 0.70)
            )),
            FlowTrackBuiltInTheme(id: "arctic-glass", name: "Arctic Glass", theme: theme(
                textScheme: .darkText, app: c(0.86, 0.91, 0.96), tint: c(0.35, 0.62, 0.88, 0.18), card: c(0.94, 0.97, 1.0, 0.78), border: c(0.38, 0.56, 0.72, 0.26),
                text: c(0.10, 0.16, 0.23), secondary: c(0.34, 0.42, 0.52), muted: c(0.52, 0.60, 0.70),
                capture: c(0.18, 0.64, 0.55), library: c(0.82, 0.48, 0.20), zoom: c(0.14, 0.45, 0.78), effects: c(0.70, 0.32, 0.55), settings: c(0.38, 0.42, 0.78),
                edit: c(0.14, 0.45, 0.78), sidebar: c(0, 0, 0, 0), sidebarText: c(0.12, 0.18, 0.26), sidebarSelected: c(0.14, 0.45, 0.78), sidebarSelectedText: c(1, 1, 1),
                buttonText: c(1, 1, 1), stripText: c(0.10, 0.38, 0.70), stripMuted: c(0.48, 0.56, 0.66), stripBackground: c(0.84, 0.90, 0.96, 0.70), stripBorder: c(0.34, 0.50, 0.66, 0.22),
                railLight: c(0.46, 0.55, 0.65, 0.337008923292), railDark: c(0.36, 0.45, 0.55), ruler: c(0.11, 0.17, 0.25), playhead: c(0.10, 0.42, 0.82), playheadText: c(0.28, 0.36, 0.46)
            )),
            FlowTrackBuiltInTheme(id: "crimson-cut", name: "Crimson Cut", theme: theme(
                textScheme: .lightText, app: c(0.090, 0.045, 0.055), tint: c(0.55, 0.05, 0.14, 0.30), card: c(0.14, 0.07, 0.085, 0.94), border: c(0.90, 0.22, 0.34, 0.24),
                text: c(0.98, 0.91, 0.93), secondary: c(0.78, 0.66, 0.70), muted: c(0.58, 0.48, 0.52),
                capture: c(0.28, 0.78, 0.46), library: c(0.95, 0.52, 0.22), zoom: c(0.36, 0.52, 0.98), effects: c(0.96, 0.18, 0.34), settings: c(0.72, 0.42, 0.88),
                edit: c(0.90, 0.16, 0.30), sidebar: .clear, sidebarText: c(0.96, 0.88, 0.91), sidebarSelected: c(0.90, 0.16, 0.30), sidebarSelectedText: .white,
                buttonText: .white, stripText: c(0.98, 0.25, 0.38), stripMuted: c(0.74, 0.62, 0.66), stripBackground: c(0.18, 0.09, 0.11, 0.86), stripBorder: c(0.82, 0.18, 0.30, 0.22),
                railLight: c(0.48, 0.28, 0.32), railDark: c(0.30, 0.20, 0.23), ruler: c(0.96, 0.88, 0.91), playhead: c(0.98, 0.22, 0.36), playheadText: c(0.88, 0.78, 0.82)
            )),
            FlowTrackBuiltInTheme(id: "indigo-flow", name: "Indigo Flow", theme: theme(
                textScheme: .lightText, app: c(0.07, 0.07, 0.13), tint: c(0.32, 0.26, 0.74, 0.30), card: c(0.105, 0.105, 0.18, 0.92), border: c(0.50, 0.46, 0.92, 0.24),
                text: c(0.93, 0.92, 1.0), secondary: c(0.70, 0.70, 0.84), muted: c(0.52, 0.52, 0.66),
                capture: c(0.24, 0.80, 0.60), library: c(0.94, 0.56, 0.22), zoom: c(0.38, 0.56, 1.0), effects: c(0.74, 0.34, 1.0), settings: c(0.52, 0.48, 1.0),
                edit: c(0.52, 0.42, 0.95), sidebar: .clear, sidebarText: c(0.90, 0.90, 0.98), sidebarSelected: c(0.52, 0.42, 0.95), sidebarSelectedText: .white,
                buttonText: .white, stripText: c(0.58, 0.66, 1.0), stripMuted: c(0.66, 0.66, 0.80), stripBackground: c(0.14, 0.14, 0.24, 0.86), stripBorder: c(0.48, 0.44, 0.84, 0.22),
                railLight: c(0.34, 0.34, 0.50), railDark: c(0.25, 0.25, 0.38), ruler: c(0.92, 0.92, 1.0), playhead: c(0.42, 0.58, 1.0), playheadText: c(0.82, 0.82, 0.94)
            )),
            FlowTrackBuiltInTheme(id: "desert-grade", name: "Desert Grade", theme: theme(
                textScheme: .darkText, app: c(0.76, 0.66, 0.52), tint: c(0.62, 0.42, 0.22, 0.20), card: c(0.84, 0.74, 0.60, 0.88), border: c(0.42, 0.30, 0.20, 0.22),
                text: c(0.18, 0.13, 0.09), secondary: c(0.38, 0.30, 0.23), muted: c(0.54, 0.44, 0.36),
                capture: c(0.35, 0.56, 0.30), library: c(0.78, 0.40, 0.18), zoom: c(0.22, 0.42, 0.60), effects: c(0.62, 0.28, 0.36), settings: c(0.46, 0.38, 0.62),
                edit: c(0.72, 0.32, 0.18), sidebar: c(0, 0, 0, 0), sidebarText: c(0.18, 0.13, 0.09), sidebarSelected: c(0.72, 0.32, 0.18), sidebarSelectedText: c(1, 1, 1),
                buttonText: c(1, 1, 1), stripText: c(0.58, 0.26, 0.14), stripMuted: c(0.48, 0.38, 0.30), stripBackground: c(0.70, 0.60, 0.48, 0.72), stripBorder: c(0.42, 0.30, 0.20, 0.22),
                railLight: c(0.46, 0.36, 0.26, 0.246568232775), railDark: c(0.38, 0.30, 0.23), ruler: c(0.18, 0.13, 0.09), playhead: c(0.74, 0.32, 0.18), playheadText: c(0.30, 0.22, 0.16)
            )),
            FlowTrackBuiltInTheme(id: "vector-lime", name: "Vector Lime", theme: theme(
                textScheme: .lightText, app: c(0.035, 0.055, 0.045), tint: c(0.38, 0.88, 0.22, 0.20), card: c(0.055, 0.080, 0.065, 0.94), border: c(0.48, 0.92, 0.28, 0.22),
                text: c(0.90, 1.0, 0.86), secondary: c(0.68, 0.80, 0.64), muted: c(0.48, 0.60, 0.46),
                capture: c(0.34, 0.96, 0.32), library: c(0.95, 0.64, 0.18), zoom: c(0.40, 0.82, 0.32), effects: c(0.82, 0.34, 0.62), settings: c(0.50, 0.62, 0.96),
                edit: c(0.34, 0.92, 0.28), sidebar: .clear, sidebarText: c(0.90, 1.0, 0.86), sidebarSelected: c(0.34, 0.92, 0.28), sidebarSelectedText: c(0.02, 0.05, 0.03),
                buttonText: c(0.02, 0.05, 0.03), stripText: c(0.48, 1.0, 0.36), stripMuted: c(0.62, 0.76, 0.58), stripBackground: c(0.08, 0.12, 0.09, 0.88), stripBorder: c(0.42, 0.86, 0.28, 0.22),
                railLight: c(0.32, 0.46, 0.28), railDark: c(0.20, 0.30, 0.18), ruler: c(0.88, 1.0, 0.82), playhead: c(0.46, 1.0, 0.28), playheadText: c(0.76, 0.90, 0.72)
            )),
            FlowTrackBuiltInTheme(id: "nord-dark", name: "Nord Dark", theme: theme(
                textScheme: .lightText, app: c(0.13, 0.16, 0.20), tint: c(0.36, 0.51, 0.67, 0.20), card: c(0.18, 0.22, 0.27, 0.90), border: c(0.50, 0.58, 0.68, 0.18),
                text: c(0.90, 0.93, 0.96), secondary: c(0.72, 0.77, 0.83), muted: c(0.54, 0.60, 0.68),
                capture: c(0.64, 0.75, 0.55), library: c(0.92, 0.62, 0.42), zoom: c(0.53, 0.75, 0.82), effects: c(0.71, 0.56, 0.68), settings: c(0.50, 0.58, 0.78),
                edit: c(0.50, 0.58, 0.78), sidebar: .clear, sidebarText: c(0.90, 0.93, 0.96), sidebarSelected: c(0.50, 0.58, 0.78), sidebarSelectedText: c(0.10, 0.13, 0.17),
                buttonText: c(0.10, 0.13, 0.17), stripText: c(0.53, 0.75, 0.82), stripMuted: c(0.66, 0.72, 0.80), stripBackground: c(0.21, 0.25, 0.31, 0.86), stripBorder: c(0.48, 0.56, 0.66, 0.20),
                railLight: c(0.40, 0.46, 0.54), railDark: c(0.31, 0.36, 0.44), ruler: c(0.90, 0.93, 0.96), playhead: c(0.53, 0.75, 0.82), playheadText: c(0.76, 0.82, 0.90)
            )),
            FlowTrackBuiltInTheme(id: "high-contrast", name: "High Contrast", theme: theme(
                textScheme: .lightText, app: .black, tint: c(0.0, 0.0, 0.0, 0), card: c(0.03, 0.03, 0.03, 1.0), border: c(1.0, 1.0, 1.0, 0.42),
                text: .white, secondary: c(0.88, 0.88, 0.88), muted: c(0.72, 0.72, 0.72),
                capture: c(0.0, 1.0, 0.42), library: c(1.0, 0.72, 0.0), zoom: c(0.0, 0.62, 1.0), effects: c(1.0, 0.20, 0.60), settings: c(0.72, 0.62, 1.0),
                edit: c(1.0, 0.22, 0.50), sidebar: .clear, sidebarText: .white, sidebarSelected: c(1.0, 0.22, 0.50), sidebarSelectedText: .black,
                buttonText: .black, stripText: .white, stripMuted: c(0.82, 0.82, 0.82), stripBackground: c(0.08, 0.08, 0.08, 1.0), stripBorder: c(1.0, 1.0, 1.0, 0.36),
                railLight: c(0.46, 0.46, 0.46), railDark: c(0.38, 0.38, 0.38), ruler: .white, playhead: c(0.0, 0.62, 1.0), playheadText: .white
            ))
        ]
    }

    static func builtInTheme(withID id: String?) -> FlowTrackTheme {
        builtInThemes.first { $0.id == id }?.theme ?? defaultTheme
    }

    static func builtInThemeName(withID id: String?) -> String {
        builtInThemes.first { $0.id == id }?.name ?? "Built-in Default"
    }

    private static var defaultTheme: FlowTrackTheme {
        FlowTrackTheme(
            appBackground: Color(nsColor: .windowBackgroundColor),
            appBackgroundTint: Color.accentColor.opacity(0.20),
            cardBackground: Color(nsColor: .controlBackgroundColor).opacity(0.55),
            cardBorder: Color.secondary.opacity(0.12),
            inspectorBackground: Color(nsColor: .controlBackgroundColor).opacity(0.55),
            inspectorBorder: Color.secondary.opacity(0.12),
            primaryText: .primary,
            secondaryText: .secondary,
            mutedText: Color.secondary.opacity(0.72),
            captureAccent: .green,
            libraryAccent: .orange,
            zoomAccent: .blue,
            effectsAccent: .pink,
            settingsAccent: .indigo,
            editAccent: .blue,
            sidebarButtonBackground: Color.clear,
            sidebarButtonText: .primary,
            sidebarButtonSelectedBackground: .accentColor,
            sidebarButtonSelectedText: .white,
            accentButtonText: .white,
            controlStripText: .accentColor,
            controlStripMutedText: .secondary,
            controlStripBackground: Color.secondary.opacity(0.1),
            controlStripBorder: Color.secondary.opacity(0.1),
            timelineRailLight: Color.secondary.opacity(0.16),
            timelineRailDark: Color.secondary.opacity(0.16),
            timelineRuler: .primary,
            timelinePlayhead: .accentColor,
            timelinePlayheadText: .secondary
        )
    }

    private static func c(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1.0) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    private static func theme(
        textScheme: FlowTrackThemeTextScheme,
        app: Color, tint: Color, card: Color, border: Color,
        text: Color, secondary: Color, muted: Color,
        capture: Color, library: Color, zoom: Color, effects: Color, settings: Color,
        edit: Color, sidebar: Color, sidebarText: Color, sidebarSelected: Color, sidebarSelectedText: Color,
        buttonText: Color, stripText: Color, stripMuted: Color, stripBackground: Color, stripBorder: Color,
        railLight: Color, railDark: Color, ruler: Color, playhead: Color, playheadText: Color
    ) -> FlowTrackTheme {
        FlowTrackTheme(
            textScheme: textScheme,
            appBackground: app,
            appBackgroundTint: tint,
            cardBackground: card,
            cardBorder: border,
            inspectorBackground: card,
            inspectorBorder: border,
            primaryText: text,
            secondaryText: secondary,
            mutedText: muted,
            captureAccent: capture,
            libraryAccent: library,
            zoomAccent: zoom,
            effectsAccent: effects,
            settingsAccent: settings,
            editAccent: edit,
            sidebarButtonBackground: sidebar,
            sidebarButtonText: sidebarText,
            sidebarButtonSelectedBackground: sidebarSelected,
            sidebarButtonSelectedText: sidebarSelectedText,
            accentButtonText: buttonText,
            controlStripText: stripText,
            controlStripMutedText: stripMuted,
            controlStripBackground: stripBackground,
            controlStripBorder: stripBorder,
            timelineRailLight: railLight,
            timelineRailDark: railDark,
            timelineRuler: ruler,
            timelinePlayhead: playhead,
            timelinePlayheadText: playheadText
        )
    }
}

private struct FlowTrackThemeEnvironmentKey: EnvironmentKey {
    static var defaultValue: FlowTrackTheme {
        FlowTrackThemeDefaults.standard
    }
}

private struct FlowTrackSavedThemesEnvironmentKey: EnvironmentKey {
    static var defaultValue: [FlowTrackSavedTheme] { [] }
}

private struct FlowTrackSelectedThemeIDEnvironmentKey: EnvironmentKey {
    static var defaultValue: UUID? { nil }
}

private struct FlowTrackSelectedBuiltInThemeIDEnvironmentKey: EnvironmentKey {
    static var defaultValue: String { flowTrackBuiltInThemeID }
}

private struct FlowTrackThemeActionsEnvironmentKey: EnvironmentKey {
    static var defaultValue: FlowTrackThemeActions { FlowTrackThemeActions() }
}

extension EnvironmentValues {
    var flowTrackTheme: FlowTrackTheme {
        get { self[FlowTrackThemeEnvironmentKey.self] }
        set { self[FlowTrackThemeEnvironmentKey.self] = newValue }
    }

    var flowTrackSavedThemes: [FlowTrackSavedTheme] {
        get { self[FlowTrackSavedThemesEnvironmentKey.self] }
        set { self[FlowTrackSavedThemesEnvironmentKey.self] = newValue }
    }

    var flowTrackSelectedThemeID: UUID? {
        get { self[FlowTrackSelectedThemeIDEnvironmentKey.self] }
        set { self[FlowTrackSelectedThemeIDEnvironmentKey.self] = newValue }
    }

    var flowTrackSelectedBuiltInThemeID: String {
        get { self[FlowTrackSelectedBuiltInThemeIDEnvironmentKey.self] }
        set { self[FlowTrackSelectedBuiltInThemeIDEnvironmentKey.self] = newValue }
    }

    var flowTrackThemeActions: FlowTrackThemeActions {
        get { self[FlowTrackThemeActionsEnvironmentKey.self] }
        set { self[FlowTrackThemeActionsEnvironmentKey.self] = newValue }
    }
}
