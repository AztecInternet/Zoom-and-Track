import SwiftUI

struct FlowTrackOnboardingCoachCard: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme
    @State private var isTrafficLightGroupHovered = false

    private let trafficLightDiameter: CGFloat = 12
    private let nativeMeasuredDiameter: CGFloat = 24
    private let nativeMeasuredGap: CGFloat = 17
    private let titleBarHeight: CGFloat = 32

    let stage: FlowTrackOnboardingStage
    let canGoBack: Bool
    let isFinalStage: Bool
    let isCollapsed: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        Group {
            if isCollapsed {
                collapsedPill
            } else {
                expandedPanel
            }
        }
        .background(cardFill)
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar

            VStack(alignment: .leading, spacing: 16) {
                header

                Text(stage.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    progressIndicator

                    HStack(spacing: 8) {
                        Button("Back", action: onBack)
                            .disabled(!canGoBack)
                            .buttonStyle(FlowTrackOnboardingButtonStyle(kind: .secondary, accentColor: accentColor))

                        Spacer(minLength: 12)

                        Button("Skip", action: onSkip)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36)
                            .frame(height: 28)

                        if isFinalStage {
                            Button("Done", action: onDone)
                                .buttonStyle(FlowTrackOnboardingButtonStyle(kind: .primary, accentColor: accentColor))
                        } else {
                            Button("Next", action: onNext)
                                .buttonStyle(FlowTrackOnboardingButtonStyle(kind: .primary, accentColor: accentColor))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 480, alignment: .leading)
    }

    private var collapsedPill: some View {
        HStack(spacing: 12) {
            trafficLightGroup

            Image(systemName: stage.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("Guided Tour")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)
                Text(stage.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            Button {
                onToggleCollapse()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Expand Guided Tour")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            onToggleCollapse()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            trafficLightGroup
                .padding(.leading, 14)
                .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .frame(height: titleBarHeight)
        .padding(.trailing, 18)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.045))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stage.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Guided Tour")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)
                Text(stage.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
        }
    }

    private var trafficLightGroup: some View {
        HStack(spacing: trafficLightGap) {
            trafficLightButton(
                color: Color(red: 1.0, green: 0.37, blue: 0.34),
                hoverSystemName: "xmark.circle.fill",
                help: "Close Guided Tour",
                action: onSkip
            )
            trafficLightButton(
                color: Color(red: 1.0, green: 0.78, blue: 0.18),
                hoverSystemName: "minus.circle.fill",
                help: "Minimise Guided Tour",
                action: onToggleCollapse
            )
        }
        .fixedSize()
        .onHover { isTrafficLightGroupHovered = $0 }
    }

    private var trafficLightGap: CGFloat {
        trafficLightDiameter * (nativeMeasuredGap / nativeMeasuredDiameter)
    }

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(FlowTrackOnboardingStage.activeTourStages) { progressStage in
                Capsule(style: .continuous)
                    .fill(progressStage.stageIndex <= stage.stageIndex ? accentColor : Color.secondary.opacity(0.18))
                    .frame(width: progressStage == stage ? 24 : 9, height: 5)
            }
        }
        .accessibilityLabel("Guided Tour step \(stage.progressIndex) of \(stage.progressCount)")
    }

    private func trafficLightButton(
        color: Color,
        hoverSystemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: trafficLightDiameter, height: trafficLightDiameter)
                if isTrafficLightGroupHovered {
                    Image(systemName: hoverSystemName)
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black.opacity(0.62), color)
                        .frame(width: trafficLightDiameter, height: trafficLightDiameter)
                        .transition(.opacity)
                }
            }
            .frame(width: trafficLightDiameter, height: trafficLightDiameter)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var cardFill: some View {
        RoundedRectangle(cornerRadius: isCollapsed ? 18 : 16, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: isCollapsed ? 18 : 16, style: .continuous)
                    .fill(flowTrackTheme.cardBackground.opacity(0.86))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: isCollapsed ? 18 : 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            .overlay(
                RoundedRectangle(cornerRadius: isCollapsed ? 18 : 16, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
                    .padding(1)
            )
    }

    private var accentColor: Color {
        FlowTrackAccent.color(for: .capture, theme: flowTrackTheme)
    }
}

struct FlowTrackOnboardingRegionHighlight: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(accentColor.opacity(0.42), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(1.5)
            )
            .allowsHitTesting(false)
    }

    private var accentColor: Color {
        FlowTrackAccent.color(for: .capture, theme: flowTrackTheme)
    }
}

private struct FlowTrackOnboardingButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .frame(minWidth: 46)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return .primary
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return accentColor.opacity(isPressed ? 0.78 : 0.92)
        case .secondary:
            return Color.secondary.opacity(isPressed ? 0.16 : 0.10)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return accentColor.opacity(0.35)
        case .secondary:
            return Color.secondary.opacity(0.16)
        }
    }
}
