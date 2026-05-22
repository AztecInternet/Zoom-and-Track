import AppKit
import SwiftUI

let flowTrackBuiltInThemeID = "built-in-default"

struct FlowTrackTheme: Codable {
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
}

struct FlowTrackThemeActions {
    var selectTheme: (UUID?) -> Void = { _ in }
    var saveTheme: (String, FlowTrackTheme) -> Void = { _, _ in }
    var updateTheme: (UUID, String, FlowTrackTheme) -> Void = { _, _, _ in }
    var deleteTheme: (UUID) -> Void = { _ in }
    var resetToBuiltInDefault: () -> Void = {}
}

enum FlowTrackThemeDefaults {
    static var standard: FlowTrackTheme {
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

    var flowTrackThemeActions: FlowTrackThemeActions {
        get { self[FlowTrackThemeActionsEnvironmentKey.self] }
        set { self[FlowTrackThemeActionsEnvironmentKey.self] = newValue }
    }
}
