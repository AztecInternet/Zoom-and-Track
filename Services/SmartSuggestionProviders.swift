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
