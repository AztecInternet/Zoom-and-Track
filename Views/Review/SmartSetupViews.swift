import SwiftUI

struct SmartSetupReviewPanel: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme
    @ObservedObject var viewModel: CaptureSetupViewModel
    var isEmbeddedInInspector = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let statusMessage = viewModel.smartSetupStatusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(flowTrackTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.pendingSmartSetupSuggestions.isEmpty {
                suggestionList
            }
        }
        .padding(isEmbeddedInInspector ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: isEmbeddedInInspector ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isEmbeddedInInspector ? Color.clear : flowTrackTheme.inspectorBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isEmbeddedInInspector ? Color.clear : flowTrackTheme.inspectorBorder, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Suggestions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(flowTrackTheme.primaryText)
                Text("Local review suggestions for improving existing edits.")
                    .font(.system(size: 10))
                    .foregroundStyle(flowTrackTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !viewModel.pendingSmartSetupSuggestions.isEmpty {
                Button("Clear") {
                    viewModel.clearSmartSetupSuggestions()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
                .help("Clear all pending Smart Suggestions")
            }

            Button {
                viewModel.runSmartSetup()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.isRunningSmartSetup ? "hourglass" : "sparkles")
                    Text(viewModel.isRunningSmartSetup ? "Running" : "Run")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.recordingSummary == nil || viewModel.isRunningSmartSetup)
            .help("Generate Smart Suggestions from recorded activity and existing markers")
        }
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.pendingSmartSetupSuggestions) { suggestion in
                    SmartSetupSuggestionRow(
                        suggestion: suggestion,
                        isSelected: viewModel.selectedSmartSetupSuggestionID == suggestion.suggestionID,
                        onSelect: {
                            viewModel.selectSmartSetupSuggestion(suggestion.suggestionID)
                        },
                        onDismiss: {
                            viewModel.dismissSmartSetupSuggestion(suggestion.suggestionID)
                        }
                    )
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxHeight: isEmbeddedInInspector ? .infinity : 260)
    }
}

private struct SmartSetupSuggestionRow: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let suggestion: SmartSetupSuggestion
    let isSelected: Bool
    let onSelect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let accentColor = FlowTrackAccent.color(for: .zoomAndClicks, theme: flowTrackTheme)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                Text(suggestion.reviewStateLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? accentColor : flowTrackTheme.mutedText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let providerBadgeTitle = suggestion.providerBadgeTitle {
                    providerBadge(providerBadgeTitle, accentColor: accentColor)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(flowTrackTheme.mutedText)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss this suggestion")
            }

            Text(suggestion.headline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(flowTrackTheme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(suggestion.adviceBody)
                .font(.system(size: 10.5))
                .foregroundStyle(flowTrackTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(suggestion.displayMetadata)
                .font(.system(size: 10))
                .foregroundStyle(flowTrackTheme.mutedText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.16) : flowTrackTheme.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? accentColor.opacity(0.9) : flowTrackTheme.cardBorder.opacity(0.85), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: isSelected ? accentColor.opacity(0.18) : Color.clear, radius: 5, x: 0, y: 0)
        .onTapGesture(perform: onSelect)
    }

    private func providerBadge(_ title: String, accentColor: Color) -> some View {
        Text(title)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(flowTrackTheme.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(flowTrackTheme.cardBackground.opacity(0.56))
            )
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(isSelected ? 0.45 : 0.28), lineWidth: 1)
            )
    }
}

private extension SmartSetupSuggestion {
    var providerBadgeTitle: String? {
        if hasTextChangeSupport {
            return "Text Change"
        }
        if hasScreenTextSupport {
            return "Review"
        }

        switch providerID {
        case "click-clusters":
            return sourceEvents.count > 1 ? "Sequence" : "Interaction"
        case "clicks":
            return "Interaction"
        case "templates":
            return "Focus"
        case "rules":
            if reasons.contains(.cursorPause) {
                return "Timing"
            }
            if reasons.contains(.repeatedActivityZone) || reasons.contains(.denseActivity) {
                return "Review"
            }
            return kind == .zoomMarker ? "Focus" : "Review"
        default:
            return nil
        }
    }

    private var hasTextChangeSupport: Bool {
        guard let userReason else { return false }
        return userReason.localizedCaseInsensitiveContains("screen content changes")
            || userReason.localizedCaseInsensitiveContains("changes what is visible")
            || userReason.localizedCaseInsensitiveContains("something on screen changes")
    }

    private var hasScreenTextSupport: Bool {
        guard let userReason else { return false }
        return userReason.localizedCaseInsensitiveContains("readable content")
            || userReason.localizedCaseInsensitiveContains("screen content")
            || userReason.localizedCaseInsensitiveContains("stay oriented")
    }
}

private extension SmartSetupSuggestion {
    var headline: String {
        if let userTitle = userTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userTitle.isEmpty {
            return userTitle
        }

        switch proposal {
        case .zoomAdjustment:
            return "Stay zoomed during this click sequence"
        case .zoom:
            return "Review this zoom timing"
        case .effect:
            return "Review a possible focus effect"
        case .regionTighten:
            return "Review this focus region"
        }
    }

    var reviewStateLabel: String {
        switch proposal {
        case .zoomAdjustment:
            return "Smart Adjust"
        case .zoom, .effect, .regionTighten:
            return "Review only"
        }
    }

    var adviceBody: String {
        if let userReason = userReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userReason.isEmpty {
            return userReason
        }
        return fallbackAdviceBody
    }

    private var fallbackAdviceBody: String {
        switch proposal {
        case .zoomAdjustment:
            return stableChoice(from: [
                "Keep this short sequence steady so the viewer can follow the action.",
                "This connected interaction may work better as one clear focus moment.",
                "Hold attention here if this part is important to the edit."
            ])
        case .zoom:
            return stableChoice(from: [
                "This short interaction may be worth highlighting.",
                "A little more focus here could help the viewer follow what changed.",
                "Review this moment if the click matters to the story."
            ])
        case .effect:
            if reasons.contains(.cursorPause) {
                return stableChoice(from: [
                    "You paused here, so a subtle focus effect may help guide attention.",
                    "Attention stayed in one place, which may make this a useful emphasis point.",
                    "This quiet moment may be worth a gentle visual cue."
                ])
            }
            if reasons.contains(.repeatedActivityZone) {
                return stableChoice(from: [
                    "Activity was concentrated here, so a light focus effect may help the viewer know where to look.",
                    "Several actions happened in this area, which may be worth a gentle visual cue.",
                    "This area carries repeated activity and may benefit from clearer focus."
                ])
            }
            return stableChoice(from: [
                "A light visual cue here may help guide attention.",
                "Review this moment for subtle emphasis if it matters to the story.",
                "This part may read more clearly with a gentle focus effect."
            ])
        case .regionTighten:
            return stableChoice(from: [
                "Tighten this area only if it makes the action clearer.",
                "A smaller focus area may reduce distraction around the important action.",
                "Review the frame and keep the focus area as simple as possible."
            ])
        }
    }

    var displayTimeRange: String {
        if let sourceTimeRange, sourceTimeRange.endTime - sourceTimeRange.startTime > 0.05 {
            return "\(Self.timeString(sourceTimeRange.startTime))-\(Self.timeString(sourceTimeRange.endTime))"
        }

        let time = sourceTimeRange?.startTime ?? sourceEvents.first?.timestamp ?? proposalTime
        return Self.timeString(time)
    }

    var displayMetadata: String {
        [displayTimeRange, opportunitySummary, confidenceText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var opportunitySummary: String {
        switch proposal {
        case .zoomAdjustment:
            return "Focus sequence"
        case .zoom:
            if providerID == "click-clusters" {
                return "Focus sequence"
            }
            return reasons.contains(.click) ? "Interaction highlight" : "Focus moment"
        case .effect:
            return "Focus effect"
        case .regionTighten:
            return "Focus area"
        }
    }

    private var confidenceText: String? {
        switch score.value {
        case 0.82...:
            return nil
        case 0.68..<0.82:
            return "Worth reviewing"
        default:
            return "Possibly useful"
        }
    }

    private var proposalTime: Double {
        switch proposal {
        case .zoom(let proposal):
            return proposal.sourceEventTimestamp
        case .zoomAdjustment(let proposal):
            return proposal.startTime
        case .effect(let proposal):
            return proposal.sourceEventTimestamp
        case .regionTighten(let proposal):
            return proposal.sourceTime
        }
    }

    private func stableChoice(from options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        let value = suggestionID.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult &* 31) &+ Int(scalar.value)) & 0x7fffffff
        }
        return options[value % options.count]
    }

    static func timeString(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let wholeSeconds = Int(clampedSeconds)
        let tenths = Int((clampedSeconds - Double(wholeSeconds)) * 10.0)
        let minutes = wholeSeconds / 60
        let secondsRemainder = wholeSeconds % 60
        return String(format: "%02d:%02d.%01d", minutes, secondsRemainder, tenths)
    }
}
