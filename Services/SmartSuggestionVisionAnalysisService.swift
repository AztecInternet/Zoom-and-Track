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

enum SmartSuggestionOCRTextRole: String {
    case clickTargetText
    case nearbyContextText
    case changedAreaText
    case pageContentText
    case fallbackText

    var debugLabel: String { rawValue }
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
    let supportingTextRole: SmartSuggestionOCRTextRole
    let supportingTextRoleReason: String?

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
        contentCoordinateSize: CGSize,
        visualChangeMetadataByID: [String: SmartSuggestionVisualChangeMetadata] = [:]
    ) -> [String: SmartSuggestionOCRRegionMetadata] {
        let observationsByRegionID = Dictionary(grouping: analysisResult.observations, by: \.regionID)
        return regions.reduce(into: [:]) { partialResult, region in
            let observations = observationsByRegionID[region.id] ?? []
            partialResult[region.id] = metadata(
                for: region,
                observations: observations,
                contentCoordinateSize: contentCoordinateSize,
                visualChangeMetadata: visualChangeMetadataByID[region.id]
            )
        }
    }

    func visionTunedSuggestions(
        from suggestions: [SmartSetupSuggestion],
        regionMetadataByID: [String: SmartSuggestionOCRRegionMetadata],
        visualChangeMetadataByID: [String: SmartSuggestionVisualChangeMetadata] = [:]
    ) -> [SmartSetupSuggestion] {
        suggestions.compactMap { suggestion in
            let regionID = "suggestion-\(suggestion.suggestionID)"
            let metadata = regionMetadataByID[regionID]
            let visualChangeMetadata = visualChangeMetadataByID[regionID]
            return visionTunedSuggestion(
                suggestion,
                metadata: metadata,
                visualChangeMetadata: visualChangeMetadata
            )
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
        contentCoordinateSize: CGSize,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> SmartSuggestionOCRRegionMetadata {
        let uniqueSnippets = uniqueTextSnippets(from: observations)
        let classification = uiContextClassification(
            for: region,
            observations: observations,
            uniqueSnippets: uniqueSnippets,
            contentCoordinateSize: contentCoordinateSize,
            visualChangeMetadata: visualChangeMetadata
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
            ),
            supportingTextRole: classification.supportingTextRole,
            supportingTextRoleReason: classification.supportingTextRoleReason
        )
    }

    private func visionTunedSuggestion(
        _ suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> SmartSetupSuggestion? {
        var tunedSuggestion = suggestion
        let baseScore = tunedSuggestion.score.value
        var scoreAdjustment = 0.0

        if let metadata {
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
        }

        if let visualChangeMetadata {
            scoreAdjustment += visualChangeScoreAdjustment(for: suggestion, metadata: visualChangeMetadata)
        }
        scoreAdjustment += existingEditEvidenceScoreAdjustment(
            for: suggestion,
            metadata: metadata,
            visualChangeMetadata: visualChangeMetadata
        )

        let tunedScore = min(max(baseScore + scoreAdjustment, 0), 1)
        if let metadata,
           shouldSuppress(suggestion, tunedScore: tunedScore, metadata: metadata) {
            debugSuppressedSuggestion(suggestion, reason: "weak proposed suggestion", intent: "add")
            return nil
        }
        if shouldSuppressEmptyExistingEdit(
            suggestion,
            metadata: metadata,
            visualChangeMetadata: visualChangeMetadata
        ) {
            debugSuppressedSuggestion(suggestion, reason: "existing edit has no supporting evidence", intent: editIntentName(for: suggestion))
            return nil
        }
        if shouldSuppressWeakProposedSuggestion(
            suggestion,
            tunedScore: tunedScore,
            metadata: metadata,
            visualChangeMetadata: visualChangeMetadata
        ) {
            debugSuppressedSuggestion(suggestion, reason: "weak add opportunity", intent: "add")
            return nil
        }

        tunedSuggestion.score = SmartSetupCandidateScore(
            value: tunedScore,
            components: suggestion.score.components
        )

        if let metadata, tunedSuggestion.providerID != "existing-edits" {
            tunedSuggestion.userReason = visionSupportedReason(
                existingReason: tunedSuggestion.userReason,
                metadata: metadata,
                visualChangeMetadata: visualChangeMetadata
            )
            tunedSuggestion.userTitle = contextSupportedTitle(
                existingTitle: tunedSuggestion.userTitle,
                suggestion: tunedSuggestion,
                metadata: metadata
            )
        } else if let visualChangeMetadata, tunedSuggestion.providerID != "existing-edits" {
            tunedSuggestion.userReason = visualChangeSupportedReason(
                existingReason: tunedSuggestion.userReason,
                metadata: nil,
                visualChangeMetadata: visualChangeMetadata
            )
        }
        if tunedSuggestion.providerID == "existing-edits" {
            tunedSuggestion = existingEditEvidenceWording(
                for: tunedSuggestion,
                metadata: metadata,
                visualChangeMetadata: visualChangeMetadata
            )
        }
        return tunedSuggestion
    }

    private func existingEditEvidenceScoreAdjustment(
        for suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> Double {
        guard suggestion.providerID == "existing-edits" else { return 0 }

        var adjustment = 0.0
        if let visualChangeMetadata {
            if visualChangeMetadata.hasVisibleChange {
                adjustment += 0.03
            }
            if visualChangeMetadata.changeNearInteraction {
                adjustment += 0.03
            }
            if visualChangeMetadata.likelyLargeTransition {
                adjustment += 0.025
            }
        }
        if let metadata {
            if metadata.hasTextChange {
                adjustment += 0.025
            }
            if metadata.hasTextNearSourceEvent {
                adjustment += 0.02
            }
            if metadata.hasUsefulUIContext {
                adjustment += 0.02
            }
            if !metadata.appearsVisuallyMeaningful && visualChangeMetadata?.hasVisibleChange != true {
                adjustment -= 0.035
            }
        } else if visualChangeMetadata?.hasVisibleChange != true {
            adjustment -= 0.025
        }

        return min(max(adjustment, -0.04), 0.10)
    }

    private func visualChangeScoreAdjustment(
        for suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionVisualChangeMetadata
    ) -> Double {
        guard metadata.hasVisibleChange else {
            guard suggestion.providerID == "rules" || suggestion.providerID == "templates" else { return 0 }
            return -0.03
        }

        var adjustment = 0.0
        if metadata.changeNearInteraction {
            adjustment += 0.04
        } else if metadata.changeFarFromInteraction {
            adjustment += 0.008
        }
        if metadata.likelyPanelOpen || metadata.likelyPanelClose {
            adjustment += 0.012
        }
        if metadata.likelyLargeTransition {
            adjustment += 0.02
        }
        return min(max(adjustment, -0.035), 0.06)
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

    private func shouldSuppressEmptyExistingEdit(
        _ suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> Bool {
        guard suggestion.providerID == "existing-edits" else { return false }
        guard suggestion.sourceEvents.isEmpty else { return false }
        let hasTextEvidence = metadata?.appearsVisuallyMeaningful == true || metadata?.hasUsefulUIContext == true
        let hasVisualEvidence = visualChangeMetadata?.hasVisibleChange == true
        guard !hasTextEvidence && !hasVisualEvidence else { return false }
        return suggestion.userTitle == "Keep this effect"
            || suggestion.userTitle == "Keep this zoom"
            || suggestion.userTitle == "Review this focus effect"
            || suggestion.userTitle == "Review this visual effect"
            || suggestion.userTitle == "Review this focus zoom"
    }

    private func shouldSuppressWeakProposedSuggestion(
        _ suggestion: SmartSetupSuggestion,
        tunedScore: Double,
        metadata: SmartSuggestionOCRRegionMetadata?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> Bool {
        guard suggestion.providerID != "existing-edits" else { return false }
        guard tunedScore < 0.52 else { return false }
        let hasTextEvidence = metadata?.appearsVisuallyMeaningful == true || metadata?.hasUsefulUIContext == true
        let hasVisualEvidence = visualChangeMetadata.map(visualChangeIsMeaningfulForWording) ?? false
        let hasSourceEvents = !suggestion.sourceEvents.isEmpty
        return !hasTextEvidence && !hasVisualEvidence && !hasSourceEvents
    }

    private func editIntentName(for suggestion: SmartSetupSuggestion) -> String {
        if case .zoomAdjustment = suggestion.proposal {
            return "adjust"
        }
        guard suggestion.providerID == "existing-edits" else {
            return "add"
        }
        let title = suggestion.userTitle?.lowercased() ?? ""
        if title.hasPrefix("consider removing") || title.hasPrefix("remove") {
            return "remove"
        }
        if title.hasPrefix("keep") {
            return "keep"
        }
        if title.hasPrefix("extend")
            || title.hasPrefix("resize")
            || title.hasPrefix("move")
            || title.hasPrefix("shorten")
            || title.contains(" adjust ") {
            return "adjust"
        }
        return "reviewFallback"
    }

    private func debugSuppressedSuggestion(_ suggestion: SmartSetupSuggestion, reason: String, intent: String) {
        #if DEBUG
        let title = suggestion.userTitle ?? "n/a"
        let existingState = suggestion.providerID == "existing-edits" ? "existing" : "new"
        print("[SmartSuggestionIntent] suppressed suggestionID=\(suggestion.suggestionID) providerID=\(suggestion.providerID) existing=\(existingState) intent=\(intent) title=\(title) reason=\(reason)")
        #endif
    }

    private func visionSupportedReason(
        existingReason: String?,
        metadata: SmartSuggestionOCRRegionMetadata,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> String? {
        if metadata.hasUsefulUIContext {
            return contextSupportedReason(metadata, visualChangeMetadata: visualChangeMetadata)
        }
        if let visualReason = visualChangeSupportedReason(
            existingReason: nil,
            metadata: metadata,
            visualChangeMetadata: visualChangeMetadata
        ) {
            return visualReason
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
                    "Add a short focus hold around \(label)",
                    "Add a short focus hold around \(label)",
                    "Add a short zoom hold around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-settings-title", from: [
                "Add a short focus hold to the settings",
                "Add a short zoom hold for this settings change",
                "Add a focus hold around these options"
            ])
        case .menuInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-menu-label-title", from: [
                    "Add a short focus hold around \(label)",
                    "Add a short focus hold for the \(label) menu action",
                    "Add a short zoom hold around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-menu-title", from: [
                "Add a short focus hold to this menu action",
                "Add a short zoom hold for this menu choice",
                "Add a focus hold through this menu change"
            ])
        case .dialogInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-dialog-label-title", from: [
                    "Add a short focus hold around \(label)",
                    "Add a short focus hold for the \(label) confirmation",
                    "Add a subtle focus effect around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-dialog-title", from: [
                "Add a subtle focus effect to this dialog moment",
                "Add a short focus hold to this dialog",
                "Add a short focus hold for this confirmation"
            ])
        case .textEditing:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-text-label-title", from: [
                    "Add a short focus hold around \(label)",
                    "Add a short focus hold for the \(label) text change",
                    "Add a short zoom hold around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-text-title", from: [
                "Add a short focus hold to this text edit",
                "Add a short zoom hold for this text change",
                "Add a focus hold around the edited text"
            ])
        case .formEntry:
            if let label {
                let fieldLabel = formFieldLabelPhrase(label)
                return stableChoice(seed: "\(metadata.regionID)-form-label-title", from: [
                    "Add a short focus hold around the \(fieldLabel)",
                    "Add a short zoom hold around the \(fieldLabel)",
                    "Add a focus hold for the \(fieldLabel)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-form-title", from: [
                "Add a short focus hold to this form entry",
                "Add a short zoom hold for this field",
                "Add a focus hold through this input step"
            ])
        case .fileSelection:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-file-label-title", from: [
                    "Add a short focus hold around \(label)",
                    "Add a short focus hold for the \(label) file step",
                    "Add a subtle focus effect around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-file-title", from: [
                "Add a short focus hold to this file choice",
                "Add a short zoom hold for this file step",
                "Add a focus hold around this selection"
            ])
        case .toolbarInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-toolbar-label-title", from: [
                    "Add a short focus hold around \(label)",
                    "Add a short focus hold for the \(label) tool",
                    "Add a subtle focus effect around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-toolbar-title", from: [
                "Add a short focus hold to this toolbar action",
                "Add a short zoom hold for this tool choice",
                "Add a focus hold around this control"
            ])
        case .sidebarInteraction:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-sidebar-label-title", from: [
                    "Add a subtle focus effect to \(label)",
                    "Add a focus effect to the \(label) sidebar action",
                    "Add a subtle focus effect around \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-sidebar-title", from: [
                "Add a subtle focus effect to the side panel",
                "Add a focus effect to this sidebar action",
                "Add a subtle focus effect around the side panel"
            ])
        case .contentEditing:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-content-label-title", from: [
                    "Add a short focus hold around \(label)",
                    "Add a short zoom hold around \(label)",
                    "Add a focus hold for \(label)"
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-content-title", from: [
                "Add a short focus hold to the editing area",
                "Add a subtle focus effect to this workspace",
                "Add a short focus hold for this content change"
            ])
        case .unknown:
            return existingTitle ?? fallbackTitle(for: suggestion)
        }
    }

    private func existingEditEvidenceWording(
        for suggestion: SmartSetupSuggestion,
        metadata: SmartSuggestionOCRRegionMetadata?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> SmartSetupSuggestion {
        var tunedSuggestion = suggestion
        let label = metadata.flatMap(safeSupportingLabel(from:))
        let hasMeaningfulVisualChange = visualChangeMetadata.map(visualChangeIsMeaningfulForExistingEdit) ?? false
        let hasStrongTextEvidence = metadata.map { metadata in
            metadata.hasTextChange || metadata.hasTextNearSourceEvent || metadata.hasUsefulUIContext
        } ?? false

        switch tunedSuggestion.proposal {
        case .effect:
            if isMismatchExistingEffectSuggestion(tunedSuggestion) {
                break
            } else if isShortExistingEffectSuggestion(tunedSuggestion) {
                tunedSuggestion.userTitle = "Extend this effect"
                tunedSuggestion.userReason = "Viewers may need more time to understand the highlighted area."
            } else if visualChangeMetadata?.likelyLargeTransition == true {
                tunedSuggestion.userTitle = "Keep this effect"
                tunedSuggestion.userReason = existingEffectLargeChangeReason(
                    label: label,
                    metadata: metadata,
                    regionID: visualChangeMetadata?.regionID ?? metadata?.regionID ?? tunedSuggestion.suggestionID
                )
            } else if hasMeaningfulVisualChange {
                tunedSuggestion.userTitle = "Keep this effect"
                tunedSuggestion.userReason = existingEffectVisibleChangeReason(
                    label: label,
                    metadata: metadata,
                    regionID: visualChangeMetadata?.regionID ?? metadata?.regionID ?? tunedSuggestion.suggestionID
                )
            } else if hasStrongTextEvidence {
                tunedSuggestion.userTitle = "Keep this effect"
                tunedSuggestion.userReason = existingEffectTextReason(
                    label: label,
                    metadata: metadata,
                    regionID: metadata?.regionID ?? tunedSuggestion.suggestionID
                )
            }
        case .zoom:
            if isShortExistingZoomSuggestion(tunedSuggestion) && (hasMeaningfulVisualChange || hasStrongTextEvidence || !tunedSuggestion.sourceEvents.isEmpty) {
                tunedSuggestion.userTitle = "Extend this zoom hold by about 0.5 seconds"
                tunedSuggestion.userReason = "Viewers may need more time to absorb the information before the zoom ends."
            } else if visualChangeMetadata?.likelyLargeTransition == true {
                tunedSuggestion.userTitle = "Keep this zoom"
                tunedSuggestion.userReason = existingZoomLargeChangeReason(
                    label: label,
                    metadata: metadata,
                    regionID: visualChangeMetadata?.regionID ?? metadata?.regionID ?? tunedSuggestion.suggestionID
                )
            } else if hasMeaningfulVisualChange && visualChangeMetadata?.changeNearInteraction == true {
                tunedSuggestion.userTitle = "Keep this zoom"
                tunedSuggestion.userReason = existingZoomVisibleChangeReason(
                    label: label,
                    metadata: metadata,
                    regionID: visualChangeMetadata?.regionID ?? metadata?.regionID ?? tunedSuggestion.suggestionID
                )
            } else if hasStrongTextEvidence {
                tunedSuggestion.userTitle = "Keep this zoom"
                tunedSuggestion.userReason = existingZoomTextReason(
                    label: label,
                    metadata: metadata,
                    regionID: metadata?.regionID ?? tunedSuggestion.suggestionID
                )
            }
        case .zoomAdjustment, .regionTighten:
            break
        }

        return tunedSuggestion
    }

    private func existingEffectLargeChangeReason(
        label: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        regionID: String
    ) -> String {
        if let label {
            let target = metadata.map { visualChangeLabelPhrase(label, context: $0.uiContext) } ?? label
            return stableChoice(seed: "\(regionID)-existing-effect-large-label", from: [
                "The effect stays relevant while \(target) changes.",
                "The highlighted area continues to guide attention through the transition around \(target)."
            ])
        }
        return stableChoice(seed: "\(regionID)-existing-effect-large", from: [
            "The effect remains useful after the screen changes.",
            "The highlighted area continues to guide attention through the transition."
        ])
    }

    private func existingEffectVisibleChangeReason(
        label: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        regionID: String
    ) -> String {
        if let label {
            let target = metadata.map { visualChangeLabelPhrase(label, context: $0.uiContext) } ?? label
            return stableChoice(seed: "\(regionID)-existing-effect-change-label", from: [
                "The effect keeps \(target) clear enough for viewers to follow.",
                "The highlighted area stays useful as \(target) changes."
            ])
        }
        return stableChoice(seed: "\(regionID)-existing-effect-change", from: [
            "The effect guides attention to the intended area.",
            "The highlighted area remains relevant while the screen changes."
        ])
    }

    private func existingEffectTextReason(
        label: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        regionID: String
    ) -> String {
        if let label {
            let target = metadata.map { visualChangeLabelPhrase(label, context: $0.uiContext) } ?? label
            return "The effect keeps \(target) readable and easy to understand."
        }
        return stableChoice(seed: "\(regionID)-existing-effect-text", from: [
            "The effect keeps the important content readable.",
            "The highlighted area remains clear throughout the effect."
        ])
    }

    private func existingZoomLargeChangeReason(
        label: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        regionID: String
    ) -> String {
        if let label {
            let target = metadata.map { visualChangeLabelPhrase(label, context: $0.uiContext) } ?? label
            return stableChoice(seed: "\(regionID)-existing-zoom-large-label", from: [
                "The zoom helps viewers follow the transition around \(target).",
                "\(target) stays visible long enough to understand the change."
            ])
        }
        return stableChoice(seed: "\(regionID)-existing-zoom-large", from: [
            "The zoom helps viewers follow the transition.",
            "The larger screen change has enough time to land."
        ])
    }

    private func existingZoomVisibleChangeReason(
        label: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        regionID: String
    ) -> String {
        if let label {
            let target = metadata.map { visualChangeLabelPhrase(label, context: $0.uiContext) } ?? label
            return stableChoice(seed: "\(regionID)-existing-zoom-change-label", from: [
                "The zoom keeps \(target) clear enough for viewers to follow.",
                "The zoom stays on the information viewers need as \(target) changes."
            ])
        }
        return stableChoice(seed: "\(regionID)-existing-zoom-change", from: [
            "The zoom guides attention to the most important part of the screen.",
            "The result remains visible long enough to follow."
        ])
    }

    private func existingZoomTextReason(
        label: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        regionID: String
    ) -> String {
        if let label {
            let target = metadata.map { visualChangeLabelPhrase(label, context: $0.uiContext) } ?? label
            return "The zoom keeps \(target) readable and easy to understand."
        }
        return stableChoice(seed: "\(regionID)-existing-zoom-text", from: [
            "The zoom keeps the important content readable.",
            "Viewers get a clear look at this part of the screen."
        ])
    }

    private func isMismatchExistingEffectSuggestion(_ suggestion: SmartSetupSuggestion) -> Bool {
        suggestion.providerID == "existing-edits" && (
            suggestion.userTitle == "Resize this effect region"
                || suggestion.userTitle == "Expand this effect region to include the changing content"
                || suggestion.userTitle == "Check this effect region"
        )
    }

    private func isShortExistingEffectSuggestion(_ suggestion: SmartSetupSuggestion) -> Bool {
        suggestion.providerID == "existing-edits" && (suggestion.userTitle == "Extend this effect" || suggestion.userTitle == "Check this effect timing")
    }

    private func visualChangeIsMeaningfulForExistingEdit(_ metadata: SmartSuggestionVisualChangeMetadata) -> Bool {
        guard metadata.hasVisibleChange else { return false }
        return metadata.changeNearInteraction
            || metadata.likelyLargeTransition
            || metadata.changeScore >= 0.16
            || metadata.changedAreaPercentage >= 0.04
    }

    private func isShortExistingZoomSuggestion(_ suggestion: SmartSetupSuggestion) -> Bool {
        guard suggestion.providerID == "existing-edits",
              case .zoom(let proposal) = suggestion.proposal,
              let range = suggestion.sourceTimeRange else {
            return false
        }
        return range.endTime - range.startTime < 1.15 || proposal.holdDuration < 0.45
    }

    private func fallbackTitle(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return "Add a steadier focus sequence"
        case .zoom:
            return "Add a short focus hold here"
        case .effect:
            return "Add a subtle focus effect here"
        case .regionTighten:
            return "Resize this focus area"
        }
    }

    private func contextSupportedReason(
        _ metadata: SmartSuggestionOCRRegionMetadata,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> String {
        let label = safeSupportingLabel(from: metadata)
        if let visualReason = visualChangeSupportedReason(
            existingReason: nil,
            metadata: metadata,
            visualChangeMetadata: visualChangeMetadata
        ) {
            return visualReason
        }

        switch metadata.uiContext {
        case .settingsPanel:
            if let label {
                return stableChoice(seed: "\(metadata.regionID)-settings-label-reason", from: [
                    "\(label) needs to stay readable while viewers follow the change.",
                    "The adjustment may be easy to miss at the current pace.",
                    "Viewers may need more orientation around \(label)."
                ])
            }
            return stableChoice(seed: "\(metadata.regionID)-settings-reason", from: [
                "Viewers may need more time to follow this settings change.",
                "The edit depends on this options area staying readable.",
                "It may not be obvious which setting is being adjusted."
            ])
        case .menuInteraction:
            if let label {
                return "Viewers may need help following the \(label) choice."
            }
            return stableChoice(seed: "\(metadata.regionID)-menu-reason", from: [
                "This menu choice appears important to the step.",
                "The menu step may need more visual clarity.",
                "The menu action may move past too quickly."
            ])
        case .dialogInteraction:
            if let label {
                return "The viewer may need time to understand the \(label) decision."
            }
            return stableChoice(seed: "\(metadata.regionID)-dialog-reason", from: [
                "This dialog decision appears to matter to the step.",
                "The dialog needs to stay readable for the edit to make sense.",
                "This confirmation may matter to the final story."
            ])
        case .textEditing:
            if let label {
                return "\(label) needs to remain readable while the change happens."
            }
            return stableChoice(seed: "\(metadata.regionID)-text-reason", from: [
                "Viewers may need time to read the text change.",
                "The text edit is easy to miss at the current pace.",
                "The text may not stay readable long enough."
            ])
        case .formEntry:
            if let label {
                let fieldLabel = formFieldLabelPhrase(label)
                return "Viewers may need help following the \(fieldLabel) entry."
            }
            return stableChoice(seed: "\(metadata.regionID)-form-reason", from: [
                "This field entry may need to be clearer.",
                "The input area may need more emphasis to reduce confusion.",
                "It may not be obvious which field is being used."
            ])
        case .fileSelection:
            if let label {
                return "The \(label) selection step may need to be clearer."
            }
            return stableChoice(seed: "\(metadata.regionID)-file-reason", from: [
                "This file or selection step appears to matter to the workflow.",
                "Viewers may need help following the file action.",
                "The selection may move past too quickly."
            ])
        case .toolbarInteraction:
            if let label {
                return "Viewers may need help understanding that \(label) is the control being used."
            }
            return stableChoice(seed: "\(metadata.regionID)-toolbar-reason", from: [
                "This toolbar action is easy to miss.",
                "The control may need to stay visible longer.",
                "It may not be obvious which control is being used."
            ])
        case .sidebarInteraction:
            if let label {
                return "The side-panel step around \(label) may need clearer emphasis."
            }
            return stableChoice(seed: "\(metadata.regionID)-sidebar-reason", from: [
                "This side-panel step may need clearer orientation.",
                "Viewers may need more time to track the side-panel action.",
                "The side-panel change may move past too quickly."
            ])
        case .contentEditing:
            if let label {
                return "Viewers may need help following the change around \(label)."
            }
            return stableChoice(seed: "\(metadata.regionID)-content-reason", from: [
                "This workspace change needs to stay clear.",
                "Viewers may need help staying oriented in this content area.",
                "This content change appears to matter to the edit."
            ])
        case .unknown:
            return screenContextSupportText(for: metadata)
        }
    }

    private func visualChangeSupportedReason(
        existingReason: String?,
        metadata: SmartSuggestionOCRRegionMetadata?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> String? {
        guard let visualChangeMetadata,
              visualChangeIsMeaningfulForWording(visualChangeMetadata) else {
            return existingReason
        }

        let seed = "\(visualChangeMetadata.regionID)-visual-change-reason"
        if let metadata,
           let label = safeSupportingLabel(from: metadata) {
            let target = visualChangeLabelPhrase(label, context: metadata.uiContext)
            if visualChangeMetadata.likelyLargeTransition {
                return stableChoice(seed: "\(seed)-label-large", from: [
                    "The page transition happens quickly and may benefit from guidance around \(target).",
                    "The larger screen change may be hard to follow without attention on \(target).",
                    "The change around \(target) may move too quickly."
                ])
            }
            if visualChangeMetadata.changeNearInteraction {
                return stableChoice(seed: "\(seed)-label-near", from: [
                    "The result around \(target) is easy to miss.",
                    "Viewers may need more time to understand what happens to \(target).",
                    "The result around \(target) may move past too quickly."
                ])
            }
        }

        if visualChangeMetadata.likelyLargeTransition {
            return stableChoice(seed: "\(seed)-large", from: [
                "The transition happens quickly and may benefit from additional visual guidance.",
                "The larger screen change may be hard to follow without emphasis.",
                "The screen change may move too quickly for viewers to stay oriented."
            ])
        }

        if visualChangeMetadata.changeNearInteraction {
            return stableChoice(seed: "\(seed)-near", from: [
                "The result of this interaction is easy to miss.",
                "Viewers may need more time to understand what changed.",
                "The interaction result may move past too quickly."
            ])
        }

        return existingReason
    }

    private func visualChangeIsMeaningfulForWording(_ metadata: SmartSuggestionVisualChangeMetadata) -> Bool {
        guard metadata.hasVisibleChange else { return false }
        guard metadata.changeNearInteraction || metadata.likelyLargeTransition else { return false }
        return metadata.changeScore >= 0.12 || metadata.changedAreaPercentage >= 0.025 || metadata.likelyLargeTransition
    }

    private func visualChangeLabelPhrase(_ label: String, context: SmartSuggestionUIContext) -> String {
        switch context {
        case .formEntry:
            return "the \(formFieldLabelPhrase(label)) field"
        case .settingsPanel:
            return label
        default:
            return label
        }
    }

    private func uiContextClassification(
        for region: ActivityRegion,
        observations: [SmartSuggestionOCRTextObservation],
        uniqueSnippets: [String],
        contentCoordinateSize: CGSize,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> (context: SmartSuggestionUIContext, confidence: Double, supportingText: String?, supportingTextRole: SmartSuggestionOCRTextRole, supportingTextRoleReason: String?) {
        guard !observations.isEmpty || !region.sourceEvents.isEmpty else {
            return (.unknown, 0, nil, .fallbackText, nil)
        }

        var scores: [SmartSuggestionUIContext: Double] = [:]
        var supportingTextByContext: [SmartSuggestionUIContext: String] = [:]
        let sourcePoints = normalizedSourcePoints(
            from: region.sourceEvents,
            contentCoordinateSize: contentCoordinateSize
        )
        let averageSourcePoint = averagePoint(sourcePoints)
        let roleSelection = ocrRoleSelection(
            in: observations,
            region: region,
            sourcePoints: sourcePoints,
            averageSourcePoint: averageSourcePoint,
            visualChangeMetadata: visualChangeMetadata
        )
        let nearbyText = roleSelection.text
        let possibleSidebarNavigation = roleSelection.isLikelySidebarNavigation
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

        if possibleSidebarNavigation {
            addScore(.sidebarInteraction, 0.74, supportingText: nearbyText)
        } else if let nearbyText {
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

        if changedText && !possibleSidebarNavigation {
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

        if observations.count >= 10 && !possibleSidebarNavigation {
            addScore(.contentEditing, 0.10, supportingText: uniqueSnippets.first)
        }
        if region.kind == .clickSequence && observations.count >= 3 && !possibleSidebarNavigation {
            addScore(.contentEditing, 0.08, supportingText: nearbyText ?? uniqueSnippets.first)
        }

        guard let best = scores
            .filter({ $0.key != .unknown })
            .sorted(by: contextScoreSort)
            .first else {
            return (.unknown, 0, roleSelection.text, roleSelection.role, roleSelection.reason)
        }

        let confidence = min(best.value, 0.92)
        guard confidence >= 0.42 else {
            return (.unknown, confidence, supportingTextByContext[best.key], roleSelection.role, roleSelection.reason)
        }

        return (best.key, confidence, supportingTextByContext[best.key], roleSelection.role, roleSelection.reason)
    }

    private struct OCRRoleSelection {
        let text: String?
        let role: SmartSuggestionOCRTextRole
        let reason: String?
        let isLikelySidebarNavigation: Bool
    }

    private func ocrRoleSelection(
        in observations: [SmartSuggestionOCRTextObservation],
        region: ActivityRegion,
        sourcePoints: [CGPoint],
        averageSourcePoint: CGPoint?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> OCRRoleSelection {
        let clickTarget = clickTargetObservation(in: observations, sourcePoints: sourcePoints, averageSourcePoint: averageSourcePoint)
        let nearbyContext = nearbyContextObservation(in: observations, sourcePoints: sourcePoints, averageSourcePoint: averageSourcePoint)
        let changedArea = changedAreaObservation(in: observations, visualChangeMetadata: visualChangeMetadata)
        let pageContent = pageContentObservation(in: observations, averageSourcePoint: averageSourcePoint)
        let sidebarNavigation = isLikelySidebarNavigation(
            region: region,
            averageSourcePoint: averageSourcePoint,
            clickTarget: clickTarget ?? nearbyContext,
            visualChangeMetadata: visualChangeMetadata
        )

        if sidebarNavigation {
            if let clickTarget {
                return OCRRoleSelection(
                    text: clickTarget.text,
                    role: .clickTargetText,
                    reason: nil,
                    isLikelySidebarNavigation: true
                )
            }
            if let nearbyContext, isSidebarSideObservation(nearbyContext, averageSourcePoint: averageSourcePoint) {
                return OCRRoleSelection(
                    text: nearbyContext.text,
                    role: .nearbyContextText,
                    reason: nil,
                    isLikelySidebarNavigation: true
                )
            }
            return OCRRoleSelection(
                text: nil,
                role: pageContent == nil ? .fallbackText : .pageContentText,
                reason: "pageContentText ignored because click looked like sidebar navigation",
                isLikelySidebarNavigation: true
            )
        }

        if let clickTarget {
            return OCRRoleSelection(text: clickTarget.text, role: .clickTargetText, reason: nil, isLikelySidebarNavigation: false)
        }
        if let nearbyContext {
            return OCRRoleSelection(text: nearbyContext.text, role: .nearbyContextText, reason: nil, isLikelySidebarNavigation: false)
        }
        if let changedArea {
            return OCRRoleSelection(text: changedArea.text, role: .changedAreaText, reason: nil, isLikelySidebarNavigation: false)
        }
        if let pageContent {
            return OCRRoleSelection(text: pageContent.text, role: .pageContentText, reason: nil, isLikelySidebarNavigation: false)
        }
        return OCRRoleSelection(text: observations.sorted(by: observationSort).first?.text, role: .fallbackText, reason: nil, isLikelySidebarNavigation: false)
    }

    private func clickTargetObservation(
        in observations: [SmartSuggestionOCRTextObservation],
        sourcePoints: [CGPoint],
        averageSourcePoint: CGPoint?
    ) -> SmartSuggestionOCRTextObservation? {
        guard !sourcePoints.isEmpty else { return nil }
        return observations
            .filter { observation in
                isSmallControlLikeObservation(observation)
                    && isSameSideObservation(observation, averageSourcePoint: averageSourcePoint)
                    && sourcePoints.contains { sourcePoint in
                        let textCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
                        return distance(from: sourcePoint, to: textCenter) <= 0.20
                            || observation.boundingBox.insetBy(dx: -0.055, dy: -0.055).contains(sourcePoint)
                    }
            }
            .sorted { lhs, rhs in
                nearestDistance(to: lhs, sourcePoints: sourcePoints) < nearestDistance(to: rhs, sourcePoints: sourcePoints)
            }
            .first
    }

    private func nearbyContextObservation(
        in observations: [SmartSuggestionOCRTextObservation],
        sourcePoints: [CGPoint],
        averageSourcePoint: CGPoint?
    ) -> SmartSuggestionOCRTextObservation? {
        guard !sourcePoints.isEmpty else { return nil }
        return observations
            .filter { observation in
                isSameSideObservation(observation, averageSourcePoint: averageSourcePoint)
                    && sourcePoints.contains { sourcePoint in
                        let textCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
                        return distance(from: sourcePoint, to: textCenter) <= nearbyTextDistance
                            || observation.boundingBox.insetBy(dx: -0.04, dy: -0.04).contains(sourcePoint)
                    }
            }
            .sorted { lhs, rhs in
                nearestDistance(to: lhs, sourcePoints: sourcePoints) < nearestDistance(to: rhs, sourcePoints: sourcePoints)
            }
            .first
    }

    private func changedAreaObservation(
        in observations: [SmartSuggestionOCRTextObservation],
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> SmartSuggestionOCRTextObservation? {
        guard let changedRegion = visualChangeMetadata?.changedRegion,
              !changedRegion.isEmpty else { return nil }
        let expandedRegion = changedRegion.insetBy(dx: -0.08, dy: -0.08)
        return observations
            .filter { expandedRegion.intersects($0.boundingBox) || expandedRegion.contains(CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY)) }
            .sorted(by: observationSort)
            .first
    }

    private func pageContentObservation(
        in observations: [SmartSuggestionOCRTextObservation],
        averageSourcePoint: CGPoint?
    ) -> SmartSuggestionOCRTextObservation? {
        observations
            .filter { observation in
                guard let averageSourcePoint else { return true }
                let center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
                return distance(from: averageSourcePoint, to: center) > 0.28
            }
            .sorted(by: observationSort)
            .first
    }

    private func isLikelySidebarNavigation(
        region: ActivityRegion,
        averageSourcePoint: CGPoint?,
        clickTarget: SmartSuggestionOCRTextObservation?,
        visualChangeMetadata: SmartSuggestionVisualChangeMetadata?
    ) -> Bool {
        guard region.kind == .click || region.kind == .clickSequence else { return false }
        guard let averageSourcePoint, averageSourcePoint.x <= 0.30 else { return false }
        let hasScreenChange = visualChangeMetadata?.likelyLargeTransition == true
            || (visualChangeMetadata?.changedAreaPercentage ?? 0) >= 0.10
            || visualChangeMetadata?.changeFarFromInteraction == true
        guard hasScreenChange else { return false }

        if let clickTarget {
            return isSidebarSideObservation(clickTarget, averageSourcePoint: averageSourcePoint)
        }
        return true
    }

    private func isSmallControlLikeObservation(_ observation: SmartSuggestionOCRTextObservation) -> Bool {
        let area = observation.boundingBox.width * observation.boundingBox.height
        return area <= 0.08 && observation.boundingBox.height <= 0.18 && observation.boundingBox.width <= 0.55
    }

    private func isSameSideObservation(
        _ observation: SmartSuggestionOCRTextObservation,
        averageSourcePoint: CGPoint?
    ) -> Bool {
        guard let averageSourcePoint else { return true }
        if averageSourcePoint.x <= 0.30 {
            return observation.boundingBox.midX <= 0.45
        }
        if averageSourcePoint.x >= 0.70 {
            return observation.boundingBox.midX >= 0.55
        }
        return true
    }

    private func isSidebarSideObservation(
        _ observation: SmartSuggestionOCRTextObservation,
        averageSourcePoint: CGPoint?
    ) -> Bool {
        guard let averageSourcePoint else { return false }
        return averageSourcePoint.x <= 0.30 && observation.boundingBox.midX <= 0.45
    }

    private func nearestDistance(
        to observation: SmartSuggestionOCRTextObservation,
        sourcePoints: [CGPoint]
    ) -> CGFloat {
        let center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
        return sourcePoints.map { distance(from: $0, to: center) }.min() ?? .greatestFiniteMagnitude
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
                "Viewers may need more time to follow what changes here.",
                "This moment is easy to miss at the current pace.",
                "The change may move past too quickly."
            ])
        }

        return stableChoice(seed: "\(metadata.regionID)-readable-content", from: [
            "The important content may need more time on screen.",
            "Viewers may lose orientation without a clearer focal point.",
            "Viewers may need more time with this part of the screen."
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
