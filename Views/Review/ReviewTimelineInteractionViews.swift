import SwiftUI

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
        onToggleAddClickFocus: @escaping () -> Void,
        onDeleteSelectedMarker: @escaping () -> Void,
        onSelectNoZoomFallbackMode: @escaping (NoZoomFallbackMode) -> Void,
        onToggleOverflowRegion: @escaping () -> Void
    ) -> some View {
        TimelineToolbarView(
            hasSelectedMarker: hasSelectedMarker,
            canEditClickFocusMarkers: canEditClickFocusMarkers,
            isPlacingClickFocus: isPlacingClickFocus,
            selectedMarker: selectedMarker,
            showsNoZoomFallbackControls: showsNoZoomFallbackControls,
            isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion,
            onToggleAddClickFocus: onToggleAddClickFocus,
            onDeleteSelectedMarker: onDeleteSelectedMarker,
            onSelectNoZoomFallbackMode: onSelectNoZoomFallbackMode,
            onToggleOverflowRegion: onToggleOverflowRegion
        )
    }

    func timelineCanvasView(
        width: CGFloat,
        duration: Double,
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
        hoveredEffectTooltipMarker: EffectPlanItem?,
        hoveredEffectTooltipMarkerNumber: Int?,
        hoveredEffectTooltipAnchor: CGPoint?,
        playheadX: CGFloat,
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
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 8)
                .position(x: width / 2, y: trackCenterY)

            if isDraggingTimeline {
                Capsule()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(height: 8)
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
                        tint: Color.secondary,
                        opacity: 0.24
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
                        tint: Color.secondary,
                        opacity: 0.34
                    )
                }

                EffectsTimelineTrackView(
                    effectLayouts: effectLayouts,
                    width: width,
                    verticalOrigin: segmentOriginY,
                    timelineInteractionSuppressed: timelineInteractionSuppressed,
                    hoveredEffectTimelineMarkerID: hoveredEffectTimelineMarkerID,
                    selectedEffectMarkerID: selectedEffectMarkerID,
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

            timelinePlayheadView(
                playheadX: playheadX,
                width: width,
                trackCenterY: trackCenterY,
                isDraggingTimeline: isDraggingTimeline
            )
        }
    }

    func timelinePlayheadView(
        playheadX: CGFloat,
        width: CGFloat,
        trackCenterY: CGFloat,
        isDraggingTimeline: Bool
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3, height: 40)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .offset(y: -19)

            Circle()
                .fill(Color.accentColor.opacity(0.001))
                .frame(width: 22, height: 22)
                .offset(y: -19)
        }
        .frame(width: 22, height: 52)
        .shadow(color: Color.accentColor.opacity(isDraggingTimeline ? 0.42 : 0.22), radius: isDraggingTimeline ? 6 : 3, x: 0, y: 0)
        .position(
            x: min(max(playheadX, 11), max(width - 11, 11)),
            y: trackCenterY - 2
        )
    }

    func timelineFooterView(
        duration: Double,
        editorMode: ReviewEditorMode,
        isDrawingEffectFocusRegion: Bool,
        isDrawingNoZoomOverflowRegion: Bool
    ) -> some View {
        ZStack {
            HStack {
                Text("0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timecodeString(for: duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(
                isDrawingEffectFocusRegion
                ? "←/→/↑/↓ to nudge the focus region, ⌥ + Arrow for 10x speed"
                : editorMode == .effects
                ? "Zoom & Click bars are shown as grey reference guides while editing effects."
                : isDrawingNoZoomOverflowRegion
                ? "←/→/↑/↓ to nudge the overflow region, ⌥ + Arrow for 10x speed"
                : "Click a Marker to preview it, ←/→ to nudge 0.1s"
            )
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(.secondary)
        }
    }
}
