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
        let badgeTitle = suggestion.providerBadgeTitle
        let metadataText = suggestion.displayMetadata
        let accentRole = suggestion.accentRole
        let accentColor = FlowTrackAccent.color(for: accentRole, theme: flowTrackTheme)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                if let reviewStateLabel = suggestion.reviewStateLabel {
                    Text(reviewStateLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? accentColor : flowTrackTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let badgeTitle {
                    providerBadge(badgeTitle, accentColor: accentColor)
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

            Text(metadataText)
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
        .onAppear {
            suggestion.debugVisibleIdentity(
                badgeTitle: badgeTitle,
                accentRole: accentRole,
                metadataText: metadataText
            )
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

private extension FlowTrackAccentRole {
    var debugName: String {
        switch self {
        case .zoomAndClicks:
            return "zoomAndClicks"
        case .effects:
            return "effects"
        case .capture:
            return "capture"
        case .library:
            return "library"
        case .settings:
            return "settings"
        }
    }
}

private enum SmartSuggestionEditIntent: String {
    case add
    case keep
    case adjust
    case remove
    case reviewFallback

    var badgeTitle: String? {
        switch self {
        case .add:
            return "Add"
        case .keep:
            return "Keep"
        case .adjust:
            return "Adjust"
        case .remove:
            return "Remove"
        case .reviewFallback:
            return nil
        }
    }
}

private extension SmartSetupSuggestion {
    var accentRole: FlowTrackAccentRole {
        if isExistingEffectReviewSuggestion || isProposedEffectIdea {
            return .effects
        }
        return .zoomAndClicks
    }

    var providerBadgeTitle: String? {
        if let intentBadge = editIntent.badgeTitle {
            return intentBadge
        }

        switch providerID {
        case "existing-edits":
            if isExistingEffectReviewSuggestion {
                return "Effect"
            }
            if isExistingZoomReviewSuggestion {
                return "Zoom"
            }
            return "Review"
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
            break
        }

        if isProposedEffectIdea {
            return "Effect Idea"
        }
        if hasTextChangeSupport {
            return "Text Change"
        }
        if hasScreenTextSupport {
            return "Review"
        }
        return nil
    }

    private var editIntent: SmartSuggestionEditIntent {
        if case .zoomAdjustment = proposal {
            return .adjust
        }
        guard providerID == "existing-edits" else {
            return .add
        }
        let title = (userTitle ?? headlineFallbackTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedTitle = title.lowercased()

        if lowercasedTitle.hasPrefix("consider removing") || lowercasedTitle.hasPrefix("remove") {
            return .remove
        }
        if lowercasedTitle.hasPrefix("keep") {
            return .keep
        }
        if lowercasedTitle.hasPrefix("extend")
            || lowercasedTitle.hasPrefix("resize")
            || lowercasedTitle.hasPrefix("expand")
            || lowercasedTitle.hasPrefix("move")
            || lowercasedTitle.hasPrefix("shorten")
            || lowercasedTitle.hasPrefix("refine")
            || lowercasedTitle.hasPrefix("adjust") {
            return .adjust
        }
        return .reviewFallback
    }

    private var isExistingEffectReviewSuggestion: Bool {
        guard providerID == "existing-edits",
              kind == .effectMarker,
              suggestionID.hasPrefix("existing-effect-") else {
            return false
        }
        if case .effect = proposal {
            return true
        }
        return false
    }

    private var isExistingZoomReviewSuggestion: Bool {
        guard providerID == "existing-edits",
              kind == .zoomMarker,
              suggestionID.hasPrefix("existing-zoom-") else {
            return false
        }
        switch proposal {
        case .zoom, .zoomAdjustment:
            return true
        case .effect, .regionTighten:
            return false
        }
    }

    private var isProposedEffectIdea: Bool {
        guard providerID != "existing-edits" else { return false }
        switch proposal {
        case .effect, .regionTighten:
            return true
        case .zoom, .zoomAdjustment:
            return false
        }
    }

    func debugVisibleIdentity(
        badgeTitle: String?,
        accentRole: FlowTrackAccentRole,
        metadataText: String
    ) {
        #if DEBUG
        let sourceIDs = sourceMarkerIDs
        let sourceText = sourceIDs.isEmpty ? "none" : sourceIDs.joined(separator: ",")
        let badgeText = badgeTitle ?? "none"
        let existingState = providerID == "existing-edits" ? "existing" : "new"
        print("[SmartSuggestionCard] suggestionID=\(suggestionID) providerID=\(providerID) existing=\(existingState) intent=\(editIntent.rawValue) kind=\(kind.rawValue) proposal=\(proposalCaseName) sourceMarkerIDs=\(sourceText) realZoom=\(isExistingZoomReviewSuggestion) realEffect=\(isExistingEffectReviewSuggestion) badge=\(badgeText) accentRole=\(accentRole.debugName) title=\(headline) metadata=\(metadataText)")
        #endif
    }

    private var sourceMarkerIDs: [String] {
        if suggestionID.hasPrefix("existing-effect-") {
            return [String(suggestionID.dropFirst("existing-effect-".count))]
        }
        if suggestionID.hasPrefix("existing-zoom-") {
            return [String(suggestionID.dropFirst("existing-zoom-".count))]
        }
        return []
    }

    private var proposalCaseName: String {
        switch proposal {
        case .zoom:
            return "zoom"
        case .zoomAdjustment:
            return "zoomAdjustment"
        case .effect:
            return "effect"
        case .regionTighten:
            return "regionTighten"
        }
    }

    private var hasTextChangeSupport: Bool {
        guard let userReason else { return false }
        return userReason.localizedCaseInsensitiveContains("screen content changes")
            || userReason.localizedCaseInsensitiveContains("changes what is visible")
            || userReason.localizedCaseInsensitiveContains("something on screen changes")
            || userReason.localizedCaseInsensitiveContains("what changes")
            || userReason.localizedCaseInsensitiveContains("transition")
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
        authoritativeHeadline
    }

    private var headlineFallbackTitle: String {
        switch proposal {
        case .zoomAdjustment:
            return "Refine this focus sequence"
        case .zoom:
            return "Add a short focus hold here"
        case .effect:
            return isExistingEffectReviewSuggestion ? "Keep this effect" : "Add a subtle focus effect here"
        case .regionTighten:
            return "Resize this focus region"
        }
    }

    private var authoritativeHeadline: String {
        let rawTitle = userTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch editIntent {
        case .add:
            return titleMatchingIntent(rawTitle, allowedPrefixes: ["add"]) ?? addHeadline
        case .keep:
            return titleMatchingIntent(rawTitle, allowedPrefixes: ["keep"]) ?? keepHeadline
        case .adjust:
            return titleMatchingIntent(rawTitle, allowedPrefixes: ["extend", "resize", "expand", "move", "shorten", "refine", "adjust", "tighten"]) ?? adjustHeadline
        case .remove:
            return titleMatchingIntent(rawTitle, allowedPrefixes: ["consider removing", "remove"]) ?? removeHeadline
        case .reviewFallback:
            return titleMatchingIntent(rawTitle, allowedPrefixes: ["review"]) ?? headlineFallbackTitle
        }
    }

    private var addHeadline: String {
        switch proposal {
        case .zoomAdjustment:
            return "Refine this focus sequence"
        case .zoom:
            if providerID == "click-clusters" && sourceEvents.count > 1 {
                return "Add a zoom hold covering this \(sourceEvents.count)-step interaction"
            }
            if providerID == "clicks" || reasons.contains(.click) {
                return "Add a short focus hold for this click"
            }
            return "Add a short focus hold here"
        case .effect:
            if providerID == "rules", reasons.contains(.repeatedActivityZone) {
                return "Add a subtle focus effect here"
            }
            return "Add a subtle focus effect here"
        case .regionTighten:
            return "Add a subtle focus effect around this area"
        }
    }

    private var keepHeadline: String {
        if isExistingEffectReviewSuggestion {
            return "Keep this effect"
        }
        if isExistingZoomReviewSuggestion {
            return "Keep this zoom"
        }
        return "Keep this edit"
    }

    private var adjustHeadline: String {
        switch proposal {
        case .zoomAdjustment:
            return "Refine this focus sequence"
        case .zoom:
            return isExistingZoomReviewSuggestion ? "Move this zoom" : "Refine this focus hold"
        case .effect, .regionTighten:
            return isExistingEffectReviewSuggestion ? "Expand this effect region to include the changing content" : "Tighten this focus area"
        }
    }

    private var removeHeadline: String {
        if isExistingEffectReviewSuggestion {
            return "Consider removing this effect"
        }
        if isExistingZoomReviewSuggestion {
            return "Consider removing this zoom"
        }
        return "Consider removing this edit"
    }

    var reviewStateLabel: String? {
        editIntent == .reviewFallback ? "Review" : nil
    }

    var adviceBody: String {
        if let userReason = userReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userReason.isEmpty,
           bodyMatchesIntent(userReason) {
            return userReason
        }
        return fallbackAdviceBody
    }

    private var fallbackAdviceBody: String {
        switch editIntent {
        case .add:
            return addFallbackAdviceBody
        case .keep:
            return keepFallbackAdviceBody
        case .adjust:
            return adjustFallbackAdviceBody
        case .remove:
            return removeFallbackAdviceBody
        case .reviewFallback:
            return "Review this moment if it affects how clearly the step reads."
        }
    }

    private var addFallbackAdviceBody: String {
        switch proposal {
        case .zoomAdjustment:
            return stableChoice(from: [
                "Viewers may need more time to follow this sequence.",
                "The connected interaction may be easier to follow as one clear focus move.",
                "This sequence may benefit from a steadier focus move."
            ])
        case .zoom:
            return stableChoice(from: [
                "This interaction may need additional emphasis.",
                "Viewers may need help following what changes.",
                "This moment may move past too quickly."
            ])
        case .effect:
            if reasons.contains(.cursorPause) {
                return stableChoice(from: [
                    "This pause can guide attention if it matters to the edit.",
                    "Gentle emphasis can help this pause read as intentional.",
                    "A light visual cue can make this quiet moment easier to notice."
                ])
            }
            if reasons.contains(.repeatedActivityZone) {
                return stableChoice(from: [
                    "Viewers may need help knowing where to look.",
                    "This area appears to matter to the step.",
                    "This active area may move past too quickly."
                ])
            }
            return stableChoice(from: [
                "A light visual cue can help guide attention.",
                "Subtle emphasis can help if this moment matters to the story.",
                "This part may need more attention to read clearly."
            ])
        case .regionTighten:
            return stableChoice(from: [
                "A tighter focus area may make the action clearer.",
                "A smaller focus area can reduce distraction around the action.",
                "The important area may need a more deliberate frame."
            ])
        }
    }

    private var keepFallbackAdviceBody: String {
        if isExistingEffectReviewSuggestion {
            return stableChoice(from: [
                "The effect already highlights the changing content clearly.",
                "The effect appears to guide attention without obvious distraction.",
                "The highlighted area stays relevant through this part of the edit."
            ])
        }
        if isExistingZoomReviewSuggestion {
            return stableChoice(from: [
                "The zoom guides attention to the most important part of the screen.",
                "The zoom appears to follow the action clearly.",
                "The zoom keeps the relevant information easy to follow."
            ])
        }
        return "This edit appears to support the step clearly."
    }

    private var adjustFallbackAdviceBody: String {
        let title = headline.lowercased()
        if title.hasPrefix("extend") {
            return title.contains("zoom")
                ? "Viewers may need more time before the zoom ends."
                : "Viewers may need more time before the effect ends."
        }
        if title.hasPrefix("resize") || title.hasPrefix("expand") || title.hasPrefix("tighten") {
            return "The highlighted area may not fully cover the changing information."
        }
        if title.hasPrefix("move") {
            return "The focus point may not land on the most important part of the screen."
        }
        if title.hasPrefix("shorten") {
            return "The edit may stay on screen longer than the step needs."
        }
        return "This existing edit may need a small timing or framing adjustment."
    }

    private var removeFallbackAdviceBody: String {
        if isExistingEffectReviewSuggestion {
            return "The activity may already be clear without this effect."
        }
        if isExistingZoomReviewSuggestion {
            return "The activity may already be clear without this zoom."
        }
        return "The activity may already be clear without additional emphasis."
    }

    private func titleMatchingIntent(_ title: String, allowedPrefixes: [String]) -> String? {
        guard !title.isEmpty else { return nil }
        let normalizedTitle = title.lowercased()
        return allowedPrefixes.contains { normalizedTitle.hasPrefix($0) } ? title : nil
    }

    private func bodyMatchesIntent(_ body: String) -> Bool {
        let normalizedBody = body.lowercased()
        switch editIntent {
        case .add:
            return !containsAny(normalizedBody, prefixesOrPhrases: ["keep this", "consider removing", "remove this", "resize this", "expand this", "extend this", "move this", "shorten this"])
        case .keep:
            return !containsAny(normalizedBody, prefixesOrPhrases: ["add ", "consider removing", "remove this", "resize this", "expand this", "extend this", "move this", "shorten this", "may need more time"])
        case .adjust:
            return !containsAny(normalizedBody, prefixesOrPhrases: ["add ", "keep this", "consider removing", "remove this"])
        case .remove:
            return !containsAny(normalizedBody, prefixesOrPhrases: ["add ", "keep this", "resize this", "expand this", "extend this", "move this", "shorten this"])
        case .reviewFallback:
            return true
        }
    }

    private func containsAny(_ text: String, prefixesOrPhrases: [String]) -> Bool {
        prefixesOrPhrases.contains { text.contains($0) }
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
            if isExistingZoomReviewSuggestion {
                return zoomReviewSummary
            }
            return reasons.contains(.click) ? "Interaction highlight" : "Focus moment"
        case .effect:
            return isExistingEffectReviewSuggestion ? "Visual effect" : "Suggested effect"
        case .regionTighten:
            return isExistingEffectReviewSuggestion ? "Visual effect" : "Focus idea"
        }
    }

    private var zoomReviewSummary: String {
        let title = userTitle ?? ""
        if title.localizedCaseInsensitiveContains("hold") {
            return "Zoom hold"
        }
        if title.localizedCaseInsensitiveContains("timing") {
            return "Zoom timing"
        }
        return "Focus zoom"
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
