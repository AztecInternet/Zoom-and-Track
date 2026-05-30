import SwiftUI

struct SmartSetupReviewPanel: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme
    @ObservedObject var viewModel: CaptureSetupViewModel

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(flowTrackTheme.inspectorBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(flowTrackTheme.inspectorBorder, lineWidth: 1)
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
        .frame(maxHeight: 260)
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

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(suggestion.headline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(flowTrackTheme.primaryText)
                if let providerBadgeTitle = suggestion.providerBadgeTitle {
                    providerBadge(providerBadgeTitle, accentColor: accentColor)
                }
                Spacer(minLength: 6)
                Text(suggestion.reviewStateLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? accentColor : flowTrackTheme.mutedText)
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

            if let userReason = suggestion.userReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !userReason.isEmpty {
                Text(userReason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(flowTrackTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            explanationLine(title: "Noticed", text: suggestion.whatFlowTrackNoticed)
            explanationLine(title: "Suggest", text: suggestion.suggestedChange)
            explanationLine(title: "Why", text: suggestion.whyItMayHelp)

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

    private func explanationLine(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(flowTrackTheme.mutedText)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(flowTrackTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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

private extension SmartSetupSuggestionKind {
    var displayTitle: String {
        switch self {
        case .zoomMarker:
            return "Zoom adjustment"
        case .effectMarker:
            return "Effect review"
        case .regionTighten:
            return "Region review"
        }
    }
}

private extension SmartSetupSuggestion {
    var providerBadgeTitle: String? {
        switch providerID {
        case "rules":
            return "Rules"
        case "click-clusters":
            return "Click Cluster"
        case "clicks":
            return "Clicks"
        case "templates":
            return "Template"
        default:
            return nil
        }
    }
}

private extension SmartSetupSuggestionReason {
    var displayTitle: String {
        switch self {
        case .click:
            return "Click"
        case .cursorPause:
            return "Cursor pause"
        case .repeatedActivityZone:
            return "Repeated activity"
        case .timelineGap:
            return "Timeline gap"
        case .denseActivity:
            return "Dense activity"
        case .manualRegion:
            return "Manual region"
        }
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

    var whatFlowTrackNoticed: String {
        switch proposal {
        case .zoomAdjustment(let proposal):
            return "I noticed \(proposal.markerCount) existing click markers close together in the same area."
        case .zoom(let proposal):
            return "I noticed recorded activity near \(Self.timeString(proposal.sourceEventTimestamp))."
        case .effect:
            if reasons.contains(.cursorPause) {
                return "I noticed the cursor pause near one area for a short stretch."
            }
            if reasons.contains(.repeatedActivityZone) {
                return "I noticed repeated activity in one area over a short stretch."
            }
            return "I noticed activity that may be worth checking."
        case .regionTighten:
            return "A rough focus region is available for review."
        }
    }

    var suggestedChange: String {
        switch proposal {
        case .zoomAdjustment:
            return "Use the first marker to zoom in, keep the middle markers as No Zoom, then zoom out on the final marker."
        case .zoom:
            return "Check whether the existing marker timing should hold a little longer around this interaction."
        case .effect:
            return "If this moment matters, consider adding a subtle focus effect manually after reviewing the frame."
        case .regionTighten:
            return "Check the region by eye before tightening it manually."
        }
    }

    var whyItMayHelp: String {
        switch proposal {
        case .zoomAdjustment:
            return "That may avoid repeated zooming while the viewer follows one interaction."
        case .zoom:
            return "A steadier hold can make the interaction easier to follow."
        case .effect:
            return "This may help guide attention, but this suggestion only uses event timing."
        case .regionTighten:
            return "This may reduce visual distraction, but visual analysis is not enabled yet."
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
        var parts = [kind.displayTitle, displayTimeRange, reasons.map(\.displayTitle).joined(separator: ", ")]
        if let zoomScaleText {
            parts.append(zoomScaleText)
        }
        parts.append(confidenceText)
        return parts.joined(separator: " · ")
    }

    private var zoomScaleText: String? {
        switch proposal {
        case .zoom(let proposal):
            return String(format: "%.1fx", proposal.zoomScale)
        case .zoomAdjustment(let proposal):
            return "\(proposal.markerCount) markers"
        case .effect, .regionTighten:
            return nil
        }
    }

    private var confidenceText: String {
        "\(Int((score.value * 100).rounded()))% helpfulness"
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

    static func timeString(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let wholeSeconds = Int(clampedSeconds)
        let tenths = Int((clampedSeconds - Double(wholeSeconds)) * 10.0)
        let minutes = wholeSeconds / 60
        let secondsRemainder = wholeSeconds % 60
        return String(format: "%02d:%02d.%01d", minutes, secondsRemainder, tenths)
    }
}
