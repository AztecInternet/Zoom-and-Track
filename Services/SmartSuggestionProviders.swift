import CoreGraphics
import Foundation

struct SmartSuggestionContext {
    let events: [RecordedEvent]
    let duration: Double
    let contentCoordinateSize: CGSize
    let existingZoomMarkers: [ZoomPlanItem]
    let existingEffectMarkers: [EffectPlanItem]
}

protocol SmartSuggestionProvider {
    var providerID: String { get }

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion]
}

struct RuleSmartSuggestionProvider: SmartSuggestionProvider {
    let providerID = "rules"

    private let service: SmartSetupSuggestionService

    init(service: SmartSetupSuggestionService = SmartSetupSuggestionService()) {
        self.service = service
    }

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
        service.generateSuggestions(
            events: context.events,
            duration: context.duration,
            contentCoordinateSize: context.contentCoordinateSize,
            existingZoomMarkers: context.existingZoomMarkers,
            existingEffectMarkers: context.existingEffectMarkers
        )
        .map { suggestion in
            var markedSuggestion = suggestion
            markedSuggestion.providerID = providerID
            return markedSuggestion
        }
    }
}

struct TemplateSmartSuggestionProvider: SmartSuggestionProvider {
    let providerID = "templates"

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
        guard context.duration > 2.0,
              context.existingZoomMarkers.isEmpty,
              context.existingEffectMarkers.isEmpty else {
            return []
        }

        let safeContentSize = CGSize(
            width: max(context.contentCoordinateSize.width, 1),
            height: max(context.contentCoordinateSize.height, 1)
        )
        let sourceTime = min(max(context.duration * 0.15, 1.0), max(context.duration - 0.5, 1.0))
        let centerX = safeContentSize.width / 2
        let centerY = safeContentSize.height / 2
        let proposal = SmartSetupZoomMarkerProposal(
            sourceEventTimestamp: sourceTime,
            rawX: nil,
            rawY: nil,
            centerX: centerX,
            centerY: centerY,
            zoomScale: 1.5,
            leadInTime: 0.35,
            zoomInDuration: 0.45,
            holdDuration: 0.75,
            zoomOutDuration: 0.45,
            easeStyle: .smooth,
            zoomType: .inOut,
            bounceAmount: 0,
            clickPulse: nil,
            noZoomFallbackMode: .pan,
            noZoomOverflowRegion: nil
        )

        return [
            SmartSetupSuggestion(
                suggestionID: stableID(time: sourceTime, x: centerX, y: centerY),
                providerID: providerID,
                kind: .zoomMarker,
                sourceTimeRange: SmartSetupSourceTimeRange(
                    startTime: max(sourceTime - 0.5, 0),
                    endTime: min(sourceTime + 1.5, max(context.duration, sourceTime))
                ),
                sourceEvents: [
                    SmartSetupSourceEventReference(
                        type: .cursorMoved,
                        timestamp: sourceTime,
                        x: centerX,
                        y: centerY
                    )
                ],
                proposal: .zoom(proposal),
                score: SmartSetupCandidateScore(
                    value: 0.45,
                    components: [
                        SmartSetupScoreComponent(
                            reason: .timelineGap,
                            weight: 0.45,
                            detail: "This capture has no focus markers yet."
                        )
                    ]
                ),
                reasons: [.timelineGap]
            )
        ]
    }

    private func stableID(time: Double, x: Double, y: Double) -> String {
        let timeKey = Int((time * 100).rounded())
        let xKey = Int(x.rounded())
        let yKey = Int(y.rounded())
        return "template-first-focus-\(timeKey)-\(xKey)-\(yKey)"
    }
}

struct SmartSuggestionAggregator {
    let providers: [any SmartSuggestionProvider]

    init(providers: [any SmartSuggestionProvider]) {
        self.providers = providers
    }

    static func rulesOnly() -> SmartSuggestionAggregator {
        SmartSuggestionAggregator(providers: [RuleSmartSuggestionProvider()])
    }

    static func defaultAggregator() -> SmartSuggestionAggregator {
        SmartSuggestionAggregator(providers: [
            RuleSmartSuggestionProvider(),
            TemplateSmartSuggestionProvider()
        ])
    }

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
        var seenSuggestionIDs = Set<String>()
        var mergedSuggestions: [SmartSetupSuggestion] = []

        for provider in providers {
            for suggestion in provider.generateSuggestions(context: context) where !seenSuggestionIDs.contains(suggestion.suggestionID) {
                seenSuggestionIDs.insert(suggestion.suggestionID)
                mergedSuggestions.append(suggestion)
            }
        }

        return mergedSuggestions.sorted { lhs, rhs in
            let lhsTime = sortTime(for: lhs)
            let rhsTime = sortTime(for: rhs)
            if lhsTime != rhsTime {
                return lhsTime < rhsTime
            }
            return lhs.suggestionID < rhs.suggestionID
        }
    }

    private func sortTime(for suggestion: SmartSetupSuggestion) -> Double {
        suggestion.sourceTimeRange?.startTime ?? suggestion.sourceEvents.first?.timestamp ?? 0
    }
}
