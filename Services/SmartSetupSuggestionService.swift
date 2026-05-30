import CoreGraphics
import Foundation

struct SmartSetupSuggestionService {
    private enum Tuning {
        static let maxZoomAdjustmentSuggestions = 8
        static let maxPauseSuggestions = 18
        static let maxRepeatedZoneSuggestions = 6
        static let zoomSequenceMinimumMarkers = 3
        static let zoomSequenceMaximumGap = 4.0
        static let zoomSequenceAreaTolerance = 0.12
        static let existingZoomTimeTolerance = 0.65
        static let existingEffectTimeTolerance = 0.80
        static let minimumCursorPauseDuration = 0.85
        static let maximumCursorPauseDuration = 6.0
        static let pauseMovementTolerance: Double = 28
        static let pauseEffectLeadIn = 0.20
        static let pauseEffectTail = 0.35
        static let repeatedZoneMinimumEvents = 3
        static let repeatedZoneMinimumDuration = 2.0
        static let repeatedZoneCellSize: CGFloat = 180
        static let repeatedZoneMaximumDuration = 7.0
    }

    func generateSuggestions(
        events: [RecordedEvent],
        duration: Double,
        contentCoordinateSize: CGSize,
        existingZoomMarkers: [ZoomPlanItem],
        existingEffectMarkers: [EffectPlanItem]
    ) -> [SmartSetupSuggestion] {
        let safeDuration = max(duration, 0)
        let safeContentSize = CGSize(
            width: max(contentCoordinateSize.width, 1),
            height: max(contentCoordinateSize.height, 1)
        )
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }

        var suggestions: [SmartSetupSuggestion] = []
        suggestions.append(contentsOf: zoomMarkerAdjustmentSuggestions(
            existingZoomMarkers: existingZoomMarkers,
            contentCoordinateSize: safeContentSize
        ))
        suggestions.append(contentsOf: cursorPauseSuggestions(
            from: sortedEvents,
            duration: safeDuration,
            contentCoordinateSize: safeContentSize,
            existingEffectMarkers: existingEffectMarkers
        ))
        suggestions.append(contentsOf: repeatedActivityZoneSuggestions(
            from: sortedEvents,
            duration: safeDuration,
            contentCoordinateSize: safeContentSize,
            existingEffectMarkers: existingEffectMarkers,
            existingSuggestions: suggestions
        ))

        return suggestions.sorted { lhs, rhs in
            let lhsTime = lhs.sourceTimeRange?.startTime ?? lhs.sourceEvents.first?.timestamp ?? 0
            let rhsTime = rhs.sourceTimeRange?.startTime ?? rhs.sourceEvents.first?.timestamp ?? 0
            if lhsTime != rhsTime {
                return lhsTime < rhsTime
            }
            return lhs.suggestionID < rhs.suggestionID
        }
    }

    private func zoomMarkerAdjustmentSuggestions(
        existingZoomMarkers: [ZoomPlanItem],
        contentCoordinateSize: CGSize
    ) -> [SmartSetupSuggestion] {
        let clickMarkers = existingZoomMarkers
            .filter { $0.enabled && $0.markerKind == .clickFocus }
            .sorted { $0.sourceEventTimestamp < $1.sourceEventTimestamp }
        guard clickMarkers.count >= Tuning.zoomSequenceMinimumMarkers else { return [] }

        var suggestions: [SmartSetupSuggestion] = []
        var currentGroup: [ZoomPlanItem] = []

        func flushCurrentGroup() {
            guard currentGroup.count >= Tuning.zoomSequenceMinimumMarkers,
                  let first = currentGroup.first,
                  let last = currentGroup.last else {
                currentGroup.removeAll()
                return
            }

            let proposal = SmartSetupZoomMarkerAdjustmentProposal(
                targetMarkerIDs: currentGroup.map(\.id),
                startTime: first.sourceEventTimestamp,
                endTime: last.sourceEventTimestamp,
                suggestedFirstZoomType: .inOnly,
                suggestedMiddleZoomType: .noZoom,
                suggestedFinalZoomType: .outOnly,
                suggestedHoldDuration: max(1.0, min(2.5, last.sourceEventTimestamp - first.sourceEventTimestamp)),
                markerCount: currentGroup.count
            )
            let scoreValue = min(0.92, 0.52 + (Double(currentGroup.count) * 0.09))
            let center = averagePoint(for: currentGroup, contentCoordinateSize: contentCoordinateSize)
            suggestions.append(
                SmartSetupSuggestion(
                    suggestionID: stableID(prefix: "smart-zoom-adjust", time: first.sourceEventTimestamp, x: center.x, y: center.y),
                    kind: .zoomMarker,
                    sourceTimeRange: SmartSetupSourceTimeRange(startTime: first.sourceEventTimestamp, endTime: last.sourceEventTimestamp),
                    sourceEvents: currentGroup.map { marker in
                        SmartSetupSourceEventReference(
                            type: .leftMouseDown,
                            timestamp: marker.sourceEventTimestamp,
                            x: marker.rawX ?? marker.centerX,
                            y: marker.rawY ?? marker.centerY
                        )
                    },
                    proposal: .zoomAdjustment(proposal),
                    score: SmartSetupCandidateScore(
                        value: scoreValue,
                        components: [
                            SmartSetupScoreComponent(
                                reason: .repeatedActivityZone,
                                weight: scoreValue,
                                detail: "\(currentGroup.count) actions happened close together"
                            )
                        ]
                    ),
                    reasons: [.repeatedActivityZone]
                )
            )
            currentGroup.removeAll()
        }

        for marker in clickMarkers {
            guard let previous = currentGroup.last else {
                currentGroup = [marker]
                continue
            }

            let timeGap = marker.sourceEventTimestamp - previous.sourceEventTimestamp
            let areaDistance = normalizedDistance(from: previous, to: marker, contentCoordinateSize: contentCoordinateSize)
            if timeGap <= Tuning.zoomSequenceMaximumGap && areaDistance <= Tuning.zoomSequenceAreaTolerance {
                currentGroup.append(marker)
            } else {
                flushCurrentGroup()
                currentGroup = [marker]
            }

            if suggestions.count >= Tuning.maxZoomAdjustmentSuggestions {
                return suggestions
            }
        }
        flushCurrentGroup()

        return Array(suggestions.prefix(Tuning.maxZoomAdjustmentSuggestions))
    }

    private func cursorPauseSuggestions(
        from events: [RecordedEvent],
        duration: Double,
        contentCoordinateSize: CGSize,
        existingEffectMarkers: [EffectPlanItem]
    ) -> [SmartSetupSuggestion] {
        let cursorEvents = events.filter { $0.type == .cursorMoved }
        guard cursorEvents.count >= 2 else { return [] }

        var suggestions: [SmartSetupSuggestion] = []

        for pair in zip(cursorEvents, cursorEvents.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            let pauseDuration = next.timestamp - previous.timestamp
            guard pauseDuration >= Tuning.minimumCursorPauseDuration else { continue }
            guard pauseDuration <= Tuning.maximumCursorPauseDuration else { continue }
            guard previous.timestamp >= 0, previous.timestamp <= duration || duration == 0 else { continue }
            guard distance(from: previous, to: next) <= Tuning.pauseMovementTolerance else { continue }
            guard !hasNearbyEffectMarker(at: previous.timestamp, existingEffectMarkers: existingEffectMarkers) else { continue }
            guard !hasNearbySuggestion(at: previous.timestamp, in: suggestions) else { continue }

            let point = clampedContentPoint(for: previous, contentCoordinateSize: contentCoordinateSize)
            let proposal = effectProposal(
                sourceTime: previous.timestamp,
                startTime: max(0, previous.timestamp - Tuning.pauseEffectLeadIn),
                holdEndTime: min(max(duration, previous.timestamp), next.timestamp),
                endTime: min(max(duration, next.timestamp), next.timestamp + Tuning.pauseEffectTail),
                center: point,
                contentCoordinateSize: contentCoordinateSize
            )
            let scoreValue = min(0.92, 0.52 + (pauseDuration / 5.0))
            let score = SmartSetupCandidateScore(
                value: scoreValue,
                components: [
                    SmartSetupScoreComponent(
                        reason: .cursorPause,
                        weight: scoreValue,
                        detail: "Attention stayed in one area for \(formatTime(pauseDuration))s"
                    )
                ]
            )

            suggestions.append(
                SmartSetupSuggestion(
                    suggestionID: stableID(prefix: "smart-effect-pause", time: previous.timestamp, x: previous.x, y: previous.y),
                    kind: .effectMarker,
                    sourceTimeRange: SmartSetupSourceTimeRange(startTime: previous.timestamp, endTime: next.timestamp),
                    sourceEvents: [SmartSetupSourceEventReference(event: previous), SmartSetupSourceEventReference(event: next)],
                    proposal: .effect(proposal),
                    score: score,
                    reasons: [.cursorPause]
                )
            )

            if suggestions.count >= Tuning.maxPauseSuggestions {
                break
            }
        }

        return suggestions
    }

    private func repeatedActivityZoneSuggestions(
        from events: [RecordedEvent],
        duration: Double,
        contentCoordinateSize: CGSize,
        existingEffectMarkers: [EffectPlanItem],
        existingSuggestions: [SmartSetupSuggestion]
    ) -> [SmartSetupSuggestion] {
        let activityEvents = events.filter { event in
            event.type == .leftMouseDown || event.type == .rightMouseDown
        }
        guard activityEvents.count >= Tuning.repeatedZoneMinimumEvents else { return [] }

        let groupedEvents = Dictionary(grouping: activityEvents) { event in
            zoneKey(for: event, contentCoordinateSize: contentCoordinateSize)
        }

        var candidates: [(key: String, events: [RecordedEvent])] = groupedEvents.compactMap { key, events in
            let sorted = events.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= Tuning.repeatedZoneMinimumEvents,
                  let first = sorted.first,
                  let last = sorted.last,
                  last.timestamp - first.timestamp >= Tuning.repeatedZoneMinimumDuration else {
                return nil
            }
            return (key, sorted)
        }
        candidates.sort { lhs, rhs in
            if lhs.events.count != rhs.events.count {
                return lhs.events.count > rhs.events.count
            }
            return (lhs.events.first?.timestamp ?? 0) < (rhs.events.first?.timestamp ?? 0)
        }

        var suggestions: [SmartSetupSuggestion] = []

        for candidate in candidates {
            guard let first = candidate.events.first, let last = candidate.events.last else { continue }
            let startTime = first.timestamp
            let endTime = min(last.timestamp, startTime + Tuning.repeatedZoneMaximumDuration)
            guard !hasNearbyEffectMarker(at: startTime, existingEffectMarkers: existingEffectMarkers) else { continue }
            guard !hasNearbySuggestion(at: startTime, in: existingSuggestions + suggestions) else { continue }

            let center = averagePoint(for: candidate.events, contentCoordinateSize: contentCoordinateSize)
            let proposal = effectProposal(
                sourceTime: startTime + ((endTime - startTime) / 2),
                startTime: max(0, startTime - 0.20),
                holdEndTime: endTime,
                endTime: min(max(duration, endTime), endTime + 0.45),
                center: center,
                contentCoordinateSize: contentCoordinateSize
            )
            let scoreValue = min(0.88, 0.48 + (Double(candidate.events.count) * 0.08))
            let score = SmartSetupCandidateScore(
                value: scoreValue,
                components: [
                    SmartSetupScoreComponent(
                        reason: .repeatedActivityZone,
                        weight: scoreValue,
                        detail: "\(candidate.events.count) actions happened in one area"
                    )
                ]
            )

            suggestions.append(
                SmartSetupSuggestion(
                    suggestionID: stableID(prefix: "smart-effect-zone", time: startTime, x: center.x, y: center.y),
                    kind: .effectMarker,
                    sourceTimeRange: SmartSetupSourceTimeRange(startTime: startTime, endTime: endTime),
                    sourceEvents: candidate.events.map(SmartSetupSourceEventReference.init(event:)),
                    proposal: .effect(proposal),
                    score: score,
                    reasons: [.repeatedActivityZone]
                )
            )

            if suggestions.count >= Tuning.maxRepeatedZoneSuggestions {
                break
            }
        }

        return suggestions
    }

    private func effectProposal(
        sourceTime: Double,
        startTime: Double,
        holdEndTime: Double,
        endTime: Double,
        center: CGPoint,
        contentCoordinateSize: CGSize
    ) -> SmartSetupEffectMarkerProposal {
        let normalizedCenter = normalizedPoint(center, contentCoordinateSize: contentCoordinateSize)
        let safeEndTime = max(endTime, startTime + 0.40)
        let safeHoldStart = min(max(startTime + 0.18, startTime), safeEndTime)
        let safeHoldEnd = min(max(holdEndTime, safeHoldStart), safeEndTime)

        return SmartSetupEffectMarkerProposal(
            sourceEventTimestamp: sourceTime,
            startTime: startTime,
            holdStartTime: safeHoldStart,
            holdEndTime: safeHoldEnd,
            endTime: safeEndTime,
            style: .blurDarken,
            amount: 0.48,
            blurAmount: 0.48,
            darkenAmount: 0.42,
            tintAmount: 0.0,
            cornerRadius: 18,
            feather: 0,
            tintColor: .defaultTint,
            focusRegion: EffectFocusRegion(
                centerX: normalizedCenter.x,
                centerY: normalizedCenter.y,
                width: 0.24,
                height: 0.18
            ),
            distortion: nil
        )
    }

    private func hasNearbyZoomMarker(at time: Double, existingZoomMarkers: [ZoomPlanItem]) -> Bool {
        existingZoomMarkers.contains { marker in
            abs(marker.sourceEventTimestamp - time) <= Tuning.existingZoomTimeTolerance
        }
    }

    private func hasNearbyEffectMarker(at time: Double, existingEffectMarkers: [EffectPlanItem]) -> Bool {
        existingEffectMarkers.contains { marker in
            abs(marker.snapTime - time) <= Tuning.existingEffectTimeTolerance ||
            (time >= marker.startTime && time <= marker.endTime)
        }
    }

    private func hasNearbySuggestion(at time: Double, in suggestions: [SmartSetupSuggestion]) -> Bool {
        suggestions.contains { suggestion in
            guard suggestion.kind == .effectMarker else { return false }
            let suggestionTime = suggestion.sourceTimeRange?.startTime ?? suggestion.sourceEvents.first?.timestamp ?? 0
            return abs(suggestionTime - time) <= Tuning.existingEffectTimeTolerance
        }
    }

    private func clampedContentPoint(for event: RecordedEvent, contentCoordinateSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(event.x, 0), contentCoordinateSize.width),
            y: min(max(event.y, 0), contentCoordinateSize.height)
        )
    }

    private func averagePoint(for events: [RecordedEvent], contentCoordinateSize: CGSize) -> CGPoint {
        guard !events.isEmpty else { return .zero }
        let total = events.reduce(CGPoint.zero) { partialResult, event in
            let point = clampedContentPoint(for: event, contentCoordinateSize: contentCoordinateSize)
            return CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(events.count), y: total.y / CGFloat(events.count))
    }

    private func averagePoint(for markers: [ZoomPlanItem], contentCoordinateSize: CGSize) -> CGPoint {
        guard !markers.isEmpty else { return .zero }
        let total = markers.reduce(CGPoint.zero) { partialResult, marker in
            let point = contentPoint(for: marker, contentCoordinateSize: contentCoordinateSize)
            return CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(markers.count), y: total.y / CGFloat(markers.count))
    }

    private func normalizedDistance(from lhs: ZoomPlanItem, to rhs: ZoomPlanItem, contentCoordinateSize: CGSize) -> Double {
        let lhsPoint = normalizedPoint(contentPoint(for: lhs, contentCoordinateSize: contentCoordinateSize), contentCoordinateSize: contentCoordinateSize)
        let rhsPoint = normalizedPoint(contentPoint(for: rhs, contentCoordinateSize: contentCoordinateSize), contentCoordinateSize: contentCoordinateSize)
        let deltaX = lhsPoint.x - rhsPoint.x
        let deltaY = lhsPoint.y - rhsPoint.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    private func contentPoint(for marker: ZoomPlanItem, contentCoordinateSize: CGSize) -> CGPoint {
        if let rawX = marker.rawX, let rawY = marker.rawY {
            return CGPoint(
                x: min(max(rawX, 0), contentCoordinateSize.width),
                y: min(max(rawY, 0), contentCoordinateSize.height)
            )
        }
        if marker.centerX <= 1.5 && marker.centerY <= 1.5 {
            return CGPoint(
                x: min(max(marker.centerX, 0), 1) * contentCoordinateSize.width,
                y: min(max(marker.centerY, 0), 1) * contentCoordinateSize.height
            )
        }
        return CGPoint(
            x: min(max(marker.centerX, 0), contentCoordinateSize.width),
            y: min(max(marker.centerY, 0), contentCoordinateSize.height)
        )
    }

    private func normalizedPoint(_ point: CGPoint, contentCoordinateSize: CGSize) -> (x: Double, y: Double) {
        let x = Double(min(max(point.x / max(contentCoordinateSize.width, 1), 0), 1))
        let y = Double(min(max(point.y / max(contentCoordinateSize.height, 1), 0), 1))
        return (x, y)
    }

    private func distance(from lhs: RecordedEvent, to rhs: RecordedEvent) -> Double {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    private func zoneKey(for event: RecordedEvent, contentCoordinateSize: CGSize) -> String {
        let point = clampedContentPoint(for: event, contentCoordinateSize: contentCoordinateSize)
        let column = Int(point.x / Tuning.repeatedZoneCellSize)
        let row = Int(point.y / Tuning.repeatedZoneCellSize)
        return "\(column):\(row)"
    }

    private func stableID(prefix: String, time: Double, x: Double, y: Double) -> String {
        let timeMillis = Int((time * 1000).rounded())
        let xInt = Int(x.rounded())
        let yInt = Int(y.rounded())
        return "\(prefix)-\(timeMillis)-\(xInt)-\(yInt)"
    }

    private func formatTime(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
