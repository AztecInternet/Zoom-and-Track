import SwiftUI

enum FlowTrackAccentRole {
    case zoomAndClicks
    case effects
    case capture
    case library
    case settings
}

enum FlowTrackAccent {
    static func color(for role: FlowTrackAccentRole, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
        guard usesRoleSpecificAccent else { return .accentColor }

        return theme.accentColor(for: role)
    }

    static func panelFill(for role: FlowTrackAccentRole, opacity: Double = 0.045, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
        color(for: role, theme: theme).opacity(opacity)
    }

    static func panelBorder(for role: FlowTrackAccentRole, opacity: Double = 0.10, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
        color(for: role, theme: theme).opacity(opacity)
    }

    static func subtleFill(for role: FlowTrackAccentRole, opacity: Double, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
        color(for: role, theme: theme).opacity(opacity)
    }

    static func selectedStroke(for role: FlowTrackAccentRole, opacity: Double = 0.35, theme: FlowTrackTheme = FlowTrackThemeDefaults.standard) -> Color {
        color(for: role, theme: theme).opacity(opacity)
    }

    private static var usesRoleSpecificAccent: Bool {
        UserDefaults.standard.object(forKey: "AppleAccentColor") == nil
    }
}
