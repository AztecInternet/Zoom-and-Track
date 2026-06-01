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
                "Extend this zoom hold by about 0.5 seconds",
                "Refine this focus sequence",
                "Tighten this interaction sequence"
            ])
        case .effect:
            return suggestion.stableChoice(from: [
                "Add a subtle focus effect here",
                "Add a focus effect to this moment",
                "Add a gentle visual cue here"
            ])
        case .zoom, .regionTighten:
            return suggestion.stableChoice(from: [
                "Add a short focus hold here",
                "Add a short focus hold for this moment",
                "Add a short focus hold around this action"
            ])
        }
    }

    private func reason(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoomAdjustment:
            return suggestion.stableChoice(from: [
                "Viewers may need more time to follow the full sequence.",
                "The sequence may read better as one controlled focus move.",
                "This interaction works best when it stays visible as one clear step."
            ])
        case .effect:
            return suggestion.stableChoice(from: [
                "This area may need a little more visual weight.",
                "The viewer's attention may need to stay on this part of the screen.",
                "A gentle visual cue can help this moment read more clearly."
            ])
        case .zoom, .regionTighten:
            return suggestion.stableChoice(from: [
                "Viewers may need a clearer look at this moment.",
                "This part is easy to miss at the current pace.",
                "The surrounding edit may move past this action too quickly."
            ])
        }
    }
}

struct ExistingEditReviewSmartSuggestionProvider: SmartSuggestionProvider {
    let providerID = "existing-edits"

    private let maxSuggestions = 6
    private let shortZoomDurationThreshold = 1.15
    private let shortZoomHoldThreshold = 0.45
    private let zoomInteractionDistance = 0.17

    func generateSuggestions(context: SmartSuggestionContext) -> [SmartSetupSuggestion] {
        debugProviderInput(context)

        let safeContentSize = CGSize(
            width: max(context.contentCoordinateSize.width, 1),
            height: max(context.contentCoordinateSize.height, 1)
        )
        let realZoomMarkerIDs = Set(context.existingZoomMarkers.map(\.id))
        let realEffectMarkerIDs = Set(context.existingEffectMarkers.map(\.id))
        var zoomSuggestions: [SmartSetupSuggestion] = []
        var effectSuggestions: [SmartSetupSuggestion] = []

        for marker in context.existingZoomMarkers {
            debugMarkerInput(type: "zoom", markerID: marker.id, markerName: marker.markerName, style: nil, startTime: marker.startTime, endTime: marker.endTime, enabled: marker.enabled)
            guard marker.enabled else {
                debugSkippedMarker(type: "zoom", markerID: marker.id, reason: "disabled")
                continue
            }
            if let suggestion = zoomSuggestion(for: marker, context: context, contentCoordinateSize: safeContentSize) {
                zoomSuggestions.append(suggestion)
            } else {
                debugSkippedMarker(type: "zoom", markerID: marker.id, reason: "invalid time range")
            }
        }

        for marker in context.existingEffectMarkers {
            debugMarkerInput(type: "effect", markerID: marker.id, markerName: marker.markerName, style: marker.style.rawValue, startTime: marker.startTime, endTime: marker.endTime, enabled: marker.enabled)
            guard marker.enabled else {
                debugSkippedMarker(type: "effect", markerID: marker.id, reason: "disabled")
                continue
            }
            if let suggestion = effectSuggestion(for: marker, context: context, contentCoordinateSize: safeContentSize) {
                effectSuggestions.append(suggestion)
            } else {
                debugSkippedMarker(type: "effect", markerID: marker.id, reason: "invalid time range")
            }
        }

        let sortedEffects = sortedSuggestions(effectSuggestions)
        let remainingSlots = max(maxSuggestions - sortedEffects.count, 0)
        let selectedZooms = Array(sortedSuggestions(zoomSuggestions).prefix(remainingSlots))
        let selectedSuggestions = sortedSuggestions(sortedEffects + selectedZooms)
        for suggestion in selectedSuggestions {
            debugCreatedSuggestion(
                suggestion,
                realZoomMarkerIDs: realZoomMarkerIDs,
                realEffectMarkerIDs: realEffectMarkerIDs
            )
        }
        debugExistingEffectReviewCardCount(
            effectMarkerCount: context.existingEffectMarkers.count,
            suggestions: selectedSuggestions,
            realEffectMarkerIDs: realEffectMarkerIDs
        )
        for suggestion in zoomSuggestions where !selectedSuggestions.contains(where: { $0.suggestionID == suggestion.suggestionID }) {
            debugSkippedSuggestion(suggestion, reason: "provider cap reserved review slots for real effect markers")
        }
        return selectedSuggestions
    }

    private func zoomSuggestion(
        for marker: ZoomPlanItem,
        context: SmartSuggestionContext,
        contentCoordinateSize: CGSize
    ) -> SmartSetupSuggestion? {
        guard marker.endTime > marker.startTime else { return nil }

        let sourceEvents = events(
            in: marker.startTime...marker.endTime,
            from: context.events,
            limit: 8
        )
        let alignedEvents = sourceEvents.filter {
            normalizedDistance(
                from: $0,
                toNormalizedX: marker.centerX / contentCoordinateSize.width,
                normalizedY: marker.centerY / contentCoordinateSize.height,
                contentCoordinateSize: contentCoordinateSize
            ) <= zoomInteractionDistance
        }
        let alignsWithInteraction = !alignedEvents.isEmpty
        let markerDuration = marker.endTime - marker.startTime
        let mayBeTooShort = (markerDuration < shortZoomDurationThreshold || marker.holdDuration < shortZoomHoldThreshold) && !sourceEvents.isEmpty
        let title: String
        let reason: String
        let evidenceReason: String
        if mayBeTooShort {
            title = "Extend this zoom hold by about 0.5 seconds"
            reason = "Viewers may need more time to absorb the information before the zoom ends."
            evidenceReason = "zoom-hold-too-short"
        } else if alignsWithInteraction {
            title = "Keep this zoom"
            reason = "The zoom appears to follow the action and guide attention to the right area."
            evidenceReason = "zoom-covers-active-area"
        } else if sourceEvents.isEmpty {
            title = "Consider removing this zoom"
            reason = "There may not be enough visible action here for this zoom to clarify the edit."
            evidenceReason = "zoom-no-clear-activity"
        } else {
            title = "Move this zoom"
            reason = "The focus point may not land on the most important part of the screen."
            evidenceReason = "zoom-region-far-from-activity"
        }

        let proposal = SmartSetupZoomMarkerProposal(
            sourceEventTimestamp: marker.sourceEventTimestamp,
            rawX: marker.rawX,
            rawY: marker.rawY,
            centerX: marker.centerX,
            centerY: marker.centerY,
            zoomScale: marker.zoomScale,
            leadInTime: marker.leadInTime,
            zoomInDuration: marker.zoomInDuration,
            holdDuration: marker.holdDuration,
            zoomOutDuration: marker.zoomOutDuration,
            easeStyle: marker.easeStyle,
            zoomType: marker.zoomType,
            bounceAmount: marker.bounceAmount,
            clickPulse: marker.clickPulse,
            noZoomFallbackMode: marker.noZoomFallbackMode,
            noZoomOverflowRegion: marker.noZoomOverflowRegion
        )
        let score = existingEditScore(
            base: mayBeTooShort ? 0.82 : 0.76,
            hasActivity: !sourceEvents.isEmpty,
            alignsWithActivity: alignsWithInteraction,
            hasTimingConcern: mayBeTooShort
        )
        let reasons = existingEditReasons(
            hasActivity: !sourceEvents.isEmpty,
            alignsWithActivity: alignsWithInteraction,
            hasTimingConcern: mayBeTooShort
        )

        let suggestion = SmartSetupSuggestion(
            suggestionID: "existing-zoom-\(marker.id)",
            providerID: providerID,
            userTitle: title,
            userReason: reason,
            kind: .zoomMarker,
            sourceTimeRange: SmartSetupSourceTimeRange(startTime: marker.startTime, endTime: marker.endTime),
            sourceEvents: sourceEvents.map(SmartSetupSourceEventReference.init(event:)),
            proposal: .zoom(proposal),
            score: score,
            reasons: reasons
        )
        debugCandidateSuggestion(suggestion, markerID: marker.id, markerType: "zoom", evidenceReason: evidenceReason)
        return suggestion
    }

    private func effectSuggestion(
        for marker: EffectPlanItem,
        context: SmartSuggestionContext,
        contentCoordinateSize: CGSize
    ) -> SmartSetupSuggestion? {
        guard marker.endTime > marker.startTime else { return nil }

        let sourceEvents = events(
            in: marker.startTime...marker.endTime,
            from: context.events,
            limit: 8
        )
        let focusRect = marker.focusRegion.map(rect(for:))
        let eventRelationships = sourceEvents.map { event in
            focusRelationship(
                for: event,
                focusRect: focusRect,
                contentCoordinateSize: contentCoordinateSize
            )
        }
        let eventsNearFocus = eventRelationships.filter { $0.relationship == "inside" || $0.relationship == "near" }
        let hasFocusRegion = marker.focusRegion != nil
        let coversActiveArea = hasFocusRegion ? !eventsNearFocus.isEmpty : !sourceEvents.isEmpty
        let markerDuration = marker.endTime - marker.startTime
        let activityDuration = activitySpanDuration(sourceEvents)
        let activityOutsideFocus = hasFocusRegion && !sourceEvents.isEmpty && eventsNearFocus.isEmpty
        let mayBeTooShort = coversActiveArea
            && markerDuration < 0.70
            && activityDuration > markerDuration + 0.35
        let title: String
        let reason: String
        let evidenceReason: String
        if activityOutsideFocus {
            title = "Expand this effect region to include the changing content"
            reason = "The highlighted area may not fully cover the information changing on screen."
            evidenceReason = "effect-region-far-from-activity"
        } else if mayBeTooShort {
            title = "Extend this effect"
            reason = "Viewers may need more time to understand the highlighted area."
            evidenceReason = "effect-too-short-for-activity"
        } else if coversActiveArea {
            title = "Keep this effect"
            reason = "The effect appears to cover active content and guide attention without obvious distraction."
            evidenceReason = "effect-covers-active-area"
        } else if hasFocusRegion {
            title = "Consider removing this effect"
            reason = "The highlighted area may not add enough guidance for this step."
            evidenceReason = "effect-no-clear-activity"
        } else {
            title = "Keep this effect"
            reason = "The effect can stay if it still helps the viewer understand the moment."
            evidenceReason = "effect-review-neutral"
        }

        let proposal = SmartSetupEffectMarkerProposal(
            sourceEventTimestamp: marker.sourceEventTimestamp,
            startTime: marker.startTime,
            holdStartTime: marker.holdStartTime,
            holdEndTime: marker.holdEndTime,
            endTime: marker.endTime,
            style: marker.style,
            amount: marker.amount,
            blurAmount: marker.blurAmount,
            darkenAmount: marker.darkenAmount,
            tintAmount: marker.tintAmount,
            cornerRadius: marker.cornerRadius,
            feather: marker.feather,
            tintColor: marker.tintColor,
            focusRegion: marker.focusRegion,
            distortion: marker.distortion
        )
        let score = existingEditScore(
            base: mayBeTooShort ? 0.84 : 0.78,
            hasActivity: !sourceEvents.isEmpty,
            alignsWithActivity: coversActiveArea,
            hasTimingConcern: mayBeTooShort
        )
        let reasons = existingEditReasons(
            hasActivity: !sourceEvents.isEmpty,
            alignsWithActivity: coversActiveArea,
            hasTimingConcern: mayBeTooShort
        )

        debugEffectRegionEvidence(
            marker: marker,
            focusRect: focusRect,
            relationships: eventRelationships,
            evidenceReason: evidenceReason
        )

        let suggestion = SmartSetupSuggestion(
            suggestionID: "existing-effect-\(marker.id)",
            providerID: providerID,
            userTitle: title,
            userReason: reason,
            kind: .effectMarker,
            sourceTimeRange: SmartSetupSourceTimeRange(startTime: marker.startTime, endTime: marker.endTime),
            sourceEvents: sourceEvents.map(SmartSetupSourceEventReference.init(event:)),
            proposal: .effect(proposal),
            score: score,
            reasons: reasons
        )
        debugCandidateSuggestion(suggestion, markerID: marker.id, markerType: "effect", evidenceReason: evidenceReason)
        return suggestion
    }

    private func sortedSuggestions(_ suggestions: [SmartSetupSuggestion]) -> [SmartSetupSuggestion] {
        suggestions.sorted { lhs, rhs in
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

    private func activitySpanDuration(_ events: [RecordedEvent]) -> Double {
        guard let first = events.first?.timestamp,
              let last = events.last?.timestamp else {
            return 0
        }
        return max(last - first, 0)
    }

    private func focusRelationship(
        for event: RecordedEvent,
        focusRect: CGRect?,
        contentCoordinateSize: CGSize
    ) -> (timestamp: Double, point: CGPoint, relationship: String) {
        let point = normalizedPoint(for: event, contentCoordinateSize: contentCoordinateSize)
        guard let focusRect else {
            return (event.timestamp, point, "no-region")
        }
        if focusRect.insetBy(dx: -0.04, dy: -0.04).contains(point) {
            return (event.timestamp, point, "inside")
        }
        if focusRect.insetBy(dx: -0.16, dy: -0.16).contains(point) {
            return (event.timestamp, point, "near")
        }
        return (event.timestamp, point, "outside")
    }

    private func normalizedPoint(for event: RecordedEvent, contentCoordinateSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(event.x / contentCoordinateSize.width, 0), 1),
            y: min(max(event.y / contentCoordinateSize.height, 0), 1)
        )
    }

    private func events(in range: ClosedRange<Double>, from events: [RecordedEvent], limit: Int) -> [RecordedEvent] {
        Array(events
            .filter { range.contains($0.timestamp) }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }
            .prefix(limit))
    }

    private func existingEditScore(
        base: Double,
        hasActivity: Bool,
        alignsWithActivity: Bool,
        hasTimingConcern: Bool
    ) -> SmartSetupCandidateScore {
        var value = base
        if hasActivity { value += 0.035 }
        if alignsWithActivity { value += 0.045 }
        if hasTimingConcern { value += 0.035 }

        var components = [
            SmartSetupScoreComponent(
                reason: .manualRegion,
                weight: 0.66,
                detail: "Existing edit shows editor intent."
            )
        ]
        if hasActivity {
            components.append(SmartSetupScoreComponent(
                reason: .click,
                weight: 0.12,
                detail: "Recorded interaction occurs during this edit."
            ))
        }
        if alignsWithActivity {
            components.append(SmartSetupScoreComponent(
                reason: .denseActivity,
                weight: 0.10,
                detail: "The edit overlaps the active area."
            ))
        }
        if hasTimingConcern {
            components.append(SmartSetupScoreComponent(
                reason: .timelineGap,
                weight: 0.10,
                detail: "The edit may end before the action is easy to follow."
            ))
        }

        return SmartSetupCandidateScore(value: min(value, 0.93), components: components)
    }

    private func existingEditReasons(
        hasActivity: Bool,
        alignsWithActivity: Bool,
        hasTimingConcern: Bool
    ) -> [SmartSetupSuggestionReason] {
        var reasons: [SmartSetupSuggestionReason] = [.manualRegion]
        if hasActivity { reasons.append(.click) }
        if alignsWithActivity { reasons.append(.denseActivity) }
        if hasTimingConcern { reasons.append(.timelineGap) }
        return reasons
    }

    private func normalizedDistance(
        from event: RecordedEvent,
        toNormalizedX normalizedX: Double,
        normalizedY: Double,
        contentCoordinateSize: CGSize
    ) -> Double {
        let eventX = min(max(event.x / contentCoordinateSize.width, 0), 1)
        let eventY = min(max(event.y / contentCoordinateSize.height, 0), 1)
        let deltaX = eventX - min(max(normalizedX, 0), 1)
        let deltaY = eventY - min(max(normalizedY, 0), 1)
        return ((deltaX * deltaX) + (deltaY * deltaY)).squareRoot()
    }

    private func rect(for region: EffectFocusRegion) -> CGRect {
        CGRect(
            x: region.centerX - region.width / 2,
            y: region.centerY - region.height / 2,
            width: region.width,
            height: region.height
        )
    }

    private func debugProviderInput(_ context: SmartSuggestionContext) {
        #if DEBUG
        print("[ExistingEditReview] input zoomCount=\(context.existingZoomMarkers.count) effectCount=\(context.existingEffectMarkers.count)")
        #endif
    }

    private func debugMarkerInput(
        type: String,
        markerID: String,
        markerName: String?,
        style: String?,
        startTime: Double,
        endTime: Double,
        enabled: Bool
    ) {
        #if DEBUG
        let nameText = markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? markerName! : "none"
        let styleText = style ?? "n/a"
        print("[ExistingEditReview] marker type=\(type) id=\(markerID) range=\(timeRangeText(startTime: startTime, endTime: endTime)) name=\(nameText) style=\(styleText) enabled=\(enabled) origin=existing-marker proposal=false")
        #endif
    }

    private func debugSkippedMarker(type: String, markerID: String, reason: String) {
        #if DEBUG
        print("[ExistingEditReview] skipped marker type=\(type) id=\(markerID) reason=\(reason) origin=existing-marker proposal=false")
        #endif
    }

    private func debugEffectRegionEvidence(
        marker: EffectPlanItem,
        focusRect: CGRect?,
        relationships: [(timestamp: Double, point: CGPoint, relationship: String)],
        evidenceReason: String
    ) {
        #if DEBUG
        let regionText: String
        if let focusRect {
            regionText = String(
                format: "x=%.3f y=%.3f w=%.3f h=%.3f",
                focusRect.minX,
                focusRect.minY,
                focusRect.width,
                focusRect.height
            )
        } else {
            regionText = "none"
        }
        let pointsText = relationships.map { item in
            String(
                format: "%.2f:(%.3f,%.3f):%@",
                item.timestamp,
                item.point.x,
                item.point.y,
                item.relationship
            )
        }.joined(separator: ",")
        print("[ExistingEditReview] effect-region markerID=\(marker.id) range=\(timeRangeText(startTime: marker.startTime, endTime: marker.endTime)) focusRegion=\(regionText) activityPoints=[\(pointsText)] reason=\(evidenceReason)")
        #endif
    }

    private func debugCandidateSuggestion(
        _ suggestion: SmartSetupSuggestion,
        markerID: String,
        markerType: String,
        evidenceReason: String
    ) {
        #if DEBUG
        let range = suggestion.sourceTimeRange.map { timeRangeText(startTime: $0.startTime, endTime: $0.endTime) } ?? "n/a"
        let title = suggestion.userTitle ?? "n/a"
        print("[ExistingEditReview] candidate markerID=\(markerID) markerType=\(markerType) markerRange=\(range) suggestionID=\(suggestion.suggestionID) title=\(title) reason=\(evidenceReason) origin=existing-marker proposal=false")
        #endif
    }

    private func debugCreatedSuggestion(
        _ suggestion: SmartSetupSuggestion,
        realZoomMarkerIDs: Set<String>,
        realEffectMarkerIDs: Set<String>
    ) {
        #if DEBUG
        let markerType: String
        let markerID: String
        if let effectMarkerID = existingEffectMarkerID(from: suggestion.suggestionID) {
            markerType = "effect"
            markerID = effectMarkerID
        } else if let zoomMarkerID = existingZoomMarkerID(from: suggestion.suggestionID) {
            markerType = "zoom"
            markerID = zoomMarkerID
        } else {
            markerType = "unknown"
            markerID = "unknown"
        }
        let range = suggestion.sourceTimeRange.map { timeRangeText(startTime: $0.startTime, endTime: $0.endTime) } ?? "n/a"
        let title = suggestion.userTitle ?? "n/a"
        let evidenceReason = debugEvidenceReason(for: suggestion)
        let realZoom = isExistingZoomReviewSuggestion(suggestion, realZoomMarkerIDs: realZoomMarkerIDs)
        let realEffect = isExistingEffectReviewSuggestion(suggestion, realEffectMarkerIDs: realEffectMarkerIDs)
        print("[ExistingEditReview] created markerID=\(markerID) markerType=\(markerType) markerRange=\(range) suggestionID=\(suggestion.suggestionID) title=\(title) reason=\(evidenceReason) realZoom=\(realZoom) realEffect=\(realEffect) origin=existing-marker proposal=false")
        #endif
    }

    private func debugExistingEffectReviewCardCount(
        effectMarkerCount: Int,
        suggestions: [SmartSetupSuggestion],
        realEffectMarkerIDs: Set<String>
    ) {
        #if DEBUG
        let reviewCount = suggestions.filter {
            isExistingEffectReviewSuggestion($0, realEffectMarkerIDs: realEffectMarkerIDs)
        }.count
        if reviewCount > effectMarkerCount {
            print("[ExistingEditReview] WARNING effectMarkers=\(effectMarkerCount) existingEffectReviewCards=\(reviewCount)")
        } else {
            print("[ExistingEditReview] effectMarkers=\(effectMarkerCount) existingEffectReviewCards=\(reviewCount) OK")
        }
        #endif
    }

    private func isExistingEffectReviewSuggestion(
        _ suggestion: SmartSetupSuggestion,
        realEffectMarkerIDs: Set<String>
    ) -> Bool {
        guard suggestion.providerID == providerID,
              suggestion.kind == .effectMarker,
              let markerID = existingEffectMarkerID(from: suggestion.suggestionID),
              realEffectMarkerIDs.contains(markerID) else {
            return false
        }
        if case .effect = suggestion.proposal {
            return true
        }
        return false
    }

    private func isExistingZoomReviewSuggestion(
        _ suggestion: SmartSetupSuggestion,
        realZoomMarkerIDs: Set<String>
    ) -> Bool {
        guard suggestion.providerID == providerID,
              suggestion.kind == .zoomMarker,
              let markerID = existingZoomMarkerID(from: suggestion.suggestionID),
              realZoomMarkerIDs.contains(markerID) else {
            return false
        }
        switch suggestion.proposal {
        case .zoom, .zoomAdjustment:
            return true
        case .effect, .regionTighten:
            return false
        }
    }

    private func existingEffectMarkerID(from suggestionID: String) -> String? {
        guard suggestionID.hasPrefix("existing-effect-") else { return nil }
        return String(suggestionID.dropFirst("existing-effect-".count))
    }

    private func existingZoomMarkerID(from suggestionID: String) -> String? {
        guard suggestionID.hasPrefix("existing-zoom-") else { return nil }
        return String(suggestionID.dropFirst("existing-zoom-".count))
    }

    private func debugEvidenceReason(for suggestion: SmartSetupSuggestion) -> String {
        guard let title = suggestion.userTitle else { return "existing-edit-review" }
        switch title {
        case "Keep this effect":
            return suggestion.sourceEvents.isEmpty ? "effect-review-neutral" : "effect-covers-active-area"
        case "Extend this effect":
            return "effect-too-short-for-activity"
        case "Resize this effect region", "Expand this effect region to include the changing content":
            return "effect-region-far-from-activity"
        case "Consider removing this effect":
            return "effect-no-clear-activity"
        case "Keep this zoom":
            return suggestion.sourceEvents.isEmpty ? "zoom-no-clear-activity" : "zoom-covers-active-area"
        case "Extend this zoom hold", "Extend this zoom hold by about 0.5 seconds":
            return "zoom-hold-too-short"
        case "Move this zoom":
            return "zoom-region-far-from-activity"
        case "Consider removing this zoom":
            return "zoom-no-clear-activity"
        case "Review this focus effect":
            return suggestion.sourceEvents.isEmpty ? "effect-no-clear-activity" : "effect-covers-active-area"
        case "Check this effect timing":
            return "effect-too-short-for-activity"
        case "Check this effect region":
            return "effect-region-far-from-activity"
        case "Review this visual effect":
            return "effect-review-neutral"
        case "Review this focus zoom":
            return suggestion.sourceEvents.isEmpty ? "zoom-no-clear-activity" : "zoom-covers-active-area"
        case "Check this zoom hold":
            return "zoom-hold-too-short"
        case "Check this zoom framing":
            return "zoom-region-far-from-activity"
        default:
            return "existing-edit-review"
        }
    }

    private func debugSkippedSuggestion(_ suggestion: SmartSetupSuggestion, reason: String) {
        #if DEBUG
        let range = suggestion.sourceTimeRange.map { timeRangeText(startTime: $0.startTime, endTime: $0.endTime) } ?? "n/a"
        let title = suggestion.userTitle ?? "n/a"
        print("[ExistingEditReview] skipped suggestionID=\(suggestion.suggestionID) markerRange=\(range) title=\(title) reason=\(reason) origin=existing-marker proposal=false")
        #endif
    }

    private func timeRangeText(startTime: Double, endTime: Double) -> String {
        "\(timeText(startTime))-\(timeText(endTime))"
    }

    private func timeText(_ time: Double) -> String {
        let clamped = max(time, 0)
        let minutes = Int(clamped) / 60
        let seconds = clamped - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, seconds)
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
            "Add a zoom hold covering these \(cluster.count) clicks",
            "Add a short focus hold for this \(cluster.count)-step interaction",
            "Add a zoom hold through these \(cluster.count) actions"
        ])
    }

    private func clusterReason(for cluster: [RecordedEvent], event: RecordedEvent) -> String {
        stableSuggestionChoice(seed: "\(providerID)-reason-\(cluster.count)-\(event.timestamp)", from: [
            "Viewers may need more time to follow this short sequence.",
            "This interaction is easy to miss at the current pace.",
            "The steps may move too quickly without a brief hold."
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
                "Add a short focus hold for this click",
                "Add a brief zoom hold for this interaction",
                "Add a small click emphasis here"
            ]),
            userReason: stableSuggestionChoice(seed: "\(providerID)-reason-\(event.timestamp)", from: [
                "This click is easy to miss at the current pace.",
                "The viewer may need a clearer look at this action.",
                "The edit may move past this click too quickly."
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
            ExistingEditReviewSmartSuggestionProvider(),
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
        let consolidatedSuggestions = consolidatedSuggestions(
            from: curatedSuggestions,
            contentCoordinateSize: context.contentCoordinateSize
        )

        let sortedSuggestions = consolidatedSuggestions.sorted { lhs, rhs in
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

    private enum ConsolidationIntent: Int {
        case adjust = 4
        case add = 3
        case keep = 2
        case remove = 1
        case fallback = 0
    }

    private enum ConsolidationRelation {
        case duplicateExistingMarker
        case duplicateInteractionCluster
        case duplicateSidebarAction
        case duplicateContextLabel
        case duplicateVisualMoment
        case sameVisibleMoment
        case competesWithExistingEditAdjustment
        case competesWithExistingEffectAdjustment
        case genericClickLowValue
        case newProposalCannotBeKeep
        case genericAddDuplicate
        case weakKeep
        case weakGenericAdd

        var reason: String {
            switch self {
            case .duplicateExistingMarker:
                return "duplicate-existing-marker"
            case .duplicateInteractionCluster:
                return "duplicate-interaction-cluster"
            case .duplicateSidebarAction:
                return "duplicate-sidebar-action"
            case .duplicateContextLabel:
                return "duplicate-context-label"
            case .duplicateVisualMoment:
                return "duplicate-visual-moment"
            case .sameVisibleMoment:
                return "same-visible-moment"
            case .competesWithExistingEditAdjustment:
                return "competes-with-existing-edit-adjustment"
            case .competesWithExistingEffectAdjustment:
                return "competes-with-existing-effect-adjustment"
            case .genericClickLowValue:
                return "generic-click-low-value"
            case .newProposalCannotBeKeep:
                return "new-proposal-cannot-be-keep"
            case .genericAddDuplicate:
                return "generic-add-duplicate"
            case .weakKeep:
                return "weak-keep"
            case .weakGenericAdd:
                return "weak-generic-add"
            }
        }
    }

    private struct ConsolidationSuppression {
        let suggestionID: String
        let reason: String
        let keptSuggestionID: String
    }

    private func sortTime(for suggestion: SmartSetupSuggestion) -> Double {
        suggestion.sourceTimeRange?.startTime ?? suggestion.sourceEvents.first?.timestamp ?? 0
    }

    private func consolidatedSuggestions(
        from suggestions: [SmartSetupSuggestion],
        contentCoordinateSize: CGSize
    ) -> [SmartSetupSuggestion] {
        debugSuggestionConsolidationInputs(suggestions, contentCoordinateSize: contentCoordinateSize)
        debugSuggestionConsolidationPairs(suggestions, contentCoordinateSize: contentCoordinateSize)

        guard suggestions.count > 1 else {
            debugSuggestionConsolidation(before: suggestions.count, after: suggestions.count, suppressions: [])
            return suggestions
        }

        let rankedSuggestions = suggestions.sorted { lhs, rhs in
            let lhsValue = consolidationValue(for: lhs)
            let rhsValue = consolidationValue(for: rhs)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            if sortTime(for: lhs) != sortTime(for: rhs) {
                return sortTime(for: lhs) < sortTime(for: rhs)
            }
            return lhs.suggestionID < rhs.suggestionID
        }

        var acceptedSuggestions: [SmartSetupSuggestion] = []
        var acceptedSuggestionIDs = Set<String>()
        var suppressions: [ConsolidationSuppression] = []

        for suggestion in rankedSuggestions {
            if let suppressionReason = qualitySuppressionReason(for: suggestion, acceptedSuggestions: acceptedSuggestions) {
                suppressions.append(
                    ConsolidationSuppression(
                        suggestionID: suggestion.suggestionID,
                        reason: suppressionReason.reason,
                        keptSuggestionID: "quality-filter"
                    )
                )
                continue
            }

            if let duplicate = acceptedSuggestions.compactMap({ acceptedSuggestion -> (SmartSetupSuggestion, ConsolidationRelation)? in
                guard let relation = consolidationRelation(
                    between: acceptedSuggestion,
                    and: suggestion,
                    contentCoordinateSize: contentCoordinateSize
                ) else {
                    return nil
                }
                return (acceptedSuggestion, relation)
            }).first {
                suppressions.append(
                    ConsolidationSuppression(
                        suggestionID: suggestion.suggestionID,
                        reason: duplicate.1.reason,
                        keptSuggestionID: duplicate.0.suggestionID
                    )
                )
                continue
            }

            acceptedSuggestions.append(suggestion)
            acceptedSuggestionIDs.insert(suggestion.suggestionID)
        }

        let result = suggestions.filter { acceptedSuggestionIDs.contains($0.suggestionID) }
        debugSuggestionConsolidation(before: suggestions.count, after: result.count, suppressions: suppressions)
        return result
    }

    private func consolidationValue(for suggestion: SmartSetupSuggestion) -> Double {
        let intentPriority = Double(consolidationIntent(for: suggestion).rawValue) * 0.20
        let sourceEventBoost = min(Double(suggestion.sourceEvents.count) * 0.01, 0.05)
        let existingAdjustmentBoost = isExistingEditAdjustment(suggestion) ? 0.18 : 0
        return opportunityValue(for: suggestion) + intentPriority + sourceEventBoost + existingAdjustmentBoost
    }

    private func qualitySuppressionReason(
        for suggestion: SmartSetupSuggestion,
        acceptedSuggestions: [SmartSetupSuggestion]
    ) -> ConsolidationRelation? {
        if providerIDIsNewProposalKeep(suggestion) {
            return .newProposalCannotBeKeep
        }

        let intent = consolidationIntent(for: suggestion)
        if intent == .keep,
           suggestion.providerID == "existing-edits",
           isPlainKeepSuggestion(suggestion),
           !hasStrongKeepEvidence(suggestion) {
            return .weakKeep
        }

        if isLowValueGenericClick(suggestion) {
            return .genericClickLowValue
        }

        if intent == .add,
           normalizedContextLabel(for: suggestion) == nil,
           sidebarNavigationKey(for: suggestion) == nil,
           suggestion.sourceEvents.isEmpty,
           suggestion.score.value < 0.75 {
            return .weakGenericAdd
        }

        return nil
    }

    private func providerIDIsNewProposalKeep(_ suggestion: SmartSetupSuggestion) -> Bool {
        guard suggestion.providerID != "existing-edits",
              existingSourceMarkerKey(for: suggestion) == nil,
              let title = suggestion.userTitle?.lowercased() else {
            return false
        }
        return title.hasPrefix("keep this")
    }

    private func isLowValueGenericClick(_ suggestion: SmartSetupSuggestion) -> Bool {
        suggestion.providerID == "clicks"
            && suggestion.sourceEvents.count <= 1
            && normalizedContextLabel(for: suggestion) == nil
            && sidebarNavigationKey(for: suggestion) == nil
            && suggestion.score.value <= 0.78
    }

    private func isPlainKeepSuggestion(_ suggestion: SmartSetupSuggestion) -> Bool {
        guard let title = suggestion.userTitle?.lowercased() else { return false }
        return title == "keep this zoom"
            || title == "keep this effect"
            || title == "keep this focus hold"
    }

    private func hasStrongKeepEvidence(_ suggestion: SmartSetupSuggestion) -> Bool {
        suggestion.score.value >= 0.90
            && suggestion.sourceEvents.count >= 2
            && suggestion.reasons.contains(.denseActivity)
            && suggestion.reasons.contains(.click)
    }

    private func consolidationIntent(for suggestion: SmartSetupSuggestion) -> ConsolidationIntent {
        if case .zoomAdjustment = suggestion.proposal {
            return .adjust
        }

        guard suggestion.providerID == "existing-edits" else {
            return .add
        }

        let visibleText = "\(suggestion.userTitle ?? "") \(suggestion.userReason ?? "")"
            .lowercased()

        if visibleText.contains("consider removing") || visibleText.contains("remove this") {
            return .remove
        }
        if visibleText.contains("extend this")
            || visibleText.contains("expand this")
            || visibleText.contains("resize this")
            || visibleText.contains("move this")
            || visibleText.contains("shorten this")
            || visibleText.contains("refine this")
            || visibleText.contains("adjust this")
            || visibleText.contains("tighten this") {
            return .adjust
        }
        if visibleText.contains("keep this") {
            return .keep
        }
        if visibleText.contains("add ") {
            return .add
        }

        return .fallback
    }

    private func consolidationRelation(
        between acceptedSuggestion: SmartSetupSuggestion,
        and candidate: SmartSetupSuggestion,
        contentCoordinateSize: CGSize
    ) -> ConsolidationRelation? {
        guard acceptedSuggestion.suggestionID != candidate.suggestionID else {
            return .duplicateExistingMarker
        }

        if let crossMarkerRelation = crossMarkerExistingEffectAdjustmentRelation(
            between: acceptedSuggestion,
            and: candidate
        ) {
            return crossMarkerRelation
        }

        if let acceptedMarkerKey = existingSourceMarkerKey(for: acceptedSuggestion),
           acceptedMarkerKey == existingSourceMarkerKey(for: candidate) {
            return .duplicateExistingMarker
        }

        if sourceEventsOverlap(acceptedSuggestion.sourceEvents, candidate.sourceEvents, contentCoordinateSize: contentCoordinateSize),
           visibleOpportunityTimesCompete(acceptedSuggestion, candidate) {
            return .duplicateInteractionCluster
        }

        if sidebarNavigationKey(for: acceptedSuggestion) != nil,
           sidebarNavigationKey(for: candidate) != nil,
           sameIntent(acceptedSuggestion, candidate, intent: .add),
           existingSourceMarkerKey(for: acceptedSuggestion) == nil,
           existingSourceMarkerKey(for: candidate) == nil,
           abs(sortTime(for: acceptedSuggestion) - sortTime(for: candidate)) <= 3.0 {
            return .genericAddDuplicate
        }

        if let acceptedLabel = normalizedContextLabel(for: acceptedSuggestion),
           let candidateLabel = normalizedContextLabel(for: candidate),
           contextLabelsCompete(acceptedLabel, candidateLabel),
           intentsCompete(acceptedSuggestion, candidate),
           proposalsCompete(acceptedSuggestion, candidate),
           abs(sortTime(for: acceptedSuggestion) - sortTime(for: candidate)) <= 3.0 {
            return .duplicateContextLabel
        }

        if let editorialRelation = editorialVisibleMomentRelation(
            between: acceptedSuggestion,
            and: candidate,
            contentCoordinateSize: contentCoordinateSize
        ) {
            return editorialRelation
        }

        guard canConsolidateVisibleMoment(acceptedSuggestion, candidate),
              visibleOpportunityTimesCompete(acceptedSuggestion, candidate),
              opportunityPointsAreNear(acceptedSuggestion, candidate, contentCoordinateSize: contentCoordinateSize, tolerance: finalOpportunityDistanceTolerance) else {
            return nil
        }

        return .duplicateVisualMoment
    }

    private func canConsolidateVisibleMoment(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        if lhs.providerID == "existing-edits", rhs.providerID == "existing-edits" {
            return false
        }

        if visibleOpportunityCategory(for: lhs) == visibleOpportunityCategory(for: rhs) {
            return true
        }

        let lhsIntent = consolidationIntent(for: lhs)
        let rhsIntent = consolidationIntent(for: rhs)
        return lhsIntent == .add || rhsIntent == .add
    }

    private func editorialVisibleMomentRelation(
        between acceptedSuggestion: SmartSetupSuggestion,
        and candidate: SmartSetupSuggestion,
        contentCoordinateSize: CGSize
    ) -> ConsolidationRelation? {
        guard editorialTimesCompete(acceptedSuggestion, candidate),
              attentionSuggestionsCompete(acceptedSuggestion, candidate),
              opportunityPointsAreNear(acceptedSuggestion, candidate, contentCoordinateSize: contentCoordinateSize, tolerance: 0.22) else {
            return nil
        }

        let acceptedIntent = consolidationIntent(for: acceptedSuggestion)
        let candidateIntent = consolidationIntent(for: candidate)
        guard acceptedIntent == .adjust || acceptedIntent == .add || candidateIntent == .adjust || candidateIntent == .add else {
            return nil
        }

        if isExistingEffectAdjustment(acceptedSuggestion), candidate.providerID != "existing-edits" {
            return .competesWithExistingEffectAdjustment
        }
        if isExistingEffectAdjustment(candidate), acceptedSuggestion.providerID != "existing-edits" {
            return .competesWithExistingEffectAdjustment
        }

        if isExistingEditAdjustment(acceptedSuggestion), candidate.providerID != "existing-edits" {
            return .competesWithExistingEditAdjustment
        }
        if isExistingEditAdjustment(candidate), acceptedSuggestion.providerID != "existing-edits" {
            return .competesWithExistingEditAdjustment
        }

        if (acceptedIntent == .adjust && candidateIntent == .add)
            || (acceptedIntent == .add && candidateIntent == .adjust) {
            return .sameVisibleMoment
        }

        if acceptedIntent == .add, candidateIntent == .add {
            return .genericAddDuplicate
        }

        guard acceptedIntent == .adjust, candidateIntent == .adjust else {
            return nil
        }

        if effectAndZoomAdjustmentsCanCoexist(acceptedSuggestion, candidate) {
            return nil
        }
        return .sameVisibleMoment
    }

    private func crossMarkerExistingEffectAdjustmentRelation(
        between lhs: SmartSetupSuggestion,
        and rhs: SmartSetupSuggestion
    ) -> ConsolidationRelation? {
        guard crossMarkerEditorialCandidate(lhs, rhs),
              overlapStrength(lhs.sourceTimeRange, rhs.sourceTimeRange) >= 0.50 else {
            return nil
        }

        if isExistingEffectAdjustment(lhs), isGeneratedZoomAdjustment(rhs) {
            return .competesWithExistingEffectAdjustment
        }
        if isExistingEffectAdjustment(rhs), isGeneratedZoomAdjustment(lhs) {
            return .competesWithExistingEffectAdjustment
        }

        return nil
    }

    private func crossMarkerEditorialCandidate(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        guard existingSourceMarkerKey(for: lhs) != existingSourceMarkerKey(for: rhs),
              editorialTimesCompete(lhs, rhs),
              attentionSuggestionsCompete(lhs, rhs) else {
            return false
        }

        let lhsIntent = consolidationIntent(for: lhs)
        let rhsIntent = consolidationIntent(for: rhs)
        return lhsIntent == .adjust || lhsIntent == .add || rhsIntent == .adjust || rhsIntent == .add
    }

    private func editorialTimesCompete(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        if abs(sortTime(for: lhs) - sortTime(for: rhs)) <= 1.5 {
            return true
        }
        return rangesOverlapSubstantially(lhs.sourceTimeRange, rhs.sourceTimeRange)
    }

    private func attentionSuggestionsCompete(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        let lhsFamily = proposalFamily(for: lhs)
        let rhsFamily = proposalFamily(for: rhs)
        return (lhsFamily == "zoom" || lhsFamily == "effect")
            && (rhsFamily == "zoom" || rhsFamily == "effect")
    }

    private func isExistingEditAdjustment(_ suggestion: SmartSetupSuggestion) -> Bool {
        suggestion.providerID == "existing-edits" && consolidationIntent(for: suggestion) == .adjust
    }

    private func isExistingEffectAdjustment(_ suggestion: SmartSetupSuggestion) -> Bool {
        isExistingEditAdjustment(suggestion)
            && suggestion.suggestionID.hasPrefix("existing-effect-")
            && proposalFamily(for: suggestion) == "effect"
    }

    private func isGeneratedZoomAdjustment(_ suggestion: SmartSetupSuggestion) -> Bool {
        guard suggestion.providerID != "existing-edits" else { return false }
        if case .zoomAdjustment = suggestion.proposal {
            return true
        }
        return false
    }

    private func effectAndZoomAdjustmentsCanCoexist(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        guard proposalFamily(for: lhs) != proposalFamily(for: rhs) else { return false }
        guard lhs.providerID == "existing-edits", rhs.providerID == "existing-edits" else { return false }
        guard lhs.score.value >= 0.90, rhs.score.value >= 0.90 else { return false }
        return !rangesOverlapSubstantially(lhs.sourceTimeRange, rhs.sourceTimeRange)
    }

    private func sameIntent(
        _ lhs: SmartSetupSuggestion,
        _ rhs: SmartSetupSuggestion,
        intent: ConsolidationIntent
    ) -> Bool {
        consolidationIntent(for: lhs) == intent && consolidationIntent(for: rhs) == intent
    }

    private func intentsCompete(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        let lhsIntent = consolidationIntent(for: lhs)
        let rhsIntent = consolidationIntent(for: rhs)
        return lhsIntent == rhsIntent || lhsIntent == .adjust || rhsIntent == .adjust
    }

    private func proposalsCompete(_ lhs: SmartSetupSuggestion, _ rhs: SmartSetupSuggestion) -> Bool {
        proposalFamily(for: lhs) == proposalFamily(for: rhs)
            || consolidationIntent(for: lhs) == .add
            || consolidationIntent(for: rhs) == .add
    }

    private func proposalFamily(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
        case .zoom, .zoomAdjustment:
            return "zoom"
        case .effect, .regionTighten:
            return "effect"
        }
    }

    private func existingSourceMarkerKey(for suggestion: SmartSetupSuggestion) -> String? {
        if suggestion.providerID == "existing-edits" {
            if suggestion.suggestionID.hasPrefix("existing-effect-") {
                return suggestion.suggestionID
                    .replacingOccurrences(of: "existing-effect-", with: "effect:")
            }
            if suggestion.suggestionID.hasPrefix("existing-zoom-") {
                return suggestion.suggestionID
                    .replacingOccurrences(of: "existing-zoom-", with: "zoom:")
            }
        }

        if case .zoomAdjustment(let proposal) = suggestion.proposal,
           let markerID = proposal.targetMarkerIDs.first {
            return "zoom:\(markerID)"
        }

        return nil
    }

    private func sourceEventsOverlap(
        _ lhs: [SmartSetupSourceEventReference],
        _ rhs: [SmartSetupSourceEventReference],
        contentCoordinateSize: CGSize
    ) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }

        let lhsKeys = Set(lhs.map(sourceEventKey))
        let rhsKeys = Set(rhs.map(sourceEventKey))
        if !lhsKeys.isDisjoint(with: rhsKeys) {
            return true
        }

        let safeWidth = max(contentCoordinateSize.width, 1)
        let safeHeight = max(contentCoordinateSize.height, 1)
        return lhs.contains { lhsEvent in
            rhs.contains { rhsEvent in
                guard abs(lhsEvent.timestamp - rhsEvent.timestamp) <= 0.45 else { return false }
                let deltaX = (lhsEvent.x / safeWidth) - (rhsEvent.x / safeWidth)
                let deltaY = (lhsEvent.y / safeHeight) - (rhsEvent.y / safeHeight)
                return (deltaX * deltaX + deltaY * deltaY).squareRoot() <= 0.08
            }
        }
    }

    private func sourceEventKey(for event: SmartSetupSourceEventReference) -> String {
        let timeKey = Int((event.timestamp * 100).rounded())
        let xKey = Int(event.x.rounded())
        let yKey = Int(event.y.rounded())
        return "\(event.type.rawValue)-\(timeKey)-\(xKey)-\(yKey)"
    }

    private func opportunityPointsAreNear(
        _ lhs: SmartSetupSuggestion,
        _ rhs: SmartSetupSuggestion,
        contentCoordinateSize: CGSize,
        tolerance: Double
    ) -> Bool {
        guard let lhsPoint = normalizedOpportunityPoint(for: lhs, contentCoordinateSize: contentCoordinateSize),
              let rhsPoint = normalizedOpportunityPoint(for: rhs, contentCoordinateSize: contentCoordinateSize) else {
            return true
        }

        let deltaX = lhsPoint.x - rhsPoint.x
        let deltaY = lhsPoint.y - rhsPoint.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot() <= tolerance
    }

    private func sidebarNavigationKey(for suggestion: SmartSetupSuggestion) -> String? {
        let text = "\(suggestion.userTitle ?? "") \(suggestion.userReason ?? "")"
            .lowercased()
        if text.contains("sidebar")
            || text.contains("side panel")
            || text.contains("navigation")
            || text.contains("nav ") {
            return "sidebar-navigation"
        }
        return nil
    }

    private func normalizedContextLabel(for suggestion: SmartSetupSuggestion) -> String? {
        guard let title = suggestion.userTitle?.lowercased() else { return nil }
        let prefixes = [
            "add a zoom hold covering ",
            "add a zoom hold through ",
            "add a short zoom hold around ",
            "add a short zoom hold for ",
            "add a short focus hold around ",
            "add a short focus hold for ",
            "add a focus hold around ",
            "add a focus hold through ",
            "add a focus hold for ",
            "add a brief zoom hold for ",
            "add a small click emphasis here",
            "add a subtle focus effect to ",
            "add a subtle focus effect around ",
            "add a focus effect to ",
            "add subtle emphasis during ",
            "add extra attention to ",
            "add emphasis around ",
            "add emphasis to ",
            "add focus around ",
            "add focus to ",
            "extend this zoom hold around ",
            "resize this effect region around ",
            "move this zoom around ",
            "keep this zoom around ",
            "keep this effect around ",
            "consider removing this zoom around ",
            "consider removing this effect around "
        ]

        var label = title
        for prefix in prefixes where label.hasPrefix(prefix) {
            label.removeFirst(prefix.count)
            break
        }

        let punctuation = CharacterSet.alphanumerics.union(.whitespaces).inverted
        label = label
            .components(separatedBy: punctuation)
            .joined(separator: " ")

        let ignoredWords: Set<String> = [
            "a", "an", "and", "around", "brief", "clearer", "click", "clicks",
            "covering", "effect", "emphasis", "focus", "for", "hold", "if",
            "in", "it", "moment", "region", "short", "small", "subtle",
            "the", "these", "this", "through", "to", "zoom"
        ]
        let tokens = label
            .split(separator: " ")
            .map(String.init)
            .filter { !ignoredWords.contains($0) }

        guard !tokens.isEmpty else { return nil }
        let normalizedLabel = tokens.joined(separator: " ")
        let genericLabels: Set<String> = [
            "action", "active content", "area", "content", "information",
            "interaction", "screen", "step", "transition"
        ]
        guard !genericLabels.contains(normalizedLabel) else { return nil }
        return normalizedLabel
    }

    private func contextLabelsCompete(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return min(lhs.count, rhs.count) >= 4
        }

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }
        let sharedCount = lhsTokens.intersection(rhsTokens).count
        return sharedCount >= 2 || Double(sharedCount) / Double(min(lhsTokens.count, rhsTokens.count)) >= 0.75
    }

    private func normalizedTimeKey(for suggestion: SmartSetupSuggestion) -> String {
        String(Int((sortTime(for: suggestion) * 2).rounded()))
    }

    private func timeRangeText(for suggestion: SmartSetupSuggestion) -> String {
        guard let range = suggestion.sourceTimeRange else {
            return String(format: "%.2f", sortTime(for: suggestion))
        }
        return String(format: "%.2f-%.2f", range.startTime, range.endTime)
    }

    private func proposalTypeText(for suggestion: SmartSetupSuggestion) -> String {
        switch suggestion.proposal {
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

    private func relationMissReason(
        lhs: SmartSetupSuggestion,
        rhs: SmartSetupSuggestion,
        contentCoordinateSize: CGSize
    ) -> String {
        let timeDelta = abs(sortTime(for: lhs) - sortTime(for: rhs))
        if timeDelta > 3.0 {
            return "outside-near-time-window"
        }
        if crossMarkerEditorialCandidate(lhs, rhs) {
            return "cross-marker-editorial-not-strong-enough"
        }
        if existingSourceMarkerKey(for: lhs) != existingSourceMarkerKey(for: rhs) {
            return "different-existing-marker"
        }
        if sidebarNavigationKey(for: lhs) != sidebarNavigationKey(for: rhs) {
            return "different-sidebar-nav-key"
        }
        let lhsLabel = normalizedContextLabel(for: lhs)
        let rhsLabel = normalizedContextLabel(for: rhs)
        if lhsLabel == nil || rhsLabel == nil {
            return "missing-context-label"
        }
        if let lhsLabel, let rhsLabel, !contextLabelsCompete(lhsLabel, rhsLabel) {
            return "different-context-label"
        }
        if !sourceEventsOverlap(lhs.sourceEvents, rhs.sourceEvents, contentCoordinateSize: contentCoordinateSize) {
            return "different-source-events"
        }
        if !opportunityPointsAreNear(lhs, rhs, contentCoordinateSize: contentCoordinateSize, tolerance: finalOpportunityDistanceTolerance) {
            return "different-screen-area"
        }
        return "different-category-or-intent"
    }

    private func debugSuggestionConsolidationInputs(
        _ suggestions: [SmartSetupSuggestion],
        contentCoordinateSize: CGSize
    ) {
        #if DEBUG
        for suggestion in suggestions {
            print(
                "[SuggestionConsolidation] input suggestionID=\(suggestion.suggestionID) providerID=\(suggestion.providerID) intent=\(consolidationIntent(for: suggestion)) title=\"\(suggestion.userTitle ?? "")\" timeRange=\(timeRangeText(for: suggestion)) sourceEvents=\(suggestion.sourceEvents.count) timeKey=\(normalizedTimeKey(for: suggestion)) labelKey=\(normalizedContextLabel(for: suggestion) ?? "none") sidebarKey=\(sidebarNavigationKey(for: suggestion) ?? "none") markerKey=\(existingSourceMarkerKey(for: suggestion) ?? "none") proposal=\(proposalTypeText(for: suggestion)) score=\(String(format: "%.3f", suggestion.score.value))"
            )
        }
        #endif
    }

    private func debugSuggestionConsolidationPairs(
        _ suggestions: [SmartSetupSuggestion],
        contentCoordinateSize: CGSize
    ) {
        #if DEBUG
        guard suggestions.count > 1 else { return }
        for lhsIndex in suggestions.indices {
            for rhsIndex in suggestions.index(after: lhsIndex)..<suggestions.endIndex {
                let lhs = suggestions[lhsIndex]
                let rhs = suggestions[rhsIndex]
                guard abs(sortTime(for: lhs) - sortTime(for: rhs)) <= 3.0 else { continue }

                let lhsLabel = normalizedContextLabel(for: lhs)
                let rhsLabel = normalizedContextLabel(for: rhs)
                let sameContextLabel = lhsLabel.flatMap { label in
                    rhsLabel.map { contextLabelsCompete(label, $0) }
                } ?? false
                let sameSidebar = sidebarNavigationKey(for: lhs) != nil
                    && sidebarNavigationKey(for: lhs) == sidebarNavigationKey(for: rhs)
                let sameMarker = existingSourceMarkerKey(for: lhs) != nil
                    && existingSourceMarkerKey(for: lhs) == existingSourceMarkerKey(for: rhs)
                let sameEvents = sourceEventsOverlap(lhs.sourceEvents, rhs.sourceEvents, contentCoordinateSize: contentCoordinateSize)
                let overlap = visibleOpportunityTimesCompete(lhs, rhs)
                let relation = consolidationRelation(between: lhs, and: rhs, contentCoordinateSize: contentCoordinateSize)
                let crossMarkerCandidate = crossMarkerEditorialCandidate(lhs, rhs)
                let lhsRealExistingEffectAdjust = isExistingEffectAdjustment(lhs)
                let rhsGeneratedZoomAdjustment = isGeneratedZoomAdjustment(rhs)
                let strength = overlapStrength(lhs.sourceTimeRange, rhs.sourceTimeRange)
                print(
                    "[SuggestionConsolidation] pair lhs=\"\(lhs.userTitle ?? lhs.suggestionID)\" rhs=\"\(rhs.userTitle ?? rhs.suggestionID)\" timeOverlap=\(overlap) sameContextLabel=\(sameContextLabel) sameSidebarNav=\(sameSidebar) sameMarker=\(sameMarker) sameSourceEvents=\(sameEvents) crossMarkerEditorialCandidate=\(crossMarkerCandidate) lhsRealExistingEffectAdjust=\(lhsRealExistingEffectAdjust) rhsGeneratedZoomAdjustment=\(rhsGeneratedZoomAdjustment) overlapStrength=\(String(format: "%.3f", strength)) duplicateReason=\(relation?.reason ?? "none") finalDuplicateReason=\(relation?.reason ?? "none") notDuplicateReason=\(relation == nil ? relationMissReason(lhs: lhs, rhs: rhs, contentCoordinateSize: contentCoordinateSize) : "matched")"
                )
            }
        }
        #endif
    }

    private func debugSuggestionConsolidation(
        before: Int,
        after: Int,
        suppressions: [ConsolidationSuppression]
    ) {
        #if DEBUG
        print("[SuggestionConsolidation] before=\(before) after=\(after)")
        print("[SuggestionConsolidation] after=\(after)")
        for suppression in suppressions {
            print(
                "[SuggestionConsolidation] suppressed suggestionID=\(suppression.suggestionID) reason=\(suppression.reason) kept=\(suppression.keptSuggestionID)"
            )
        }
        #endif
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
                "Add a zoom hold covering this \(eventCount)-step interaction",
                "Add a short focus hold for this \(eventCount)-step interaction",
                "Add a zoom hold through this short interaction"
            ])
            representative.userReason = stableSuggestionChoice(seed: "click-cluster-opportunity-reason-\(key)", from: [
                "Viewers may need more time to follow these steps.",
                "This interaction is easy to miss at the current pace.",
                "The sequence may move too quickly without a brief hold."
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
        case "existing-edits":
            return max(suggestion.score.value, 0.80)
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
        case "existing-edits":
            return 0.08
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

        return overlapStrength(lhs, rhs) >= substantialOverlapRatio
    }

    private func overlapStrength(_ lhs: SmartSetupSourceTimeRange?, _ rhs: SmartSetupSourceTimeRange?) -> Double {
        guard let lhs, let rhs else { return 0 }

        let overlapStart = max(lhs.startTime, rhs.startTime)
        let overlapEnd = min(lhs.endTime, rhs.endTime)
        let overlapDuration = max(overlapEnd - overlapStart, 0)
        guard overlapDuration > 0 else { return 0 }

        let lhsDuration = max(lhs.endTime - lhs.startTime, 0.001)
        let rhsDuration = max(rhs.endTime - rhs.startTime, 0.001)
        return overlapDuration / min(lhsDuration, rhsDuration)
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
