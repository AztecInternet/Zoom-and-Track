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
            markedSuggestion.userTitle = title(for: suggestion)
            markedSuggestion.userReason = "Rule-based focus opportunity detected"
            return markedSuggestion
        }
    }

    private func title(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return "Stay zoomed during this click sequence"
        case .effect:
            return "Review a possible focus effect"
        case .zoom, .regionTighten:
            return "Review a possible editing opportunity"
        }
    }
}

struct ClickClusterSmartSuggestionProvider: SmartSuggestionProvider {
    let providerID = "click-clusters"

    private let maxClusters = 5
    private let maxEmittedSuggestions = 8
    private let maximumTimeGap = 4.0
    private let maximumNormalizedDistance = 0.12
    private let existingZoomTimeTolerance = 0.65
    private let clusterLeadInTime = 0.35
    private let clusterZoomDuration = 0.35
    private let minimumClusterHold = 0.45
    private let finalClusterTail = 0.65

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
        guard context.duration > 2.0 else { return [] }

        let clickEvents = sortedClickEvents(from: context.events)
        guard clickEvents.count >= 2 else { return [] }

        let safeContentSize = CGSize(
            width: max(context.contentCoordinateSize.width, 1),
            height: max(context.contentCoordinateSize.height, 1)
        )
        let clusters = clickClusters(from: clickEvents, contentCoordinateSize: safeContentSize)
        var suggestions: [SmartSetupSuggestion] = []
        var acceptedClusterCount = 0

        for cluster in clusters where cluster.count >= 2 {
            guard !isCoveredByExistingZoomMarker(cluster, existingZoomMarkers: context.existingZoomMarkers) else {
                continue
            }

            let remainingSuggestionSlots = maxEmittedSuggestions - suggestions.count
            guard remainingSuggestionSlots >= 2 else { break }

            suggestions.append(contentsOf: clusterSuggestions(
                for: cluster,
                contentCoordinateSize: safeContentSize,
                duration: context.duration,
                limit: remainingSuggestionSlots
            ))
            acceptedClusterCount += 1

            if acceptedClusterCount >= maxClusters || suggestions.count >= maxEmittedSuggestions {
                break
            }
        }

        return suggestions
    }

    private func sortedClickEvents(from events: [RecordedEvent]) -> [RecordedEvent] {
        events
            .filter { event in
                event.type == .leftMouseDown || event.type == .rightMouseDown
            }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }
    }

    private func clickClusters(from events: [RecordedEvent], contentCoordinateSize: CGSize) -> [[RecordedEvent]] {
        var clusters: [[RecordedEvent]] = []
        var currentCluster: [RecordedEvent] = []

        func flushCurrentCluster() {
            if currentCluster.count >= 2 {
                clusters.append(currentCluster)
            }
            currentCluster = []
        }

        for event in events {
            guard let previous = currentCluster.last else {
                currentCluster = [event]
                continue
            }

            let timeGap = event.timestamp - previous.timestamp
            let distance = normalizedDistance(from: previous, to: event, contentCoordinateSize: contentCoordinateSize)
            if timeGap <= maximumTimeGap && distance <= maximumNormalizedDistance {
                currentCluster.append(event)
            } else {
                flushCurrentCluster()
                currentCluster = [event]
            }
        }

        flushCurrentCluster()
        return clusters
    }

    private func clusterSuggestions(for cluster: [RecordedEvent], contentCoordinateSize: CGSize, duration: Double, limit: Int) -> [SmartSetupSuggestion] {
        let selectedEvents = selectedEventsForSequence(from: cluster, limit: limit)
        return selectedEvents.enumerated().map { index, event in
            suggestion(
                for: event,
                at: index,
                sequenceCount: selectedEvents.count,
                in: cluster,
                contentCoordinateSize: contentCoordinateSize,
                duration: duration
            )
        }
    }

    private func selectedEventsForSequence(from cluster: [RecordedEvent], limit: Int) -> [RecordedEvent] {
        guard cluster.count > limit, limit >= 2, let first = cluster.first, let last = cluster.last else {
            return Array(cluster.prefix(limit))
        }

        let middleLimit = max(limit - 2, 0)
        let middleEvents = cluster.dropFirst().dropLast().prefix(middleLimit)
        return [first] + middleEvents + [last]
    }

    private func suggestion(
        for event: RecordedEvent,
        at index: Int,
        sequenceCount: Int,
        in cluster: [RecordedEvent],
        contentCoordinateSize: CGSize,
        duration: Double
    ) -> SmartSetupSuggestion {
        let point = clampedContentPoint(for: event, contentCoordinateSize: contentCoordinateSize)
        let zoomType = zoomType(for: index, count: sequenceCount)
        let timing = markerTiming(
            for: event,
            at: index,
            sequenceCount: sequenceCount,
            in: cluster,
            duration: duration
        )
        let proposal = SmartSetupZoomMarkerProposal(
            sourceEventTimestamp: event.timestamp,
            rawX: event.x,
            rawY: event.y,
            centerX: point.x,
            centerY: point.y,
            zoomScale: 1.55,
            leadInTime: timing.leadInTime,
            zoomInDuration: timing.zoomInDuration,
            holdDuration: timing.holdDuration,
            zoomOutDuration: timing.zoomOutDuration,
            easeStyle: .smooth,
            zoomType: zoomType,
            bounceAmount: 0,
            clickPulse: nil,
            noZoomFallbackMode: .pan,
            noZoomOverflowRegion: nil
        )

        return SmartSetupSuggestion(
            suggestionID: stableID(for: event, at: index, in: cluster, point: point),
            providerID: providerID,
            userTitle: "Review a \(cluster.count)-click focus sequence",
            userReason: "\(cluster.count) nearby clicks detected",
            kind: .zoomMarker,
            sourceTimeRange: SmartSetupSourceTimeRange(
                startTime: timing.startTime,
                endTime: timing.endTime
            ),
            sourceEvents: cluster.map(SmartSetupSourceEventReference.init(event:)),
            proposal: .zoom(proposal),
            score: SmartSetupCandidateScore(
                value: min(0.86, 0.64 + (Double(cluster.count) * 0.04)),
                components: [
                    SmartSetupScoreComponent(
                        reason: .click,
                        weight: 0.55,
                        detail: "Several nearby clicks can be treated as one focus sequence."
                    ),
                    SmartSetupScoreComponent(
                        reason: .denseActivity,
                        weight: 0.25,
                        detail: "\(cluster.count) nearby clicks were recorded."
                    )
                ]
            ),
            reasons: [.click, .denseActivity]
        )
    }

    private func markerTiming(
        for event: RecordedEvent,
        at index: Int,
        sequenceCount: Int,
        in cluster: [RecordedEvent],
        duration: Double
    ) -> (leadInTime: Double, zoomInDuration: Double, holdDuration: Double, zoomOutDuration: Double, startTime: Double, endTime: Double) {
        let zoomType = zoomType(for: index, count: sequenceCount)
        let nextTimestamp = nextClusterTimestamp(after: event, in: cluster)
        let previousTimestamp = previousClusterTimestamp(before: event, in: cluster)

        switch zoomType {
        case .inOnly:
            let holdUntil = min(nextTimestamp ?? event.timestamp + minimumClusterHold, duration)
            let holdDuration = max(holdUntil - event.timestamp, minimumClusterHold)
            return timing(
                eventTimestamp: event.timestamp,
                leadInTime: min(clusterLeadInTime, event.timestamp),
                zoomInDuration: clusterZoomDuration,
                holdDuration: holdDuration,
                zoomOutDuration: 0,
                duration: duration
            )
        case .noZoom:
            let previousGap = previousTimestamp.map { max(event.timestamp - $0, 0) } ?? minimumClusterHold
            let nextGap = nextTimestamp.map { max($0 - event.timestamp, 0) } ?? minimumClusterHold
            let localWindow = min(previousGap, nextGap, 1.0)
            return timing(
                eventTimestamp: event.timestamp,
                leadInTime: min(0.10, event.timestamp),
                zoomInDuration: 0,
                holdDuration: max(minimumClusterHold, localWindow),
                zoomOutDuration: 0,
                duration: duration
            )
        case .outOnly:
            return timing(
                eventTimestamp: event.timestamp,
                leadInTime: 0,
                zoomInDuration: 0,
                holdDuration: finalClusterTail,
                zoomOutDuration: clusterZoomDuration,
                duration: duration
            )
        case .inOut:
            return timing(
                eventTimestamp: event.timestamp,
                leadInTime: min(clusterLeadInTime, event.timestamp),
                zoomInDuration: clusterZoomDuration,
                holdDuration: minimumClusterHold,
                zoomOutDuration: clusterZoomDuration,
                duration: duration
            )
        }
    }

    private func timing(
        eventTimestamp: Double,
        leadInTime: Double,
        zoomInDuration: Double,
        holdDuration: Double,
        zoomOutDuration: Double,
        duration: Double
    ) -> (leadInTime: Double, zoomInDuration: Double, holdDuration: Double, zoomOutDuration: Double, startTime: Double, endTime: Double) {
        let timelineEnd = max(duration, 0)
        let safeEventTimestamp = min(max(eventTimestamp, 0), timelineEnd)
        let safeLeadIn = max(min(leadInTime, safeEventTimestamp), 0)
        let safeZoomInDuration = max(zoomInDuration, 0)
        let requestedZoomOutDuration = max(zoomOutDuration, 0)
        let requestedHoldDuration = max(holdDuration, minimumClusterHold)
        let availableAfterEvent = max(timelineEnd - safeEventTimestamp, 0)
        let safeHoldDuration = min(requestedHoldDuration, availableAfterEvent)
        let safeZoomOutDuration = min(requestedZoomOutDuration, max(availableAfterEvent - safeHoldDuration, 0))
        let endTime = safeEventTimestamp + safeHoldDuration + safeZoomOutDuration
        return (
            leadInTime: safeLeadIn,
            zoomInDuration: safeZoomInDuration,
            holdDuration: safeHoldDuration,
            zoomOutDuration: safeZoomOutDuration,
            startTime: max(safeEventTimestamp - safeLeadIn, 0),
            endTime: endTime
        )
    }

    private func zoomType(for index: Int, count: Int) -> ZoomType {
        if index == 0 {
            return .inOnly
        }
        if index == count - 1 {
            return .outOnly
        }
        return .noZoom
    }

    private func previousClusterTimestamp(before event: RecordedEvent, in cluster: [RecordedEvent]) -> Double? {
        cluster.last { candidate in
            candidate.timestamp < event.timestamp
        }?.timestamp
    }

    private func nextClusterTimestamp(after event: RecordedEvent, in cluster: [RecordedEvent]) -> Double? {
        cluster.first { candidate in
            candidate.timestamp > event.timestamp
        }?.timestamp
    }

    private func isCoveredByExistingZoomMarker(_ cluster: [RecordedEvent], existingZoomMarkers: [ZoomPlanItem]) -> Bool {
        guard let first = cluster.first, let last = cluster.last else { return false }
        let startTime = first.timestamp - existingZoomTimeTolerance
        let endTime = last.timestamp + existingZoomTimeTolerance
        return existingZoomMarkers.contains { marker in
            marker.shouldSuppressClickSmartSuggestion
                && marker.sourceEventTimestamp >= startTime
                && marker.sourceEventTimestamp <= endTime
        }
    }

    private func averagePoint(for events: [RecordedEvent], contentCoordinateSize: CGSize) -> CGPoint {
        guard !events.isEmpty else { return .zero }
        let total = events.reduce(CGPoint.zero) { partialResult, event in
            let point = clampedContentPoint(for: event, contentCoordinateSize: contentCoordinateSize)
            return CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(events.count), y: total.y / CGFloat(events.count))
    }

    private func normalizedDistance(from lhs: RecordedEvent, to rhs: RecordedEvent, contentCoordinateSize: CGSize) -> Double {
        let lhsPoint = normalizedPoint(clampedContentPoint(for: lhs, contentCoordinateSize: contentCoordinateSize), contentCoordinateSize: contentCoordinateSize)
        let rhsPoint = normalizedPoint(clampedContentPoint(for: rhs, contentCoordinateSize: contentCoordinateSize), contentCoordinateSize: contentCoordinateSize)
        let deltaX = lhsPoint.x - rhsPoint.x
        let deltaY = lhsPoint.y - rhsPoint.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    private func clampedContentPoint(for event: RecordedEvent, contentCoordinateSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(event.x, 0), contentCoordinateSize.width),
            y: min(max(event.y, 0), contentCoordinateSize.height)
        )
    }

    private func normalizedPoint(_ point: CGPoint, contentCoordinateSize: CGSize) -> (x: Double, y: Double) {
        let x = Double(min(max(point.x / max(contentCoordinateSize.width, 1), 0), 1))
        let y = Double(min(max(point.y / max(contentCoordinateSize.height, 1), 0), 1))
        return (x, y)
    }

    private func stableID(for event: RecordedEvent, at index: Int, in cluster: [RecordedEvent], point: CGPoint) -> String {
        let firstTimeKey = Int(((cluster.first?.timestamp ?? 0) * 100).rounded())
        let lastTimeKey = Int(((cluster.last?.timestamp ?? 0) * 100).rounded())
        let eventTimeKey = Int((event.timestamp * 100).rounded())
        let xKey = Int(point.x.rounded())
        let yKey = Int(point.y.rounded())
        return "click-cluster-\(firstTimeKey)-\(lastTimeKey)-\(cluster.count)-\(index)-\(eventTimeKey)-\(xKey)-\(yKey)"
    }
}

struct ClickHeuristicSmartSuggestionProvider: SmartSuggestionProvider {
    let providerID = "clicks"

    private let maxCandidateSuggestions = 12
    private let existingZoomTimeTolerance = 0.65
    private let emittedSuggestionTimeTolerance = 0.65

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
        guard context.duration > 2.0 else { return [] }

        let clickEvents = context.events
            .filter { event in
                event.type == .leftMouseDown || event.type == .rightMouseDown
            }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }

        guard !clickEvents.isEmpty else { return [] }

        let safeContentSize = CGSize(
            width: max(context.contentCoordinateSize.width, 1),
            height: max(context.contentCoordinateSize.height, 1)
        )
        var suggestions: [SmartSetupSuggestion] = []

        for event in clickEvents {
            guard !hasNearbyZoomMarker(at: event.timestamp, existingZoomMarkers: context.existingZoomMarkers),
                  !hasNearbySuggestion(at: event.timestamp, suggestions: suggestions) else {
                continue
            }

            suggestions.append(suggestion(for: event, contentCoordinateSize: safeContentSize, duration: context.duration))

            if suggestions.count >= maxCandidateSuggestions {
                break
            }
        }

        return suggestions
    }

    private func suggestion(for event: RecordedEvent, contentCoordinateSize: CGSize, duration: Double) -> SmartSetupSuggestion {
        let point = clampedContentPoint(for: event, contentCoordinateSize: contentCoordinateSize)
        let proposal = SmartSetupZoomMarkerProposal(
            sourceEventTimestamp: event.timestamp,
            rawX: event.x,
            rawY: event.y,
            centerX: point.x,
            centerY: point.y,
            zoomScale: 1.6,
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

        return SmartSetupSuggestion(
            suggestionID: stableID(for: event, point: point),
            providerID: providerID,
            userTitle: "Focus on this click",
            userReason: "Mouse click detected",
            kind: .zoomMarker,
            sourceTimeRange: SmartSetupSourceTimeRange(
                startTime: max(event.timestamp - 0.35, 0),
                endTime: min(event.timestamp + 1.65, max(duration, event.timestamp))
            ),
            sourceEvents: [SmartSetupSourceEventReference(event: event)],
            proposal: .zoom(proposal),
            score: SmartSetupCandidateScore(
                value: 0.74,
                components: [
                    SmartSetupScoreComponent(
                        reason: .click,
                        weight: 0.74,
                        detail: "A recorded click can be a useful focus point."
                    )
                ]
            ),
            reasons: [.click]
        )
    }

    private func hasNearbyZoomMarker(at time: Double, existingZoomMarkers: [ZoomPlanItem]) -> Bool {
        existingZoomMarkers.contains { marker in
            marker.shouldSuppressClickSmartSuggestion
                && abs(marker.sourceEventTimestamp - time) <= existingZoomTimeTolerance
        }
    }

    private func hasNearbySuggestion(at time: Double, suggestions: [SmartSetupSuggestion]) -> Bool {
        suggestions.contains { suggestion in
            let suggestionTime = suggestion.sourceTimeRange?.startTime ?? suggestion.sourceEvents.first?.timestamp ?? 0
            return abs(suggestionTime - time) <= emittedSuggestionTimeTolerance
        }
    }

    private func clampedContentPoint(for event: RecordedEvent, contentCoordinateSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(event.x, 0), contentCoordinateSize.width),
            y: min(max(event.y, 0), contentCoordinateSize.height)
        )
    }

    private func stableID(for event: RecordedEvent, point: CGPoint) -> String {
        let timeKey = Int((event.timestamp * 100).rounded())
        let xKey = Int(point.x.rounded())
        let yKey = Int(point.y.rounded())
        return "click-focus-\(timeKey)-\(xKey)-\(yKey)"
    }
}

private extension ZoomPlanItem {
    var shouldSuppressClickSmartSuggestion: Bool {
        markerNameSource == .manual
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
                userTitle: "Starter focus suggestion",
                userReason: "Fallback starter suggestion",
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

    private let zoomTimeConflictTolerance = 0.65
    private let effectTimeConflictTolerance = 0.80
    private let substantialOverlapRatio = 0.50
    private let maxVisibleClickSuggestions = 5

    init(providers: [any SmartSuggestionProvider]) {
        self.providers = providers
    }

    static func rulesOnly() -> SmartSuggestionAggregator {
        SmartSuggestionAggregator(providers: [RuleSmartSuggestionProvider()])
    }

    static func defaultAggregator() -> SmartSuggestionAggregator {
        SmartSuggestionAggregator(providers: [
            RuleSmartSuggestionProvider(),
            ClickClusterSmartSuggestionProvider(),
            ClickHeuristicSmartSuggestionProvider(),
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

        let conflictFilteredSuggestions = conflictFilteredSuggestions(from: mergedSuggestions)
        let providerCappedSuggestions = providerCappedSuggestions(from: conflictFilteredSuggestions)

        return scoreTunedSuggestions(from: providerCappedSuggestions).sorted { lhs, rhs in
            if lhs.score.value != rhs.score.value {
                return lhs.score.value > rhs.score.value
            }
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

    private func scoreTunedSuggestions(from suggestions: [SmartSetupSuggestion]) -> [SmartSetupSuggestion] {
        suggestions.map { suggestion in
            var tunedSuggestion = suggestion
            tunedSuggestion.score = SmartSetupCandidateScore(
                value: tunedScoreValue(for: suggestion),
                components: suggestion.score.components
            )
            return tunedSuggestion
        }
    }

    private func providerCappedSuggestions(from suggestions: [SmartSetupSuggestion]) -> [SmartSetupSuggestion] {
        var visibleClickSuggestionCount = 0
        return suggestions.filter { suggestion in
            guard suggestion.providerID == "clicks" else {
                return true
            }

            guard visibleClickSuggestionCount < maxVisibleClickSuggestions else {
                return false
            }
            visibleClickSuggestionCount += 1
            return true
        }
    }

    private func tunedScoreValue(for suggestion: SmartSetupSuggestion) -> Double {
        switch suggestion.providerID {
        case "click-clusters":
            return max(suggestion.score.value, 0.88)
        case "clicks":
            return max(suggestion.score.value, 0.78)
        case "templates":
            return min(max(suggestion.score.value, 0.55), 0.65)
        default:
            return suggestion.score.value
        }
    }

    private func conflictFilteredSuggestions(from suggestions: [SmartSetupSuggestion]) -> [SmartSetupSuggestion] {
        var acceptedSuggestions: [SmartSetupSuggestion] = []

        for suggestion in suggestions {
            guard !acceptedSuggestions.contains(where: { conflicts($0, with: suggestion) }) else {
                continue
            }
            acceptedSuggestions.append(suggestion)
        }

        return acceptedSuggestions
    }

    private func conflicts(_ acceptedSuggestion: SmartSetupSuggestion, with candidate: SmartSetupSuggestion) -> Bool {
        guard acceptedSuggestion.providerID != candidate.providerID else {
            return false
        }

        switch (acceptedSuggestion.kind, candidate.kind) {
        case (.zoomMarker, .zoomMarker):
            return zoomSuggestionsConflict(acceptedSuggestion, candidate)
        case (.effectMarker, .effectMarker):
            return effectSuggestionsConflict(acceptedSuggestion, candidate)
        default:
            return false
        }
    }

    private func zoomSuggestionsConflict(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        if abs(sortTime(for: lhs) - sortTime(for: rhs)) <= zoomTimeConflictTolerance {
            return true
        }
        return rangesOverlapSubstantially(lhs.sourceTimeRange, rhs.sourceTimeRange)
    }

    private func effectSuggestionsConflict(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        if abs(sortTime(for: lhs) - sortTime(for: rhs)) <= effectTimeConflictTolerance {
            return true
        }
        return rangesOverlapSubstantially(lhs.sourceTimeRange, rhs.sourceTimeRange)
    }

    private func rangesOverlapSubstantially(_ lhs: SmartSetupSourceTimeRange?, _ rhs: SmartSetupSourceTimeRange?) -> Bool {
        guard let lhs, let rhs else { return false }

        let overlapStart = max(lhs.startTime, rhs.startTime)
        let overlapEnd = min(lhs.endTime, rhs.endTime)
        let overlapDuration = max(overlapEnd - overlapStart, 0)
        guard overlapDuration > 0 else { return false }

        let lhsDuration = max(lhs.endTime - lhs.startTime, 0.001)
        let rhsDuration = max(rhs.endTime - rhs.startTime, 0.001)
        return overlapDuration / min(lhsDuration, rhsDuration) >= substantialOverlapRatio
    }
}
