import CoreGraphics
import Foundation
import Vision

struct SmartSuggestionOCRTextObservation {
    let regionID: String
    let frameTimestamp: Double
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

struct SmartSuggestionOCRDiagnostics {
    let analyzedFrameCount: Int
    let textObservationCount: Int
    let cropFrameCount: Int
    let cropTextObservationCount: Int
    let fullFrameFallbackFrameCount: Int
    let fullFrameFallbackTextObservationCount: Int
    let failedOCRCount: Int
    let elapsedSeconds: Double
    let previewStrings: [String]
}

struct SmartSuggestionOCRAnalysisResult {
    let observations: [SmartSuggestionOCRTextObservation]
    let diagnostics: SmartSuggestionOCRDiagnostics
}

enum SmartSuggestionUIContext: String, CaseIterable {
    case settingsPanel
    case menuInteraction
    case dialogInteraction
    case textEditing
    case formEntry
    case fileSelection
    case toolbarInteraction
    case sidebarInteraction
    case contentEditing
    case unknown

    var displayName: String {
        switch self {
        case .settingsPanel:
            return "Settings"
        case .menuInteraction:
            return "Menu"
        case .dialogInteraction:
            return "Dialog"
        case .textEditing:
            return "Text editing"
        case .formEntry:
            return "Form"
        case .fileSelection:
            return "File"
        case .toolbarInteraction:
            return "Toolbar"
        case .sidebarInteraction:
            return "Sidebar"
        case .contentEditing:
            return "Content"
        case .unknown:
            return "Unknown"
        }
    }
}

struct SmartSuggestionOCRRegionMetadata {
    let regionID: String
    let textCount: Int
    let uniqueTextSnippets: [String]
    let hasTextNearSourceEvent: Bool
    let hasTextChange: Bool
    let uiContext: SmartSuggestionUIContext
    let uiContextConfidence: Double
    let supportingText: String?
    let supportingTextConfidence: Float?

    var appearsVisuallyMeaningful: Bool {
        textCount > 0 || hasTextNearSourceEvent || hasTextChange
    }

    var hasUsefulUIContext: Bool {
        uiContext != .unknown && uiContextConfidence >= 0.62
    }
}

struct SmartSuggestionVisionAnalysisService {
    private let maximumFramesToAnalyze = 60
    private let maximumPreviewStrings = 4
    private let minimumTextHeight: Float = 0.018
    private let nearbyTextDistance: CGFloat = 0.18
    private let cropPadding: CGFloat = 0.16

    private static let textRecognitionQueue = DispatchQueue(
        label: "com.flowtrack.smart-suggestions.text-recognition",
        qos: .utility
    )

    func analyzeText(
        in samples: [ActivityRegionFrameSample],
        regions: [ActivityRegion] = []
    ) async -> SmartSuggestionOCRAnalysisResult {
        let startDate = Date()
        guard !samples.isEmpty else {
            return SmartSuggestionOCRAnalysisResult(
                observations: [],
                diagnostics: SmartSuggestionOCRDiagnostics(
                    analyzedFrameCount: 0,
                    textObservationCount: 0,
                    cropFrameCount: 0,
                    cropTextObservationCount: 0,
                    fullFrameFallbackFrameCount: 0,
                    fullFrameFallbackTextObservationCount: 0,
                    failedOCRCount: 0,
                    elapsedSeconds: 0,
                    previewStrings: []
                )
            )
        }

        var observations: [SmartSuggestionOCRTextObservation] = []
        var cropFrameCount = 0
        var cropTextObservationCount = 0
        var fullFrameFallbackFrameCount = 0
        var fullFrameFallbackTextObservationCount = 0
        var failedOCRCount = 0
        let sampledFrames = Array(samples.prefix(maximumFramesToAnalyze))
        let regionsByID = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })

        for sample in sampledFrames {
            guard !Task.isCancelled else { break }
            do {
                let cropObservations = try await cropTextObservations(
                    for: sample,
                    region: regionsByID[sample.regionID]
                )
                if !cropObservations.isEmpty {
                    cropFrameCount += 1
                    cropTextObservationCount += cropObservations.count
                    observations.append(contentsOf: cropObservations)
                } else {
                    let fallbackObservations = try await recognizedTextObservations(
                        image: sample.image,
                        regionID: sample.regionID,
                        frameTimestamp: sample.actualTime
                    )
                    fullFrameFallbackFrameCount += 1
                    fullFrameFallbackTextObservationCount += fallbackObservations.count
                    observations.append(contentsOf: fallbackObservations)
                }
            } catch {
                failedOCRCount += 1
            }
        }

        return SmartSuggestionOCRAnalysisResult(
            observations: observations,
            diagnostics: SmartSuggestionOCRDiagnostics(
                analyzedFrameCount: sampledFrames.count,
                textObservationCount: observations.count,
                cropFrameCount: cropFrameCount,
                cropTextObservationCount: cropTextObservationCount,
                fullFrameFallbackFrameCount: fullFrameFallbackFrameCount,
                fullFrameFallbackTextObservationCount: fullFrameFallbackTextObservationCount,
                failedOCRCount: failedOCRCount,
                elapsedSeconds: Date().timeIntervalSince(startDate),
                previewStrings: previewStrings(from: observations)
            )
        )
    }

    func regionMetadata(
        for regions: [ActivityRegion],
        analysisResult: SmartSuggestionOCRAnalysisResult,
        contentCoordinateSize: CGSize
    ) -> [String: SmartSuggestionOCRRegionMetadata] {
        let observationsByRegionID = Dictionary(grouping: analysisResult.observations, by: \.regionID)
        return regions.reduce(into: [:]) { partialResult, region in
            let observations = observationsByRegionID[region.id] ?? []
            partialResult[region.id] = metadata(
                for: region,
                observations: observations,
                contentCoordinateSize: contentCoordinateSize
            )
        }
    }

    func visionTunedSuggestions(
        from suggestions: [SmartSetupSuggestion],
        regionMetadataByID: [String: SmartSuggestionOCRRegionMetadata]
    ) -> [SmartSetupSuggestion] {
        suggestions.compactMap { suggestion in
            let metadata = regionMetadataByID["suggestion-\(suggestion.suggestionID)"]
            return visionTunedSuggestion(suggestion, metadata: metadata)
        }
        .sorted { lhs, rhs in
            if lhs.score.value != rhs.score.value {
                return lhs.score.value > rhs.score.value
            }
            let lhsTime = lhs.sourceTimeRange?.startTime ?? lhs.sourceEvents.first?.timestamp ?? 0
            let rhsTime = rhs.sourceTimeRange?.startTime ?? rhs.sourceEvents.first?.timestamp ?? 0
            if lhsTime != rhsTime {
                return lhsTime < rhsTime
            }
            return lhs.suggestionID < rhs.suggestionID
        }
    }

    private func metadata(
        for region: ActivityRegion,
        observations: [SmartSuggestionOCRTextObservation],
        contentCoordinateSize: CGSize
    ) -> SmartSuggestionOCRRegionMetadata {
        let uniqueSnippets = uniqueTextSnippets(from: observations)
        let classification = uiContextClassification(
            for: region,
            observations: observations,
            uniqueSnippets: uniqueSnippets,
            contentCoordinateSize: contentCoordinateSize
        )
        return SmartSuggestionOCRRegionMetadata(
            regionID: region.id,
            textCount: observations.count,
            uniqueTextSnippets: uniqueSnippets,
            hasTextNearSourceEvent: hasNearbyText(
                in: observations,
                sourceEvents: region.sourceEvents,
                contentCoordinateSize: contentCoordinateSize
            ),
            hasTextChange: hasTextChange(in: observations),
            uiContext: classification.context,
            uiContextConfidence: classification.confidence,
            supportingText: classification.supportingText,
            supportingTextConfidence: confidence(
                for: classification.supportingText,
                in: observations
            )
        )
    }

    private func visionTunedSuggestion(
        _ suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata?
    ) -> SmartSetupSuggestion? {
        guard let metadata else { return suggestion }

        var tunedSuggestion = suggestion
        let baseScore = tunedSuggestion.score.value
        var scoreAdjustment = 0.0
        if metadata.hasTextNearSourceEvent {
            scoreAdjustment += 0.05
        } else if metadata.textCount > 0 {
            scoreAdjustment += 0.025
        }
        if metadata.hasTextChange {
            scoreAdjustment += 0.04
        }
        if metadata.hasUsefulUIContext {
            scoreAdjustment += 0.025
        }
        if shouldSoftlyDowngrade(suggestion, metadata: metadata) {
            scoreAdjustment -= 0.08
        }

        let tunedScore = min(max(baseScore + scoreAdjustment, 0), 1)
        if shouldSuppress(suggestion, tunedScore: tunedScore, metadata: metadata) {
            return nil
        }

        tunedSuggestion.score = SmartSetupCandidateScore(
            value: tunedScore,
            components: suggestion.score.components
        )
        tunedSuggestion.userReason = visionSupportedReason(
            existingReason: tunedSuggestion.userReason,
            metadata: metadata
        )
        tunedSuggestion.userTitle = contextSupportedTitle(
            existingTitle: tunedSuggestion.userTitle,
            suggestion: tunedSuggestion,
            metadata: metadata
        )
        return tunedSuggestion
    }

    private func shouldSoftlyDowngrade(
        _ suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata
    ) -> Bool {
        guard !metadata.appearsVisuallyMeaningful else { return false }
        guard suggestion.providerID == "rules" || suggestion.providerID == "templates" else { return false }
        return suggestion.reasons.contains(.cursorPause)
            || suggestion.reasons.contains(.repeatedActivityZone)
            || suggestion.reasons.contains(.denseActivity)
            || suggestion.providerID == "templates"
    }

    private func shouldSuppress(
        _ suggestion: SmartSetupSuggestion,
        tunedScore: Double,
        metadata: SmartSuggestionOCRRegionMetadata
    ) -> Bool {
        guard !metadata.appearsVisuallyMeaningful else { return false }
        guard suggestion.providerID == "rules" else { return false }
        guard suggestion.reasons.contains(.cursorPause) || suggestion.reasons.contains(.repeatedActivityZone) else { return false }
        return tunedScore < 0.55
    }

    private func visionSupportedReason(
        existingReason: String?,
        metadata: SmartSuggestionOCRRegionMetadata
    ) -> String? {
        if metadata.hasUsefulUIContext {
            return contextSupportedReason(metadata)
        }
        guard metadata.hasTextNearSourceEvent || metadata.hasTextChange else {
            return existingReason
        }

        let supportText = screenContextSupportText(for: metadata)
        return supportText
    }

    private func contextSupportedTitle(
        existingTitle: String?,
        suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata
    ) -> String? {
        guard metadata.hasUsefulUIContext else { return existingTitle }
        let label = safeSupportingLabel(from: metadata)

        switch metadata.uiContext {
        case .settingsPanel:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-settings-label-title", from: [
                    "Keep \(label) visible",
                    "Make \(label) clear",
                    "Keep the \(label) options visible"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-settings-title", from: [
                "Keep the settings area in focus",
                "Make this settings change clear",
                "Hold attention on these options"
            ])
        case .menuInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-menu-label-title", from: [
                    "Keep the \(label) menu choice clear",
                    "Highlight the \(label) menu action",
                    "Keep \(label) easy to follow"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-menu-title", from: [
                "Keep this menu action clear",
                "Highlight this menu choice",
                "Make the menu change easy to follow"
            ])
        case .dialogInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-dialog-label-title", from: [
                    "Keep the \(label) dialog clear",
                    "Make the \(label) confirmation easy to follow",
                    "Highlight the \(label) moment"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-dialog-title", from: [
                "Highlight this dialog moment",
                "Keep this dialog clear",
                "Make this confirmation easy to follow"
            ])
        case .textEditing:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-text-label-title", from: [
                    "Keep \(label) readable",
                    "Make the \(label) text change clear",
                    "Hold focus on \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-text-title", from: [
                "Keep the text edit readable",
                "Make this text change easy to follow",
                "Hold focus on the edited text"
            ])
        case .formEntry:
            if let label {
                let fieldLabel = formFieldLabelPhrase(label)
                return stableChoice(seed: "\(metadata.regionID)-form-label-title", from: [
                    "Keep the \(fieldLabel) field clear",
                    "Guide attention to the \(fieldLabel)",
                    "Keep the \(fieldLabel) easy to follow"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-form-title", from: [
                "Keep this form entry clear",
                "Guide attention to this field",
                "Make this input step easy to follow"
            ])
        case .fileSelection:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-file-label-title", from: [
                    "Keep the \(label) selection clear",
                    "Highlight the \(label) file step",
                    "Make the \(label) choice easy to follow"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-file-title", from: [
                "Keep this file choice clear",
                "Highlight this file step",
                "Make this selection easy to follow"
            ])
        case .toolbarInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-toolbar-label-title", from: [
                    "Keep the \(label) control clear",
                    "Highlight the \(label) tool",
                    "Make \(label) easy to follow"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-toolbar-title", from: [
                "Keep this toolbar action clear",
                "Highlight this tool choice",
                "Make this control easy to follow"
            ])
        case .sidebarInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-sidebar-label-title", from: [
                    "Keep \(label) visible in the side panel",
                    "Guide attention to \(label)",
                    "Make the \(label) sidebar step clear"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-sidebar-title", from: [
                "Keep the sidebar action clear",
                "Guide attention to this side panel",
                "Make this sidebar step easy to follow"
            ])
        case .contentEditing:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-content-label-title", from: [
                    "Keep \(label) clear",
                    "Guide attention to \(label)",
                    "Keep \(label) easy to follow"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-content-title", from: [
                "Keep the editing area clear",
                "Guide attention to this workspace",
                "Make this content change easy to follow"
            ])
        case .unknown:
            return existingTitle ?? fallbackTitle(for: suggestion)
        }
    }

    private func fallbackTitle(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return "Keep this interaction in focus"
        case .zoom:
            return "Guide attention to this moment"
        case .effect:
            return "Consider a subtle focus effect"
        case .regionTighten:
            return "Review this focus area"
        }
    }

    private func contextSupportedReason(_ metadata: SmartSuggestionOCRRegionMetadata) -> String {
        let label = safeSupportingLabel(from: metadata)
        switch metadata.uiContext {
        case .settingsPanel:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-settings-label-reason", from: [
                    "\(label) appears to be the setting in focus, so keeping it readable can help viewers follow the change.",
                    "The action seems tied to \(label); a steady focus may make the adjustment easier to understand.",
                    "Keeping \(label) visible can help the viewer stay oriented during this settings step."
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-settings-reason", from: [
                "Settings or options are visible here, so a steady focus may help viewers follow the change.",
                "This looks like an options area; keeping it clear can make the edit easier to understand.",
                "The viewer may benefit from seeing which setting is being adjusted."
            ])
        case .menuInteraction:
            if let label {
                return "The action appears to involve \(label), so a brief focus hold may help viewers follow the choice."
            }
            return stableChoice(seed: "\(metadata.regionID)-menu-reason", from: [
                "A menu appears to be involved, so keeping this moment clear can help the viewer follow the choice.",
                "This looks like a menu step where a brief focus hold may improve clarity.",
                "The viewer may need a clear look at this menu action."
            ])
        case .dialogInteraction:
            if let label {
                return "\(label) appears in this dialog, so keeping it clear can help the viewer understand the decision."
            }
            return stableChoice(seed: "\(metadata.regionID)-dialog-reason", from: [
                "This looks like a dialog or confirmation, so a clear hold may help the viewer understand the decision.",
                "The screen appears to show a dialog; keeping it readable can make the step easier to follow.",
                "This confirmation moment may be worth highlighting if it matters to the edit."
            ])
        case .textEditing:
            if let label {
                return "\(label) appears to be the relevant text here, so keeping it readable may make the edit easier to follow."
            }
            return stableChoice(seed: "\(metadata.regionID)-text-reason", from: [
                "Text appears to be changing here, so keeping the area steady may help the viewer read it.",
                "This looks like a text edit; a clear focus moment can make the change easier to follow.",
                "Readable text is central to this moment, so clarity matters."
            ])
        case .formEntry:
            if let label {
                let fieldLabel = formFieldLabelPhrase(label)
                return "The \(fieldLabel) field appears to be in use, so a subtle focus hold may help viewers follow the entry."
            }
            return stableChoice(seed: "\(metadata.regionID)-form-reason", from: [
                "This looks like a form or field, so a subtle focus hold may help the viewer follow the entry.",
                "A field appears to be involved; keeping it clear can reduce confusion.",
                "The viewer may benefit from seeing which input area is being used."
            ])
        case .fileSelection:
            if let label {
                return "\(label) appears to be part of the selection step, so keeping it clear may help the workflow make sense."
            }
            return stableChoice(seed: "\(metadata.regionID)-file-reason", from: [
                "This looks like a file or selection step, so keeping it clear may help the workflow make sense.",
                "A file action appears to be happening here; a steady focus can help viewers follow the choice.",
                "The viewer may need a clearer look at this selection moment."
            ])
        case .toolbarInteraction:
            if let label {
                return "\(label) appears to be the control in use, so highlighting it can help viewers understand the action."
            }
            return stableChoice(seed: "\(metadata.regionID)-toolbar-reason", from: [
                "This appears to involve a toolbar or control area, so highlighting it may make the action easier to follow.",
                "A tool or control seems important here; a clear focus moment can help orientation.",
                "The viewer may benefit from seeing which control is being used."
            ])
        case .sidebarInteraction:
            if let label {
                return "\(label) appears in the side panel, so keeping it visible can help the viewer stay oriented."
            }
            return stableChoice(seed: "\(metadata.regionID)-sidebar-reason", from: [
                "This looks like a sidebar or side panel step, so keeping that area clear may help orientation.",
                "The action appears to happen in a side panel; a subtle focus can help the viewer track it.",
                "The viewer may benefit from seeing the side-panel change clearly."
            ])
        case .contentEditing:
            if let label {
                return "\(label) appears to be part of the work area, so keeping it clear may help viewers follow the change."
            }
            return stableChoice(seed: "\(metadata.regionID)-content-reason", from: [
                "This looks like work inside the main editing area, so keeping focus steady may help the viewer follow the change.",
                "The workspace appears to change here; a clear focus moment can help the viewer stay oriented.",
                "This content area may be worth keeping clear if the edit depends on it."
            ])
        case .unknown:
            return screenContextSupportText(for: metadata)
        }
    }

    private func uiContextClassification(
        for region: ActivityRegion,
        observations: [SmartSuggestionOCRTextObservation],
        uniqueSnippets: [String],
        contentCoordinateSize: CGSize
    ) -> (context: SmartSuggestionUIContext, confidence: Double, supportingText: String?) {
        guard !observations.isEmpty || !region.sourceEvents.isEmpty else {
            return (.unknown, 0, nil)
        }

        var scores: [SmartSuggestionUIContext: Double] = [:]
        var supportingTextByContext: [SmartSuggestionUIContext: String] = [:]
        let sourcePoints = normalizedSourcePoints(
            from: region.sourceEvents,
            contentCoordinateSize: contentCoordinateSize
        )
        let nearbyText = nearbyTextSnippet(
            in: observations,
            sourcePoints: sourcePoints
        )
        let averageSourcePoint = averagePoint(sourcePoints)
        let changedText = hasTextChange(in: observations)

        func addScore(_ context: SmartSuggestionUIContext, _ amount: Double, supportingText: String? = nil) {
            scores[context, default: 0] += amount
            if supportingTextByContext[context] == nil {
                supportingTextByContext[context] = supportingText
            }
        }

        let definitions: [(context: SmartSuggestionUIContext, terms: [String], baseScore: Double)] = [
            (.settingsPanel, ["settings", "preferences", "options", "appearance", "theme", "account", "profile", "privacy", "general", "advanced"], 0.56),
            (.dialogInteraction, ["ok", "cancel", "apply", "save", "close", "done", "confirm", "delete", "continue", "allow", "dismiss"], 0.54),
            (.fileSelection, ["open", "save as", "choose", "browse", "import", "export", "file", "folder", "recent", "desktop", "documents", "downloads"], 0.54),
            (.formEntry, ["name", "email", "password", "url", "path", "username", "search", "address", "phone", "title", "field"], 0.52),
            (.menuInteraction, ["file", "edit", "view", "window", "help", "menu", "new", "copy", "paste", "select", "recent"], 0.48),
            (.toolbarInteraction, ["tool", "brush", "crop", "zoom", "align", "format", "bold", "italic", "share", "filter"], 0.46),
            (.sidebarInteraction, ["library", "favorites", "projects", "collections", "history", "navigation", "sidebar"], 0.46),
            (.textEditing, ["text", "font", "paragraph", "line", "typing", "comment", "note", "body", "heading"], 0.48),
            (.contentEditing, ["canvas", "timeline", "preview", "editor", "workspace", "content", "layer", "clip", "track"], 0.46)
        ]

        for definition in definitions {
            let matches = matchingSnippets(uniqueSnippets, terms: definition.terms)
            guard !matches.isEmpty else { continue }
            let matchBoost = min(Double(matches.count - 1) * 0.04, 0.12)
            addScore(definition.context, definition.baseScore + matchBoost, supportingText: matches.first)
        }

        if let nearbyText {
            addScore(.contentEditing, 0.08, supportingText: nearbyText)
            if scores[.formEntry, default: 0] > 0 {
                addScore(.formEntry, 0.08, supportingText: nearbyText)
            }
            if scores[.settingsPanel, default: 0] > 0 {
                addScore(.settingsPanel, 0.06, supportingText: nearbyText)
            }
            if scores[.dialogInteraction, default: 0] > 0 {
                addScore(.dialogInteraction, 0.06, supportingText: nearbyText)
            }
        }

        if changedText {
            addScore(.contentEditing, 0.09, supportingText: nearbyText ?? uniqueSnippets.first)
            if scores[.textEditing, default: 0] > 0 {
                addScore(.textEditing, 0.06, supportingText: nearbyText ?? uniqueSnippets.first)
            }
        }

        if let averageSourcePoint {
            if averageSourcePoint.x <= 0.22 {
                addScore(.sidebarInteraction, 0.28, supportingText: nearbyText ?? uniqueSnippets.first)
            }
            if averageSourcePoint.y <= 0.16 {
                addScore(.toolbarInteraction, 0.24, supportingText: nearbyText ?? uniqueSnippets.first)
            }
            if averageSourcePoint.x >= 0.78 && observations.count >= 4 {
                addScore(.contentEditing, 0.12, supportingText: nearbyText ?? uniqueSnippets.first)
            }
        }

        if observations.count >= 10 {
            addScore(.contentEditing, 0.10, supportingText: uniqueSnippets.first)
        }
        if region.kind == .clickSequence && observations.count >= 3 {
            addScore(.contentEditing, 0.08, supportingText: nearbyText ?? uniqueSnippets.first)
        }

        guard let best = scores
            .filter({ $0.key != .unknown })
            .sorted(by: contextScoreSort)
            .first else {
            return (.unknown, 0, nil)
        }

        let confidence = min(best.value, 0.92)
        guard confidence >= 0.42 else {
            return (.unknown, confidence, supportingTextByContext[best.key])
        }

        return (best.key, confidence, supportingTextByContext[best.key])
    }

    private func matchingSnippets(_ snippets: [String], terms: [String]) -> [String] {
        snippets.filter { snippet in
            let lowercasedSnippet = snippet.lowercased()
            return terms.contains { term in
                lowercasedSnippet.contains(term)
            }
        }
    }

    private func safeSupportingLabel(from metadata: SmartSuggestionOCRRegionMetadata) -> String? {
        guard let confidence = metadata.supportingTextConfidence, confidence >= 0.58 else { return nil }
        guard let text = metadata.supportingText else { return nil }

        let label = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count >= 3, label.count <= 32 else { return nil }

        if let knownLabel = knownCleanSupportingLabel(from: label) {
            return knownLabel
        }

        let words = label.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= 4 else { return nil }
        guard !label.contains(",") && !label.contains(";") && !label.contains(":") else {
            return nil
        }

        let scalars = Array(label.unicodeScalars)
        let letters = scalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let spaces = scalars.filter { CharacterSet.whitespaces.contains($0) }.count
        let allowedPunctuation = scalars.filter { "-_/&'.".unicodeScalars.contains($0) }.count
        let readableCount = letters + digits + spaces + allowedPunctuation
        guard letters >= 2, Double(readableCount) / Double(max(scalars.count, 1)) >= 0.86 else {
            return nil
        }

        let uppercaseLetters = scalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        let lowercaseLetters = scalars.filter { CharacterSet.lowercaseLetters.contains($0) }.count
        if lowercaseLetters == 0, uppercaseLetters >= 5 {
            return nil
        }

        let lowercasedLabel = label.lowercased()
        let rejectedFragments = [
            "|", "•", "ooo", "lll", "iii", "xxx", "sh4", "lniim",
            " projec", " availabl", " automati", " on the ser"
        ]
        guard !rejectedFragments.contains(where: { lowercasedLabel.contains($0) }) else {
            return nil
        }
        guard !looksLikeCombinedOrSentenceLabel(words.map(String.init), lowercasedLabel: lowercasedLabel) else {
            return nil
        }

        return label
    }

    private func knownCleanSupportingLabel(from label: String) -> String? {
        let lowercasedLabel = label.lowercased()
        if lowercasedLabel.contains("search by snapshot name") {
            return "snapshot search"
        }
        if lowercasedLabel.contains("creator name") {
            return "Creator Name"
        }
        if lowercasedLabel.contains("wp themes") {
            return "WP Themes"
        }
        return nil
    }

    private func looksLikeCombinedOrSentenceLabel(_ words: [String], lowercasedLabel: String) -> Bool {
        if lowercasedLabel.contains(" available ")
            || lowercasedLabel.contains(" on the ")
            || lowercasedLabel.contains(" if ")
            || lowercasedLabel.contains(" and ") {
            return true
        }

        let lowercasedWords = words.map { $0.lowercased() }
        let commandLikeWords = Set([
            "preview", "automatic", "snapshot", "clear", "apply", "cancel",
            "save", "close", "open", "choose", "browse", "available"
        ])
        let commandWordCount = lowercasedWords.filter { commandLikeWords.contains($0) }.count
        if words.count >= 4, commandWordCount >= 3 {
            return true
        }

        let lastWord = lowercasedWords.last ?? ""
        let suspiciousEndings = Set(["projec", "ser", "availabl", "automati"])
        return suspiciousEndings.contains(lastWord)
    }

    private func formFieldLabelPhrase(_ label: String) -> String {
        let lowercasedLabel = label.lowercased()
        if lowercasedLabel == "snapshot search" {
            return "snapshot search"
        }
        if lowercasedLabel == "search by snapshot name" {
            return "snapshot search"
        }
        if lowercasedLabel.hasPrefix("search by ") {
            let searchSubject = label.dropFirst("Search by ".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !searchSubject.isEmpty {
                return "\(searchSubject) search"
            }
        }
        if lowercasedLabel.contains("search") {
            return label
        }
        return "\"\(label)\""
    }

    private func confidence(
        for snippet: String?,
        in observations: [SmartSuggestionOCRTextObservation]
    ) -> Float? {
        guard let snippet else { return nil }
        let key = snippet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return observations
            .filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
            .map(\.confidence)
            .max()
    }

    private func nearbyTextSnippet(
        in observations: [SmartSuggestionOCRTextObservation],
        sourcePoints: [CGPoint]
    ) -> String? {
        guard !sourcePoints.isEmpty else { return nil }

        return observations
            .sorted(by: observationSort)
            .first { observation in
                let textCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
                return sourcePoints.contains { sourcePoint in
                    distance(from: sourcePoint, to: textCenter) <= nearbyTextDistance
                        || observation.boundingBox.insetBy(dx: -0.04, dy: -0.04).contains(sourcePoint)
                }
            }?
            .text
    }

    private func averagePoint(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(
                x: partialResult.x + point.x,
                y: partialResult.y + point.y
            )
        }
        let count = CGFloat(points.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private func contextScoreSort(
        _ lhs: Dictionary<SmartSuggestionUIContext, Double>.Element,
        _ rhs: Dictionary<SmartSuggestionUIContext, Double>.Element
    ) -> Bool {
        if lhs.value != rhs.value {
            return lhs.value > rhs.value
        }
        return contextPriority(lhs.key) < contextPriority(rhs.key)
    }

    private func contextPriority(_ context: SmartSuggestionUIContext) -> Int {
        switch context {
        case .settingsPanel:
            return 0
        case .dialogInteraction:
            return 1
        case .fileSelection:
            return 2
        case .formEntry:
            return 3
        case .menuInteraction:
            return 4
        case .textEditing:
            return 5
        case .toolbarInteraction:
            return 6
        case .sidebarInteraction:
            return 7
        case .contentEditing:
            return 8
        case .unknown:
            return 9
        }
    }

    private func screenContextSupportText(for metadata: SmartSuggestionOCRRegionMetadata) -> String {
        if metadata.hasTextChange {
            return stableChoice(seed: "\(metadata.regionID)-content-change", from: [
                "The screen content changes here, so this moment may be worth keeping clear.",
                "Something on screen changes during this moment, which may help the viewer if it stays easy to follow.",
                "This interaction changes what is visible, so a steady focus could help."
            ])
        }

        return stableChoice(seed: "\(metadata.regionID)-readable-content", from: [
            "There is readable content on screen, so a steadier focus may help.",
            "This part may be easier to follow if the viewer can stay oriented.",
            "The viewer may need a clear look at the screen content here."
        ])
    }

    private func stableChoice(seed: String, from options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        let value = seed.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult &* 31) &+ Int(scalar.value)) & 0x7fffffff
        }
        return options[value % options.count]
    }

    private func cropTextObservations(
        for sample: ActivityRegionFrameSample,
        region: ActivityRegion?
    ) async throws -> [SmartSuggestionOCRTextObservation] {
        guard let region,
              let normalizedCropRect = normalizedCropRect(for: region),
              let croppedImage = crop(sample.image, to: normalizedCropRect) else {
            return []
        }

        return try await recognizedTextObservations(
            image: croppedImage,
            regionID: sample.regionID,
            frameTimestamp: sample.actualTime
        ) { boundingBox in
            CGRect(
                x: normalizedCropRect.minX + (boundingBox.minX * normalizedCropRect.width),
                y: normalizedCropRect.minY + (boundingBox.minY * normalizedCropRect.height),
                width: boundingBox.width * normalizedCropRect.width,
                height: boundingBox.height * normalizedCropRect.height
            )
        }
    }

    private func recognizedTextObservations(
        image: CGImage,
        regionID: String,
        frameTimestamp: Double,
        boundingBoxTransform: @escaping (CGRect) -> CGRect = { $0 }
    ) async throws -> [SmartSuggestionOCRTextObservation] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SmartSuggestionOCRTextObservation], Error>) in
            Self.textRecognitionQueue.async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.automaticallyDetectsLanguage = false
                    request.recognitionLanguages = ["en-US"]
                    request.minimumTextHeight = minimumTextHeight

                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])

                    let recognizedTextObservations = request.results ?? []
                    let observations: [SmartSuggestionOCRTextObservation] = recognizedTextObservations.compactMap { observation in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }

                        return SmartSuggestionOCRTextObservation(
                            regionID: regionID,
                            frameTimestamp: frameTimestamp,
                            text: text,
                            confidence: candidate.confidence,
                            boundingBox: boundingBoxTransform(observation.boundingBox)
                        )
                    }
                    continuation.resume(returning: observations)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func normalizedCropRect(for region: ActivityRegion) -> CGRect? {
        let baseRect: CGRect?
        if let normalizedArea = region.normalizedArea, !normalizedArea.isNull, !normalizedArea.isEmpty {
            baseRect = normalizedArea
        } else {
            let points = normalizedSourcePoints(
                from: region.sourceEvents,
                contentCoordinateSize: CGSize(width: 1, height: 1)
            )
            if let averagePoint = averagePoint(points) {
                baseRect = CGRect(
                    x: averagePoint.x,
                    y: averagePoint.y,
                    width: 0,
                    height: 0
                )
            } else {
                baseRect = nil
            }
        }

        guard let baseRect else { return nil }
        let padding = cropPadding(for: region)
        let paddedRect = baseRect.insetBy(dx: -padding, dy: -padding)
        let minimumSize = minimumCropSize(for: region)
        let expandedRect = CGRect(
            x: paddedRect.midX - max(paddedRect.width, minimumSize.width) / 2,
            y: paddedRect.midY - max(paddedRect.height, minimumSize.height) / 2,
            width: max(paddedRect.width, minimumSize.width),
            height: max(paddedRect.height, minimumSize.height)
        )

        return expandedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func cropPadding(for region: ActivityRegion) -> CGFloat {
        switch region.kind {
        case .click:
            return cropPadding
        case .clickSequence:
            return 0.18
        case .pause, .repeatedArea:
            return 0.22
        case .unknown:
            return 0.20
        }
    }

    private func minimumCropSize(for region: ActivityRegion) -> CGSize {
        switch region.kind {
        case .click:
            return CGSize(width: 0.34, height: 0.28)
        case .clickSequence:
            return CGSize(width: 0.42, height: 0.34)
        case .pause, .repeatedArea:
            return CGSize(width: 0.48, height: 0.40)
        case .unknown:
            return CGSize(width: 0.44, height: 0.36)
        }
    }

    private func crop(_ image: CGImage, to normalizedRect: CGRect) -> CGImage? {
        let imageRect = CGRect(
            x: CGFloat(image.width) * normalizedRect.minX,
            y: CGFloat(image.height) * normalizedRect.minY,
            width: CGFloat(image.width) * normalizedRect.width,
            height: CGFloat(image.height) * normalizedRect.height
        )
        let clampedRect = imageRect
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            .integral
        guard clampedRect.width >= 8, clampedRect.height >= 8 else { return nil }
        return image.cropping(to: clampedRect)
    }

    private func uniqueTextSnippets(from observations: [SmartSuggestionOCRTextObservation]) -> [String] {
        var seenStrings = Set<String>()
        var snippets: [String] = []
        for observation in observations.sorted(by: observationSort) {
            let normalizedText = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedText.count >= 2 else { continue }
            let key = normalizedText.lowercased()
            guard !seenStrings.contains(key) else { continue }
            seenStrings.insert(key)
            snippets.append(normalizedText)
        }
        return snippets
    }

    private func hasNearbyText(
        in observations: [SmartSuggestionOCRTextObservation],
        sourceEvents: [SmartSetupSourceEventReference],
        contentCoordinateSize: CGSize
    ) -> Bool {
        let sourcePoints = normalizedSourcePoints(
            from: sourceEvents,
            contentCoordinateSize: contentCoordinateSize
        )
        guard !sourcePoints.isEmpty else { return false }

        return observations.contains { observation in
            let textCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
            return sourcePoints.contains { sourcePoint in
                distance(from: sourcePoint, to: textCenter) <= nearbyTextDistance
                    || observation.boundingBox.insetBy(dx: -0.04, dy: -0.04).contains(sourcePoint)
            }
        }
    }

    private func hasTextChange(in observations: [SmartSuggestionOCRTextObservation]) -> Bool {
        guard let firstTime = observations.map(\.frameTimestamp).min(),
              let lastTime = observations.map(\.frameTimestamp).max(),
              lastTime - firstTime > 0.05 else {
            return false
        }

        let midpoint = (firstTime + lastTime) / 2
        let earlyText = Set(observations
            .filter { $0.frameTimestamp <= midpoint }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 2 })
        let lateText = Set(observations
            .filter { $0.frameTimestamp > midpoint }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 2 })

        guard !earlyText.isEmpty, !lateText.isEmpty else { return false }
        return earlyText.symmetricDifference(lateText).count >= 2
    }

    private func normalizedSourcePoints(
        from sourceEvents: [SmartSetupSourceEventReference],
        contentCoordinateSize: CGSize
    ) -> [CGPoint] {
        let safeWidth = max(contentCoordinateSize.width, 1)
        let safeHeight = max(contentCoordinateSize.height, 1)
        return sourceEvents
            .filter { $0.type == .leftMouseDown || $0.type == .rightMouseDown || $0.type == .cursorMoved }
            .map { event in
                CGPoint(
                    x: min(max(event.x / safeWidth, 0), 1),
                    y: min(max(event.y / safeHeight, 0), 1)
                )
            }
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return sqrt((deltaX * deltaX) + (deltaY * deltaY))
    }

    private func previewStrings(from observations: [SmartSuggestionOCRTextObservation]) -> [String] {
        var seenStrings = Set<String>()
        var preview: [String] = []

        for observation in observations.sorted(by: observationSort) {
            let normalizedText = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedText.count >= 2 else { continue }
            let key = normalizedText.lowercased()
            guard !seenStrings.contains(key) else { continue }
            seenStrings.insert(key)
            preview.append(normalizedText)

            if preview.count >= maximumPreviewStrings {
                break
            }
        }

        return preview
    }

    private func observationSort(_ lhs: SmartSuggestionOCRTextObservation, _ rhs: SmartSuggestionOCRTextObservation) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.frameTimestamp != rhs.frameTimestamp {
            return lhs.frameTimestamp < rhs.frameTimestamp
        }
        return lhs.text < rhs.text
    }
}
