import AppKit
import SwiftUI

private struct TimelinePlayheadHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let sideY = rect.height * 0.34
        let neckY = rect.maxY

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + sideY))
        path.addLine(to: CGPoint(x: rect.midX, y: neckY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + sideY))
        path.closeSubpath()
        return path
    }
}

extension ContentView {
    @ViewBuilder
    func timelineToolbar(
        summary: RecordingInspectionSummary,
        selectedMarker: ZoomPlanItem?,
        showsNoZoomFallbackControls: Bool,
        hasSelectedMarker: Bool,
        canEditClickFocusMarkers: Bool,
        isPlacingClickFocus: Bool,
        isDrawingNoZoomOverflowRegion: Bool,
        isTimelineScrubSnappingEnabled: Bool,
        onToggleAddClickFocus: @escaping () -> Void,
        onDeleteSelectedMarker: @escaping () -> Void,
        onSelectNoZoomFallbackMode: @escaping (NoZoomFallbackMode) -> Void,
        onToggleOverflowRegion: @escaping () -> Void,
        onToggleTimelineScrubSnapping: @escaping () -> Void
    ) -> some View {
        TimelineToolbarView(
            hasSelectedMarker: hasSelectedMarker,
            canEditClickFocusMarkers: canEditClickFocusMarkers,
            isPlacingClickFocus: isPlacingClickFocus,
            selectedMarker: selectedMarker,
            showsNoZoomFallbackControls: showsNoZoomFallbackControls,
            isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion,
            isTimelineScrubSnappingEnabled: isTimelineScrubSnappingEnabled,
            onToggleAddClickFocus: onToggleAddClickFocus,
            onDeleteSelectedMarker: onDeleteSelectedMarker,
            onSelectNoZoomFallbackMode: onSelectNoZoomFallbackMode,
            onToggleOverflowRegion: onToggleOverflowRegion,
            onToggleTimelineScrubSnapping: onToggleTimelineScrubSnapping
        )
    }

    func timelineCanvasView(
        width: CGFloat,
        duration: Double,
        visibleRange: TimelineVisibleRange,
        trackCenterY: CGFloat,
        segmentOriginY: CGFloat,
        editorMode: ReviewEditorMode,
        segmentLayouts: [TimelineSegmentLayout],
        effectLayouts: [EffectTimelineSegmentLayout],
        timelineInteractionSuppressed: Bool,
        selectedZoomMarkerID: String?,
        hoveredTimelineMarkerID: String?,
        hoveredTimelinePhase: MarkerTimingPhase?,
        hoveredTooltipMarker: ZoomPlanItem?,
        hoveredTooltipMarkerNumber: Int?,
        hoveredTooltipAnchor: CGPoint?,
        hoveredEffectTimelineMarkerID: String?,
        selectedEffectMarkerID: String?,
        activeEffectHoldPoint: ActiveEffectHoldPoint?,
        hoveredEffectTooltipMarker: EffectPlanItem?,
        hoveredEffectTooltipMarkerNumber: Int?,
        hoveredEffectTooltipAnchor: CGPoint?,
        playheadX: CGFloat?,
        isDraggingTimeline: Bool,
        displayedPhaseProvider: @escaping (ZoomPlanItem) -> MarkerTimingPhase?,
        zoomPlaybackHighlightProvider: @escaping (ZoomPlanItem) -> Bool,
        effectPlaybackHighlightProvider: @escaping (EffectPlanItem) -> Bool,
        onTimelineHoverChanged: @escaping (String, Bool, MarkerTimingPhase?, CGPoint) -> Void,
        onTimelineTap: @escaping (String) -> Void,
        onEffectHoverChanged: @escaping (String, Bool, CGPoint?) -> Void,
        onEffectSelect: @escaping (String) -> Void
    ) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(flowTrackTheme.timelineRailColor(for: colorScheme))
                .frame(height: 24)
                .position(x: width / 2, y: trackCenterY)

            if isDraggingTimeline {
                Capsule()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(height: 24)
                    .position(x: width / 2, y: trackCenterY)
            }

            if editorMode == .zoomAndClicks {
                ForEach(effectLayouts) { layout in
                    referenceTimelineSegment(
                        startRatio: layout.startRatio,
                        eventRatio: layout.eventRatio,
                        endRatio: layout.endRatio,
                        lane: layout.lane,
                        width: width,
                        verticalOrigin: segmentOriginY,
                        tint: FlowTrackAccent.color(for: .effects, theme: flowTrackTheme),
                        opacity: 0.34
                    )
                }

                ForEach(segmentLayouts) { layout in
                    let displayedPhase = displayedPhaseProvider(layout.marker)
                    timelineSegment(
                        layout: layout,
                        width: width,
                        duration: duration,
                        verticalOrigin: segmentOriginY,
                        isSelected: selectedZoomMarkerID == layout.marker.id,
                        isEnabled: layout.marker.enabled,
                        activePhase: displayedPhase,
                        visibleRange: visibleRange,
                        theme: flowTrackTheme,
                        interactionSuppressed: timelineInteractionSuppressed,
                        isHovered: !timelineInteractionSuppressed && hoveredTimelineMarkerID == layout.marker.id,
                        hoveredTimelineMarkerID: hoveredTimelineMarkerID,
                        hoveredTimelinePhase: hoveredTimelinePhase,
                        onHoverChanged: { isHovering, phase, anchor in
                            onTimelineHoverChanged(layout.marker.id, isHovering, phase, anchor)
                        },
                        onTap: {
                            onTimelineTap(layout.marker.id)
                        }
                    )
                }
            } else {
                ForEach(segmentLayouts) { layout in
                    referenceTimelineSegment(
                        startRatio: layout.startRatio,
                        eventRatio: layout.eventRatio,
                        endRatio: layout.endRatio,
                        lane: layout.lane,
                        width: width,
                        verticalOrigin: segmentOriginY,
                        tint: FlowTrackAccent.color(for: .zoomAndClicks, theme: flowTrackTheme),
                        opacity: 0.32
                    )
                }

                EffectsTimelineTrackView(
                    effectLayouts: effectLayouts,
                    width: width,
                    verticalOrigin: segmentOriginY,
                    timelineInteractionSuppressed: timelineInteractionSuppressed,
                    hoveredEffectTimelineMarkerID: hoveredEffectTimelineMarkerID,
                    selectedEffectMarkerID: selectedEffectMarkerID,
                    activeEffectHoldPoint: activeEffectHoldPoint,
                    hoveredTooltipMarker: hoveredEffectTooltipMarker,
                    hoveredTooltipMarkerNumber: hoveredEffectTooltipMarkerNumber,
                    hoveredTooltipAnchor: hoveredEffectTooltipAnchor,
                    playbackHighlightProvider: effectPlaybackHighlightProvider,
                    onHoverChanged: onEffectHoverChanged,
                    onSelect: onEffectSelect
                )
            }

            if !timelineInteractionSuppressed,
               let hoveredTooltipMarker,
               let hoveredTooltipMarkerNumber,
               let hoveredTooltipAnchor {
                timelineMarkerTooltipOverlay(
                    markerID: hoveredTooltipMarker.id,
                    markerNumber: hoveredTooltipMarkerNumber,
                    marker: hoveredTooltipMarker,
                    phase: hoveredTimelinePhase,
                    hoveredTimelineMarkerID: hoveredTimelineMarkerID,
                    anchor: hoveredTooltipAnchor,
                    width: width
                )
            }

            if let playheadX {
                timelinePlayheadView(
                    playheadX: playheadX,
                    width: width,
                    trackCenterY: trackCenterY,
                    isDraggingTimeline: isDraggingTimeline
                )
            }
        }
    }

    func timelineRulerView(
        visibleRange: TimelineVisibleRange,
        width: CGFloat,
        topY: CGFloat
    ) -> some View {
        let ticks = timelineRulerTicks(visibleRange: visibleRange, width: width)

        return ZStack(alignment: .topLeading) {
            ForEach(ticks) { tick in
                let x = timelineX(for: tick.time, visibleRange: visibleRange, width: width)

                Rectangle()
                    .fill(tick.isMajor ? flowTrackTheme.timelineRuler : flowTrackTheme.timelineRuler.opacity(0.58))
                    .frame(width: 1, height: tick.isMajor ? 10 : 5)
                    .position(x: x, y: topY + (tick.isMajor ? 17 : 19.5))

                if let label = tick.label {
                    let labelInset: CGFloat = 22
                    let labelX = min(max(x, labelInset), max(width - labelInset, labelInset))

                    Text(label)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(flowTrackTheme.timelineRuler)
                        .fixedSize()
                        .position(x: labelX, y: topY + 6)
                }
            }
        }
        .frame(width: width, height: 24, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    func timelinePlayheadView(
        playheadX: CGFloat,
        width: CGFloat,
        trackCenterY: CGFloat,
        isDraggingTimeline: Bool
    ) -> some View {
        let playheadColor = flowTrackTheme.timelinePlayhead
        let separationColor = Color(nsColor: .controlBackgroundColor)

        return ZStack {
            Rectangle()
                .fill(separationColor)
                .frame(width: 4, height: 82)
                .offset(y: -5)

            TimelinePlayheadHandleShape()
                .fill(separationColor)
                .frame(width: 28, height: 24)
                .offset(y: -29)

            TimelinePlayheadHandleShape()
                .fill(playheadColor.opacity(0.86))
                .frame(width: 26, height: 22)
                .offset(y: -29)

            Rectangle()
                .fill(playheadColor)
                .frame(width: 2, height: 82)
                .offset(y: -5)

            Rectangle()
                .fill(playheadColor.opacity(0.001))
                .frame(width: 34, height: 34)
                .offset(y: -28)
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .frame(width: 34, height: 98)
        .shadow(color: Color.black.opacity(isDraggingTimeline ? 0.10 : 0.05), radius: isDraggingTimeline ? 1 : 0.5, x: 0, y: 0.5)
        .position(
            x: playheadX,
            y: trackCenterY - 2
        )
    }

    func timelineInstructionText(
        editorMode: ReviewEditorMode,
        isDrawingEffectFocusRegion: Bool,
        isDrawingNoZoomOverflowRegion: Bool
    ) -> String {
        isDrawingEffectFocusRegion
        ? "←/→/↑/↓ to nudge the focus region, ⌥ + Arrow for 10x speed"
        : editorMode == .effects
        ? "Zoom & Click bars are shown as grey reference guides while editing effects."
        : isDrawingNoZoomOverflowRegion
        ? "←/→/↑/↓ to nudge the overflow region, ⌥ + Arrow for 10x speed"
        : "Click a marker to preview it, click empty timeline to clear selection, ←/→ to nudge one frame"
    }

    func timelineInstructionView(
        editorMode: ReviewEditorMode,
        isDrawingEffectFocusRegion: Bool,
        isDrawingNoZoomOverflowRegion: Bool
    ) -> some View {
        Text(
            timelineInstructionText(
                editorMode: editorMode,
                isDrawingEffectFocusRegion: isDrawingEffectFocusRegion,
                isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion
            )
        )
        .font(.system(size: 10, weight: .light))
        .foregroundStyle(.secondary)
    }

    func timelineFooterView(
        visibleRange: TimelineVisibleRange,
        editorMode: ReviewEditorMode,
        isDrawingEffectFocusRegion: Bool,
        isDrawingNoZoomOverflowRegion: Bool
    ) -> some View {
        ZStack {
            HStack {
                Text(timecodeString(for: visibleRange.startTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timecodeString(for: visibleRange.endTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            playbackTransportControls()
        }
    }
}
