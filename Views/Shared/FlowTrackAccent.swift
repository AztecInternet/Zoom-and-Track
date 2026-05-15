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
        switch role {
        case .zoomAndClicks:
            return .blue
        case .effects:
            return .pink
        case .capture, .library, .settings:
            return .accentColor
        }
    }

    static func subtleFill(for role: FlowTrackAccentRole, opacity: Double) -> Color {
        color(for: role).opacity(opacity)
    }

    static func selectedStroke(for role: FlowTrackAccentRole, opacity: Double = 0.35) -> Color {
        color(for: role).opacity(opacity)
    }
}
