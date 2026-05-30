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
            markedSuggestion.userReason = reason(for: suggestion)
            return markedSuggestion
        }
    }

    private func title(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return suggestion.stableChoice(from: [
                "Keep this interaction in focus",
                "Smooth out this focus sequence",
                "Hold attention on this area"
            ])
        case .effect:
            return suggestion.stableChoice(from: [
                "Soften the surroundings here",
                "Guide attention to this moment",
                "Consider a subtle focus effect"
            ])
        case .zoom, .regionTighten:
            return suggestion.stableChoice(from: [
                "Review this editing moment",
                "This part may be worth highlighting",
                "Check this moment for emphasis"
            ])
        }
    }

    private func reason(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return suggestion.stableChoice(from: [
                "Several actions happened close together here.",
                "The viewer may benefit from one steadier focus move.",
                "This looks like one interaction that should stay in view."
            ])
        case .effect:
            return suggestion.stableChoice(from: [
                "You spent a moment working in this area.",
                "Activity was concentrated around this part of the screen.",
                "This moment may read more clearly with gentle emphasis."
            ])
        case .zoom, .regionTighten:
            return suggestion.stableChoice(from: [
                "This looks like a useful moment to review.",
                "The viewer may benefit from seeing this more clearly.",
                "This part may deserve a little more attention."
            ])
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
            userTitle: clusterTitle(for: cluster, event: event),
            userReason: clusterReason(for: cluster, event: event),
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

    private func clusterTitle(for cluster: [RecordedEvent], event: RecordedEvent) -> String {
        stableSuggestionChoice(seed: "\(providerID)-title-\(cluster.count)-\(event.timestamp)", from: [
            "Keep these \(cluster.count) actions in view",
            "Focus this \(cluster.count)-step interaction",
            "Hold attention through these \(cluster.count) actions"
        ])
    }

    private func clusterReason(for cluster: [RecordedEvent], event: RecordedEvent) -> String {
        stableSuggestionChoice(seed: "\(providerID)-reason-\(cluster.count)-\(event.timestamp)", from: [
            "Several actions happened close together here.",
            "This looks like one short interaction worth highlighting.",
            "The viewer may benefit from following this area without extra movement."
        ])
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
            userTitle: stableSuggestionChoice(seed: "\(providerID)-title-\(event.timestamp)", from: [
                "Highlight this click",
                "Focus on this interaction",
                "Review this quick action"
            ]),
            userReason: stableSuggestionChoice(seed: "\(providerID)-reason-\(event.timestamp)", from: [
                "This looks like a useful click to highlight.",
                "The viewer may benefit from seeing this action clearly.",
                "This moment may be worth a little extra focus."
            ]),
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
                userTitle: stableSuggestionChoice(seed: "\(providerID)-title-\(sourceTime)", from: [
                    "Start with a simple focus point",
                    "Try a first focus moment",
                    "Add a gentle opening highlight"
                ]),
                userReason: stableSuggestionChoice(seed: "\(providerID)-reason-\(sourceTime)", from: [
                    "This capture does not have focus edits yet.",
                    "A single starter focus can make the edit easier to review.",
                    "This gives you one simple place to begin refining the capture."
                ]),
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
    private let maxVisibleClickSuggestions = 4
    private let maxVisibleSuggestions = 8
    private let maxVisibleCursorPauseSuggestions = 2
    private let repeatedPauseTimeSpacing = 8.0
    private let opportunityTimeTolerance = 1.0
    private let opportunityDistanceTolerance = 0.12
    private let finalOpportunityTimeTolerance = 2.5
    private let finalOpportunityDistanceTolerance = 0.16

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
        let opportunityGroupedSuggestions = opportunityGroupedSuggestions(
            from: conflictFilteredSuggestions,
            context: context
        )
        let providerCappedSuggestions = providerCappedSuggestions(from: opportunityGroupedSuggestions)
        let tunedSuggestions = scoreTunedSuggestions(from: providerCappedSuggestions)
        let curatedSuggestions = finalOpportunityCompetitionSuggestions(
            from: tunedSuggestions,
            contentCoordinateSize: context.contentCoordinateSize
        )

        let sortedSuggestions = curatedSuggestions.sorted { lhs, rhs in
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

        return Array(sortedSuggestions.prefix(maxVisibleSuggestions))
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

    private func opportunityGroupedSuggestions(
        from suggestions: [SmartSetupSuggestion],
        context: SmartSuggestionContext
    ) -> [SmartSetupSuggestion] {
        let sequenceMergedSuggestions = clickClusterOpportunityMergedSuggestions(from: suggestions)
        let crossProviderGroupedSuggestions = crossProviderOpportunityGroupedSuggestions(
            from: sequenceMergedSuggestions,
            contentCoordinateSize: context.contentCoordinateSize
        )
        return repeatedPauseReducedSuggestions(from: crossProviderGroupedSuggestions)
    }

    private func clickClusterOpportunityMergedSuggestions(from suggestions: [SmartSetupSuggestion]) -> [SmartSetupSuggestion] {
        let clusterGroups = Dictionary(grouping: suggestions.filter { $0.providerID == "click-clusters" }) {
            clickClusterOpportunityKey(for: $0)
        }
        var mergedClusterSuggestions: [String: SmartSetupSuggestion] = [:]

        for (key, group) in clusterGroups {
            guard group.count > 1 else {
                if let suggestion = group.first {
                    mergedClusterSuggestions[suggestion.suggestionID] = suggestion
                }
                continue
            }

            let orderedGroup = group.sorted {
                if sortTime(for: $0) != sortTime(for: $1) {
                    return sortTime(for: $0) < sortTime(for: $1)
                }
                return $0.suggestionID < $1.suggestionID
            }
            guard var representative = orderedGroup.first else { continue }
            let uniqueSourceEvents = uniqueSourceEvents(from: orderedGroup.flatMap(\.sourceEvents))
            let eventCount = max(uniqueSourceEvents.count, representative.sourceEvents.count)
            representative.sourceEvents = uniqueSourceEvents
            representative.sourceTimeRange = combinedSourceTimeRange(for: orderedGroup)
            representative.score = highestScore(in: orderedGroup)
            representative.userTitle = stableSuggestionChoice(seed: "click-cluster-opportunity-title-\(key)", from: [
                "Review this \(eventCount)-step interaction",
                "Keep this \(eventCount)-step interaction in view",
                "Focus this short interaction"
            ])
            representative.userReason = stableSuggestionChoice(seed: "click-cluster-opportunity-reason-\(key)", from: [
                "Several actions happened close together here.",
                "This looks like one interaction the viewer may need to follow.",
                "Keeping this area in focus may make the sequence easier to understand."
            ])
            mergedClusterSuggestions[representative.suggestionID] = representative
        }

        return suggestions.compactMap { suggestion in
            guard suggestion.providerID == "click-clusters" else {
                return suggestion
            }
            return mergedClusterSuggestions.removeValue(forKey: suggestion.suggestionID)
        }
    }

    private func crossProviderOpportunityGroupedSuggestions(
        from suggestions: [SmartSetupSuggestion],
        contentCoordinateSize: CGSize
    ) -> [SmartSetupSuggestion] {
        var acceptedSuggestionIDs = Set<String>()
        let rankedSuggestions = suggestions.sorted { lhs, rhs in
            let lhsValue = opportunityValue(for: lhs)
            let rhsValue = opportunityValue(for: rhs)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            if sortTime(for: lhs) != sortTime(for: rhs) {
                return sortTime(for: lhs) < sortTime(for: rhs)
            }
            return lhs.suggestionID < rhs.suggestionID
        }

        var acceptedSuggestions: [SmartSetupSuggestion] = []
        for suggestion in rankedSuggestions {
            guard !acceptedSuggestions.contains(where: {
                representsSameOpportunity($0, suggestion, contentCoordinateSize: contentCoordinateSize)
            }) else {
                continue
            }
            acceptedSuggestions.append(suggestion)
            acceptedSuggestionIDs.insert(suggestion.suggestionID)
        }

        return suggestions.filter { acceptedSuggestionIDs.contains($0.suggestionID) }
    }

    private func repeatedPauseReducedSuggestions(from suggestions: [SmartSetupSuggestion]) -> [SmartSetupSuggestion] {
        let pauseSuggestions = suggestions
            .filter(isCursorPauseSuggestion)
            .sorted { lhs, rhs in
                let lhsValue = tunedScoreValue(for: lhs)
                let rhsValue = tunedScoreValue(for: rhs)
                if lhsValue != rhsValue {
                    return lhsValue > rhsValue
                }
                if sortTime(for: lhs) != sortTime(for: rhs) {
                    return sortTime(for: lhs) < sortTime(for: rhs)
                }
                return lhs.suggestionID < rhs.suggestionID
            }

        var keptPauseSuggestions: [SmartSetupSuggestion] = []
        for suggestion in pauseSuggestions {
            guard keptPauseSuggestions.count < maxVisibleCursorPauseSuggestions else { break }
            guard !keptPauseSuggestions.contains(where: {
                abs(sortTime(for: $0) - sortTime(for: suggestion)) < repeatedPauseTimeSpacing
            }) else {
                continue
            }
            keptPauseSuggestions.append(suggestion)
        }

        let keptPauseSuggestionIDs = Set(keptPauseSuggestions.map(\.suggestionID))
        return suggestions.filter { suggestion in
            !isCursorPauseSuggestion(suggestion) || keptPauseSuggestionIDs.contains(suggestion.suggestionID)
        }
    }

    private func finalOpportunityCompetitionSuggestions(
        from suggestions: [SmartSetupSuggestion],
        contentCoordinateSize: CGSize
    ) -> [SmartSetupSuggestion] {
        let rankedSuggestions = suggestions.sorted { lhs, rhs in
            let lhsValue = opportunityValue(for: lhs)
            let rhsValue = opportunityValue(for: rhs)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            if sortTime(for: lhs) != sortTime(for: rhs) {
                return sortTime(for: lhs) < sortTime(for: rhs)
            }
            return lhs.suggestionID < rhs.suggestionID
        }

        var acceptedSuggestions: [SmartSetupSuggestion] = []
        for suggestion in rankedSuggestions {
            guard !acceptedSuggestions.contains(where: {
                competesAsSimilarVisibleOpportunity($0, suggestion, contentCoordinateSize: contentCoordinateSize)
            }) else {
                continue
            }
            acceptedSuggestions.append(suggestion)
        }

        let acceptedSuggestionIDs = Set(acceptedSuggestions.map(\.suggestionID))
        return suggestions.filter { acceptedSuggestionIDs.contains($0.suggestionID) }
    }

    private func competesAsSimilarVisibleOpportunity(
        _ acceptedSuggestion: SmartSetupSuggestion,
        _ candidate: SmartSetupSuggestion,
        contentCoordinateSize: CGSize
    ) -> Bool {
        guard acceptedSuggestion.suggestionID != candidate.suggestionID else { return true }
        guard visibleOpportunityCategory(for: acceptedSuggestion) == visibleOpportunityCategory(for: candidate) else {
            return false
        }
        guard visibleOpportunityTimesCompete(acceptedSuggestion, candidate) else { return false }

        guard let acceptedPoint = normalizedOpportunityPoint(for: acceptedSuggestion, contentCoordinateSize: contentCoordinateSize),
              let candidatePoint = normalizedOpportunityPoint(for: candidate, contentCoordinateSize: contentCoordinateSize) else {
            return true
        }

        let deltaX = acceptedPoint.x - candidatePoint.x
        let deltaY = acceptedPoint.y - candidatePoint.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot() <= finalOpportunityDistanceTolerance
    }

    private func visibleOpportunityTimesCompete(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        if abs(sortTime(for: lhs) - sortTime(for: rhs)) <= finalOpportunityTimeTolerance {
            return true
        }
        return rangesOverlapSubstantially(lhs.sourceTimeRange, rhs.sourceTimeRange)
    }

    private func visibleOpportunityCategory(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return "focus-sequence"
        case .zoom:
            if suggestion.providerID == "click-clusters" {
                return "focus-sequence"
            }
            return "interaction-highlight"
        case .effect:
            return suggestion.reasons.contains(.cursorPause) ? "focus-pause" : "focus-effect"
        case .regionTighten:
            return "focus-area"
        }
    }

    private func tunedScoreValue(for suggestion: SmartSetupSuggestion) -> Double {
        switch suggestion.providerID {
        case "click-clusters":
            return max(suggestion.score.value, min(0.94, 0.86 + (Double(suggestion.sourceEvents.count) * 0.015)))
        case "clicks":
            return max(suggestion.score.value, 0.76)
        case "templates":
            return min(max(suggestion.score.value, 0.55), 0.60)
        default:
            return suggestion.score.value
        }
    }

    private func opportunityValue(for suggestion: SmartSetupSuggestion) -> Double {
        tunedScoreValue(for: suggestion) + opportunityPriorityBoost(for: suggestion)
    }

    private func opportunityPriorityBoost(for suggestion: SmartSetupSuggestion) -> Double {
        switch suggestion.providerID {
        case "click-clusters":
            return 0.10
        case "clicks":
            return 0.02
        case "rules":
            if case .zoomAdjustment = suggestion.proposal {
                return 0.04
            }
            return 0
        case "templates":
            return -0.10
        default:
            return 0
        }
    }

    private func clickClusterOpportunityKey(for suggestion: SmartSetupSuggestion) -> String {
        let eventKeys = suggestion.sourceEvents
            .sorted {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp < $1.timestamp
                }
                return $0.type.rawValue < $1.type.rawValue
            }
            .map { event in
                let timeKey = Int((event.timestamp * 100).rounded())
                let xKey = Int(event.x.rounded())
                let yKey = Int(event.y.rounded())
                return "\(event.type.rawValue)-\(timeKey)-\(xKey)-\(yKey)"
            }
        return eventKeys.joined(separator: "|")
    }

    private func uniqueSourceEvents(from events: [SmartSetupSourceEventReference]) -> [SmartSetupSourceEventReference] {
        var seenEventKeys = Set<String>()
        return events
            .sorted {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp < $1.timestamp
                }
                return $0.type.rawValue < $1.type.rawValue
            }
            .filter { event in
                let eventKey = "\(event.type.rawValue)-\(Int((event.timestamp * 1000).rounded()))-\(Int(event.x.rounded()))-\(Int(event.y.rounded()))"
                guard !seenEventKeys.contains(eventKey) else { return false }
                seenEventKeys.insert(eventKey)
                return true
            }
    }

    private func combinedSourceTimeRange(for suggestions: [SmartSetupSuggestion]) -> SmartSetupSourceTimeRange? {
        let ranges = suggestions.compactMap(\.sourceTimeRange)
        if !ranges.isEmpty {
            let startTime = ranges.map(\.startTime).min() ?? 0
            let endTime = ranges.map(\.endTime).max() ?? startTime
            return SmartSetupSourceTimeRange(startTime: startTime, endTime: endTime)
        }

        let eventTimes = suggestions.flatMap(\.sourceEvents).map(\.timestamp)
        guard let startTime = eventTimes.min(), let endTime = eventTimes.max() else {
            return nil
        }
        return SmartSetupSourceTimeRange(startTime: startTime, endTime: endTime)
    }

    private func highestScore(in suggestions: [SmartSetupSuggestion]) -> SmartSetupCandidateScore {
        suggestions.max {
            if $0.score.value != $1.score.value {
                return $0.score.value < $1.score.value
            }
            return $0.suggestionID > $1.suggestionID
        }?.score ?? SmartSetupCandidateScore(value: 0)
    }

    private func representsSameOpportunity(
        _ lhs: SmartSetupSuggestion,
        _ rhs: SmartSetupSuggestion,
        contentCoordinateSize: CGSize
    ) -> Bool {
        guard lhs.suggestionID != rhs.suggestionID else { return true }
        guard opportunityTimesOverlap(lhs, rhs) else { return false }

        guard let lhsPoint = normalizedOpportunityPoint(for: lhs, contentCoordinateSize: contentCoordinateSize),
              let rhsPoint = normalizedOpportunityPoint(for: rhs, contentCoordinateSize: contentCoordinateSize) else {
            return lhs.kind == rhs.kind
        }

        let deltaX = lhsPoint.x - rhsPoint.x
        let deltaY = lhsPoint.y - rhsPoint.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot() <= opportunityDistanceTolerance
    }

    private func opportunityTimesOverlap(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        if abs(sortTime(for: lhs) - sortTime(for: rhs)) <= opportunityTimeTolerance {
            return true
        }
        if rangesOverlapSubstantially(lhs.sourceTimeRange, rhs.sourceTimeRange) {
            return true
        }
        guard let lhsRange = lhs.sourceTimeRange, let rhsRange = rhs.sourceTimeRange else {
            return false
        }
        let gap = max(max(lhsRange.startTime, rhsRange.startTime) - min(lhsRange.endTime, rhsRange.endTime), 0)
        return gap <= opportunityTimeTolerance
    }

    private func normalizedOpportunityPoint(
        for suggestion: SmartSetupSuggestion,
        contentCoordinateSize: CGSize
    ) -> (x: Double, y: Double)? {
        let safeWidth = max(contentCoordinateSize.width, 1)
        let safeHeight = max(contentCoordinateSize.height, 1)

        if !suggestion.sourceEvents.isEmpty {
            let total = suggestion.sourceEvents.reduce((x: 0.0, y: 0.0)) { partialResult, event in
                (
                    x: partialResult.x + min(max(event.x / safeWidth, 0), 1),
                    y: partialResult.y + min(max(event.y / safeHeight, 0), 1)
                )
            }
            return (
                x: total.x / Double(suggestion.sourceEvents.count),
                y: total.y / Double(suggestion.sourceEvents.count)
            )
        }

        switch suggestion.proposal {
        case .zoom(let proposal):
            return (
                x: min(max(proposal.centerX / safeWidth, 0), 1),
                y: min(max(proposal.centerY / safeHeight, 0), 1)
            )
        case .effect(let proposal):
            guard let focusRegion = proposal.focusRegion else { return nil }
            return (x: focusRegion.centerX, y: focusRegion.centerY)
        case .regionTighten(let proposal):
            return (x: proposal.proposedRegion.centerX, y: proposal.proposedRegion.centerY)
        case .zoomAdjustment:
            return nil
        }
    }

    private func isCursorPauseSuggestion(_ suggestion: SmartSetupSuggestion) -> Bool {
        guard suggestion.providerID == "rules",
              suggestion.kind == .effectMarker,
              suggestion.reasons.contains(.cursorPause) else {
            return false
        }
        return true
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

private func stableSuggestionChoice(seed: String, from options: [String]) -> String {
    guard !options.isEmpty else { return "" }
    let value = seed.unicodeScalars.reduce(0) { partialResult, scalar in
        ((partialResult &* 31) &+ Int(scalar.value)) & 0x7fffffff
    }
    return options[value % options.count]
}

private extension SmartSetupSuggestion {
    func stableChoice(from options: [String]) -> String {
        stableSuggestionChoice(seed: suggestionID, from: options)
    }
}
