import Foundation

struct SmartSetupSuggestionEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var source: String
    var generatedAt: Date
    var suggestions: [SmartSetupSuggestion]

    init(
        schemaVersion: Int = 1,
        source: String = "events.json",
        generatedAt: Date = Date(),
        suggestions: [SmartSetupSuggestion]
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.generatedAt = generatedAt
        self.suggestions = suggestions
    }
}

struct SmartSetupSuggestion: Codable, Equatable, Identifiable {
    var suggestionID: String
    var kind: SmartSetupSuggestionKind
    var sourceTimeRange: SmartSetupSourceTimeRange?
    var sourceEvents: [SmartSetupSourceEventReference]
    var proposal: SmartSetupMarkerProposal
    var score: SmartSetupCandidateScore
    var reasons: [SmartSetupSuggestionReason]

    var id: String { suggestionID }
}

enum SmartSetupSuggestionKind: String, Codable, CaseIterable {
    case zoomMarker
    case effectMarker
    case regionTighten
}

enum SmartSetupSuggestionReason: String, Codable, CaseIterable {
    case click
    case cursorPause
    case repeatedActivityZone
    case timelineGap
    case denseActivity
    case manualRegion
}

struct SmartSetupCandidateScore: Codable, Equatable {
    var value: Double
    var components: [SmartSetupScoreComponent]

    init(value: Double, components: [SmartSetupScoreComponent] = []) {
        self.value = min(max(value, 0), 1)
        self.components = components
    }
}

struct SmartSetupScoreComponent: Codable, Equatable {
    var reason: SmartSetupSuggestionReason
    var weight: Double
    var detail: String?
}

struct SmartSetupSourceTimeRange: Codable, Equatable {
    var startTime: Double
    var endTime: Double

    init(startTime: Double, endTime: Double) {
        self.startTime = min(startTime, endTime)
        self.endTime = max(startTime, endTime)
    }
}

struct SmartSetupSourceEventReference: Codable, Equatable {
    var type: RecordedEventType
    var timestamp: Double
    var x: Double
    var y: Double

    nonisolated init(event: RecordedEvent) {
        self.type = event.type
        self.timestamp = event.timestamp
        self.x = event.x
        self.y = event.y
    }

    nonisolated init(type: RecordedEventType, timestamp: Double, x: Double, y: Double) {
        self.type = type
        self.timestamp = timestamp
        self.x = x
        self.y = y
    }
}

enum SmartSetupMarkerProposal: Codable, Equatable {
    case zoom(SmartSetupZoomMarkerProposal)
    case zoomAdjustment(SmartSetupZoomMarkerAdjustmentProposal)
    case effect(SmartSetupEffectMarkerProposal)
    case regionTighten(SmartSetupRegionTightenProposal)
}

struct SmartSetupZoomMarkerAdjustmentProposal: Codable, Equatable {
    var targetMarkerIDs: [String]
    var startTime: Double
    var endTime: Double
    var suggestedFirstZoomType: ZoomType
    var suggestedMiddleZoomType: ZoomType
    var suggestedFinalZoomType: ZoomType
    var suggestedHoldDuration: Double?
    var markerCount: Int
}

struct SmartSetupZoomMarkerProposal: Codable, Equatable {
    var sourceEventTimestamp: Double
    var rawX: Double?
    var rawY: Double?
    var centerX: Double
    var centerY: Double
    var zoomScale: Double
    var leadInTime: Double
    var zoomInDuration: Double
    var holdDuration: Double
    var zoomOutDuration: Double
    var easeStyle: ZoomEaseStyle
    var zoomType: ZoomType
    var bounceAmount: Double
    var clickPulse: ClickPulseConfiguration?
    var noZoomFallbackMode: NoZoomFallbackMode
    var noZoomOverflowRegion: NoZoomOverflowRegion?
}

struct SmartSetupEffectMarkerProposal: Codable, Equatable {
    var sourceEventTimestamp: Double
    var startTime: Double
    var holdStartTime: Double
    var holdEndTime: Double
    var endTime: Double
    var style: EffectStyle
    var amount: Double
    var blurAmount: Double
    var darkenAmount: Double
    var tintAmount: Double
    var cornerRadius: Double
    var feather: Double
    var tintColor: EffectTintColor
    var focusRegion: EffectFocusRegion?
    var distortion: DistortionConfiguration?
}

struct SmartSetupRegionTightenProposal: Codable, Equatable {
    var sourceTime: Double
    var originalRegion: EffectFocusRegion
    var proposedRegion: EffectFocusRegion
    var confidence: Double

    init(
        sourceTime: Double,
        originalRegion: EffectFocusRegion,
        proposedRegion: EffectFocusRegion,
        confidence: Double
    ) {
        self.sourceTime = sourceTime
        self.originalRegion = originalRegion
        self.proposedRegion = proposedRegion
        self.confidence = min(max(confidence, 0), 1)
    }
}
