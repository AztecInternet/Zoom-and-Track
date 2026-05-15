import SwiftUI

enum FlowTrackAccentRole {
    case zoomAndClicks
    case effects
    case capture
    case library
    case settings
}

enum FlowTrackAccent {
    static func color(for role: FlowTrackAccentRole) -> Color {
        guard usesRoleSpecificAccent else { return .accentColor }

        switch role {
        case .zoomAndClicks:
            return .blue
        case .effects:
            return .pink
        case .capture:
            return .green
        case .library:
            return .orange
        case .settings:
            return .indigo
        }
    }

    static func panelFill(for role: FlowTrackAccentRole, opacity: Double = 0.045) -> Color {
        color(for: role).opacity(opacity)
    }

    static func panelBorder(for role: FlowTrackAccentRole, opacity: Double = 0.10) -> Color {
        color(for: role).opacity(opacity)
    }

    static func subtleFill(for role: FlowTrackAccentRole, opacity: Double) -> Color {
        color(for: role).opacity(opacity)
    }

    static func selectedStroke(for role: FlowTrackAccentRole, opacity: Double = 0.35) -> Color {
        color(for: role).opacity(opacity)
    }

    private static var usesRoleSpecificAccent: Bool {
        UserDefaults.standard.object(forKey: "AppleAccentColor") == nil
    }
}
