import AppKit
import SwiftUI

enum MarkerTimingPhase: String {
    case leadIn = "Motion to Click Offset"
    case zoomIn = "Zoom In"
    case hold = "Hold"
    case zoomOut = "Zoom Out"
}

struct TimelineSegmentLayout: Identifiable {
    let marker: ZoomPlanItem
    let markerNumber: Int
    let lane: Int
    let startRatio: Double
    let eventRatio: Double
    let endRatio: Double

    var id: String { marker.id }
}

func timelineSegmentLayouts(for markers: [ZoomPlanItem], duration: Double) -> [TimelineSegmentLayout] {
    let safeDuration = max(duration, 0.001)
    let maxLaneCount = 3
    var laneEndRatios = Array(repeating: -Double.infinity, count: maxLaneCount)
    let sortedMarkers = markers.enumerated().sorted { lhs, rhs in
        let lhsWindow = timelineSegmentWindow(for: lhs.element)
        let rhsWindow = timelineSegmentWindow(for: rhs.element)

        if lhsWindow.start != rhsWindow.start {
            return lhsWindow.start < rhsWindow.start
        }

        return lhs.element.sourceEventTimestamp < rhs.element.sourceEventTimestamp
    }

    return sortedMarkers.map { entry in
        let marker = entry.element
        let window = timelineSegmentWindow(for: marker)
        let startRatio = min(max(window.start / safeDuration, 0), 1)
        let eventRatio = min(max(marker.sourceEventTimestamp / safeDuration, 0), 1)
        let endRatio = min(max(window.end / safeDuration, eventRatio), 1)
        let lane = timelineLane(for: startRatio, endRatio: endRatio, laneEndRatios: &laneEndRatios)

        return TimelineSegmentLayout(
            marker: marker,
            markerNumber: entry.offset + 1,
            lane: lane,
            startRatio: startRatio,
            eventRatio: eventRatio,
            endRatio: endRatio
        )
    }
    .sorted { lhs, rhs in
        if lhs.lane != rhs.lane {
            return lhs.lane < rhs.lane
        }

        return lhs.startRatio < rhs.startRatio
    }
}

@ViewBuilder
func timelineSegment(
    layout: TimelineSegmentLayout,
    width: CGFloat,
    duration: Double,
    verticalOrigin: CGFloat,
    isSelected: Bool,
    isEnabled: Bool,
    activePhase: MarkerTimingPhase?,
    interactionSuppressed: Bool,
    isHovered: Bool,
    hoveredTimelineMarkerID: String?,
    hoveredTimelinePhase: MarkerTimingPhase?,
    onHoverChanged: @escaping (Bool, MarkerTimingPhase?, CGPoint) -> Void,
    onTap: @escaping () -> Void
) -> some View {
    let marker = layout.marker
    let baseColor: Color = isSelected ? .accentColor : (isEnabled ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.35))
    let laneHeight: CGFloat = 9
    let laneSpacing: CGFloat = 4
    let laneY = verticalOrigin + (CGFloat(layout.lane) * (laneHeight + laneSpacing))
    let startX = CGFloat(layout.startRatio) * width
    let endX = CGFloat(layout.endRatio) * width
    let eventX = CGFloat(layout.eventRatio) * width
    let barWidth = max(endX - startX, 10)
    let emphasisWidth: CGFloat = min(max(barWidth * 0.28, 8), 18)
    let markerBodyHeight: CGFloat = isSelected ? 18 : 14
    let markerBodyWidth: CGFloat = isSelected ? 8 : 6
    let hoverHighlightColor = (isSelected ? Color.accentColor : baseColor).opacity(isHovered ? (isEnabled ? 0.22 : 0.12) : 0)
    let hoverTargetPadding: CGFloat = 7
    let hoverTargetWidth = max(barWidth + (hoverTargetPadding * 2), 18)
    let hoverTargetHeight: CGFloat = 28
    let hoverAnchor = CGPoint(x: startX + (barWidth / 2), y: max(laneY - 20, 10))
    let localMinX = max(min(startX, eventX - 8) - hoverTargetPadding, 0)
    let localMaxX = min(max(endX, eventX + 8) + hoverTargetPadding, width)
    let localWidth = max(localMaxX - localMinX, hoverTargetWidth)
    let localCenterX = localMinX + (localWidth / 2)
    let localBarCenterX = (startX + (barWidth / 2)) - localMinX
    let localEventX = eventX - localMinX
    let localHoverCenterX = localBarCenterX
    let localHeight: CGFloat = 34
    let localCenterY = localHeight / 2
    let localMarkerCenterY = localCenterY + 0.5
    let labelY: CGFloat = 6
    let highlightedBarWidth = barWidth + 10
    let highlightedBarX = min(
        max(localBarCenterX, highlightedBarWidth / 2),
        max(localWidth - (highlightedBarWidth / 2), highlightedBarWidth / 2)
    )
    ZStack {
        timelineSegmentBar(
            marker: marker,
            baseColor: baseColor,
            isSelected: isSelected,
            isEnabled: isEnabled,
            width: barWidth,
            emphasisWidth: emphasisWidth,
            absoluteBarStartX: startX,
            duration: duration,
            hoveredTimelineMarkerID: hoveredTimelineMarkerID,
            hoveredTimelinePhase: hoveredTimelinePhase,
            onHoverChanged: onHoverChanged
        )
        .frame(width: barWidth, height: laneHeight)
        .position(x: localBarCenterX, y: localCenterY)

        Capsule()
            .fill(baseColor)
            .frame(width: markerBodyWidth, height: markerBodyHeight)
            .position(
                x: min(max(localEventX, markerBodyWidth / 2), max(localWidth - (markerBodyWidth / 2), markerBodyWidth / 2)),
                y: localMarkerCenterY
            )

        if isSelected {
            Capsule()
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 4)
                .frame(width: 12, height: 22)
                .position(
                    x: min(max(localEventX, 6), max(localWidth - 6, 6)),
                    y: localMarkerCenterY
                )
        }

        if let activePhase {
            let labelX = timelinePhaseCenterX(for: marker, phase: activePhase, duration: duration, width: width) - localMinX

            Text(activePhase.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                        )
                )
                .position(
                    x: labelX,
                    y: labelY
                )
                .allowsHitTesting(false)
        }

        if isHovered {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(hoverHighlightColor, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hoverHighlightColor.opacity(0.28))
                )
                .frame(width: highlightedBarWidth, height: 22)
                .position(
                    x: highlightedBarX,
                    y: localCenterY
                )
                .allowsHitTesting(false)
        }

        Rectangle()
            .fill(Color.clear)
            .frame(width: hoverTargetWidth, height: hoverTargetHeight)
            .position(
                x: min(max(localHoverCenterX, hoverTargetWidth / 2), max(localWidth - (hoverTargetWidth / 2), hoverTargetWidth / 2)),
                y: localCenterY
            )
            .contentShape(Rectangle())
            .onHover { isHovering in
                guard !interactionSuppressed else {
                    onHoverChanged(false, nil, hoverAnchor)
                    return
                }
                onHoverChanged(isHovering, nil, hoverAnchor)
            }
            .onTapGesture {
                guard !interactionSuppressed else { return }
                onTap()
            }
    }
    .frame(width: localWidth, height: localHeight)
    .position(x: localCenterX, y: laneY + (localHeight / 2))
    .brightness(isHovered ? 0.06 : 0)
}

func timelineMarkerTooltipOverlay(
    markerID: String,
    markerNumber: Int,
    marker: ZoomPlanItem,
    phase: MarkerTimingPhase?,
    hoveredTimelineMarkerID: String?,
    anchor: CGPoint,
    width: CGFloat
) -> some View {
    let tooltipWidth: CGFloat = 240
    let tooltipHalfWidth = tooltipWidth / 2
    let tooltipX = min(max(anchor.x, tooltipHalfWidth), max(width - tooltipHalfWidth, tooltipHalfWidth))
    let tooltipY: CGFloat = -120
    let trimmedMarkerName = marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = trimmedMarkerName?.isEmpty == false ? trimmedMarkerName! : "Unnamed Marker"
    let clickPulseStatus = marker.clickPulse.map { "Click Pulse: \($0.preset.displayName)" } ?? "Click Pulse: Off"

    return VStack(alignment: .leading, spacing: 4) {
        Text(displayName)
            .font(.system(size: 11, weight: .semibold))
        Text("Marker #\(markerNumber)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        Text(timecodeString(for: marker.sourceEventTimestamp))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        if let phase {
            Text(phase.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        Text("\(markerTypeSymbol(for: marker.zoomType)) \(marker.zoomType.displayName)")
            .font(.system(size: 11))
        if marker.zoomType != .noZoom && marker.zoomType != .outOnly {
            Text("Zoom \(String(format: "%.1fx", marker.zoomScale))")
                .font(.system(size: 11))
        }
        Text(clickPulseStatus)
            .font(.system(size: 11))
        Text("Motion to Click Offset \(String(format: "%.2fs", marker.leadInTime))")
            .font(.system(size: 11))
        if marker.zoomType != .outOnly {
            Text("Zoom In \(String(format: "%.2fs", marker.zoomInDuration))")
                .font(.system(size: 11))
        }
        if marker.zoomType != .outOnly {
            Text("Hold \(String(format: "%.2fs", marker.holdDuration))")
                .font(.system(size: 11))
        }
        if marker.zoomType == .inOut || marker.zoomType == .outOnly {
            Text("Zoom Out \(String(format: "%.2fs", marker.zoomOutDuration))")
                .font(.system(size: 11))
        }
        Text("Total \(String(format: "%.2fs", marker.totalSegmentDuration))")
            .font(.system(size: 11))
        Text(marker.enabled ? "Enabled" : "Disabled")
            .font(.system(size: 11))
            .foregroundStyle(marker.enabled ? .primary : .secondary)
        Divider()
        Text("hoveredTimelineMarkerID: \(hoveredTimelineMarkerID ?? "nil")")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        Text("displayed marker id: \(markerID)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        Text("displayed marker number: \(markerNumber)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .fixedSize()
    .frame(width: tooltipWidth, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    )
    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    .position(
        x: tooltipX,
        y: tooltipY
    )
    .allowsHitTesting(false)
}

@ViewBuilder
private func timelineSegmentBar(
    marker: ZoomPlanItem,
    baseColor: Color,
    isSelected: Bool,
    isEnabled: Bool,
    width: CGFloat,
    emphasisWidth: CGFloat,
    absoluteBarStartX: CGFloat,
    duration: Double,
    hoveredTimelineMarkerID: String?,
    hoveredTimelinePhase: MarkerTimingPhase?,
    onHoverChanged: @escaping (Bool, MarkerTimingPhase?, CGPoint) -> Void
) -> some View {
    let timeline = zoomTimeline(for: marker)
    let fillOpacity = isEnabled ? 0.82 : 0.34
    let leadColor = baseColor.opacity(isEnabled ? 0.24 : 0.14)
    let zoomInColor = baseColor.opacity(fillOpacity)
    let holdColor = baseColor.opacity(isEnabled ? 0.58 : 0.26)
    let zoomOutColor = baseColor.opacity(isEnabled ? 0.42 : 0.22)
    let totalWidth = max(width, 1)
    let leadWidth = max(phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? 0 : 2)
    let zoomInWidth = max(phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? 0 : 4)
    let holdWidth = max(phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? 0 : 2)
    let zoomOutWidth = max(phaseWidth(from: timeline.holdUntil, to: timeline.endTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: totalWidth), marker.zoomType == .outOnly ? totalWidth : 4)

    Capsule()
        .fill(Color.clear)
        .overlay {
            HStack(spacing: 0) {
                switch marker.zoomType {
                case .inOut:
                    timelinePhaseBlock(color: leadColor, width: leadWidth)
                    timelinePhaseBlock(color: zoomInColor, width: zoomInWidth)
                    timelinePhaseBlock(color: holdColor, width: holdWidth)
                    timelinePhaseBlock(color: zoomOutColor, width: zoomOutWidth)
                case .inOnly:
                    timelinePhaseBlock(color: leadColor, width: leadWidth)
                    timelinePhaseBlock(color: zoomInColor, width: zoomInWidth)
                    timelinePhaseBlock(color: holdColor, width: holdWidth)
                case .noZoom:
                    timelinePhaseBlock(color: leadColor, width: leadWidth)
                    timelinePhaseBlock(color: zoomInColor, width: zoomInWidth)
                    timelinePhaseBlock(color: holdColor, width: holdWidth)
                case .outOnly:
                    timelinePhaseBlock(color: zoomOutColor, width: max(totalWidth, emphasisWidth))
                }
            }
            .clipShape(Capsule())
        }
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .overlay {
            if isSelected {
                selectedTimelinePhaseOverlay(
                    marker: marker,
                    timeline: timeline,
                    width: totalWidth,
                    isEnabled: isEnabled,
                    absoluteBarStartX: absoluteBarStartX,
                    duration: duration,
                    hoveredTimelineMarkerID: hoveredTimelineMarkerID,
                    hoveredTimelinePhase: hoveredTimelinePhase,
                    onHoverChanged: onHoverChanged
                )
            }
        }
}

private func timelinePhaseBlock(color: Color, width: CGFloat) -> some View {
    Rectangle()
        .fill(color)
        .frame(width: max(width, 0))
}

@ViewBuilder
private func selectedTimelinePhaseOverlay(
    marker: ZoomPlanItem,
    timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
    width: CGFloat,
    isEnabled: Bool,
    absoluteBarStartX: CGFloat,
    duration: Double,
    hoveredTimelineMarkerID: String?,
    hoveredTimelinePhase: MarkerTimingPhase?,
    onHoverChanged: @escaping (Bool, MarkerTimingPhase?, CGPoint) -> Void
) -> some View {
    let phaseBounds = timelinePhaseBoundsMap(for: marker, timeline: timeline, width: width)
    let dividerTimes = phaseDividerTimes(for: marker, timeline: timeline)
    let dividerColor = Color.white.opacity(isEnabled ? 0.38 : 0.22)

    ZStack(alignment: .leading) {
        ForEach(dividerTimes, id: \.self) { time in
            Rectangle()
                .fill(dividerColor)
                .frame(width: 1, height: 9)
                .position(
                    x: min(max(phaseX(for: time, timeline: timeline, width: width), 0.5), max(width - 0.5, 0.5)),
                    y: 4.5
                )
                .allowsHitTesting(false)
        }

        HStack(spacing: 0) {
            ForEach(phaseBounds, id: \.phase.rawValue) { item in
                let phaseAnchor = CGPoint(
                    x: absoluteBarStartX + phaseStartOffset(for: item.phase, marker: marker, timeline: timeline, width: width) + (item.width / 2),
                    y: -8
                )
                Color.clear
                    .frame(width: max(item.width, 0))
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        if isHovering {
                            onHoverChanged(true, item.phase, phaseAnchor)
                        } else if hoveredTimelineMarkerID == marker.id, hoveredTimelinePhase == item.phase {
                            onHoverChanged(true, nil, CGPoint(x: width / 2, y: -8))
                        }
                    }
            }
        }
    }
    .clipShape(Capsule())
    .onHover { isHovering in
        if !isHovering, hoveredTimelineMarkerID == marker.id, hoveredTimelinePhase != nil {
            onHoverChanged(true, nil, CGPoint(x: width / 2, y: -8))
        }
    }
}

private func phaseWidth(from start: Double, to end: Double, timelineStart: Double, timelineEnd: Double, totalWidth: CGFloat) -> CGFloat {
    let totalDuration = max(timelineEnd - timelineStart, 0.001)
    let clampedStart = min(max(start, timelineStart), timelineEnd)
    let clampedEnd = min(max(end, clampedStart), timelineEnd)
    return CGFloat((clampedEnd - clampedStart) / totalDuration) * totalWidth
}

private func phaseX(for time: Double, timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double), width: CGFloat) -> CGFloat {
    let totalDuration = max(timeline.endTime - timeline.startTime, 0.001)
    let clampedTime = min(max(time, timeline.startTime), timeline.endTime)
    return CGFloat((clampedTime - timeline.startTime) / totalDuration) * width
}

private func phaseDividerTimes(for marker: ZoomPlanItem, timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)) -> [Double] {
    let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)

    switch marker.zoomType {
    case .inOut:
        return [zoomInStart, timeline.peakTime, timeline.holdUntil]
    case .inOnly:
        return [zoomInStart, timeline.peakTime]
    case .noZoom:
        return [zoomInStart, timeline.peakTime]
    case .outOnly:
        return []
    }
}

private func timelinePhaseBoundsMap(
    for marker: ZoomPlanItem,
    timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
    width: CGFloat
) -> [(phase: MarkerTimingPhase, width: CGFloat)] {
    var items: [(phase: MarkerTimingPhase, width: CGFloat)] = []

    switch marker.zoomType {
    case .inOut:
        items.append((.leadIn, phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.zoomIn, phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.hold, phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.zoomOut, phaseWidth(from: timeline.holdUntil, to: timeline.endTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
    case .inOnly:
        items.append((.leadIn, phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.zoomIn, phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.hold, phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
    case .noZoom:
        items.append((.leadIn, phaseWidth(from: timeline.startTime, to: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.zoomIn, phaseWidth(from: max(timeline.peakTime - marker.zoomInDuration, timeline.startTime), to: timeline.peakTime, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
        items.append((.hold, phaseWidth(from: timeline.peakTime, to: timeline.holdUntil, timelineStart: timeline.startTime, timelineEnd: timeline.endTime, totalWidth: width)))
    case .outOnly:
        items.append((.zoomOut, width))
    }

    return items.map { item in
        (item.phase, item.width)
    }
}

private func phaseStartOffset(
    for phase: MarkerTimingPhase,
    marker: ZoomPlanItem,
    timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
    width: CGFloat
) -> CGFloat {
    let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)

    switch phase {
    case .leadIn:
        return phaseX(for: timeline.startTime, timeline: timeline, width: width)
    case .zoomIn:
        return phaseX(for: zoomInStart, timeline: timeline, width: width)
    case .hold:
        return phaseX(for: timeline.peakTime, timeline: timeline, width: width)
    case .zoomOut:
        return phaseX(for: timeline.holdUntil, timeline: timeline, width: width)
    }
}

private func timelinePhaseCenterX(for marker: ZoomPlanItem, phase: MarkerTimingPhase, duration: Double, width: CGFloat) -> CGFloat {
    let bounds = timelinePhaseBounds(for: marker, phase: phase)
    let safeDuration = max(duration, 0.001)
    let startX = CGFloat(min(max(bounds.start, 0), safeDuration) / safeDuration) * width
    let endX = CGFloat(min(max(bounds.end, 0), safeDuration) / safeDuration) * width
    return startX + max((endX - startX) / 2, 0)
}

private func timelinePhaseBounds(for marker: ZoomPlanItem, phase: MarkerTimingPhase) -> (start: Double, end: Double) {
    let timeline = zoomTimeline(for: marker)
    let zoomInStart = max(timeline.peakTime - marker.zoomInDuration, timeline.startTime)

    switch phase {
    case .leadIn:
        return (timeline.startTime, zoomInStart)
    case .zoomIn:
        return (zoomInStart, timeline.peakTime)
    case .hold:
        return (timeline.peakTime, timeline.holdUntil)
    case .zoomOut:
        return (timeline.holdUntil, timeline.endTime)
    }
}

private func timelineLane(for startRatio: Double, endRatio: Double, laneEndRatios: inout [Double]) -> Int {
    let lanePadding = 0.008

    for index in laneEndRatios.indices {
        if startRatio >= laneEndRatios[index] + lanePadding {
            laneEndRatios[index] = endRatio
            return index
        }
    }

    if let bestIndex = laneEndRatios.enumerated().min(by: { $0.element < $1.element })?.offset {
        laneEndRatios[bestIndex] = endRatio
        return bestIndex
    }

    return 0
}

private func timelineSegmentWindow(for marker: ZoomPlanItem) -> (start: Double, end: Double) {
    let timeline = zoomTimeline(for: marker)

    switch marker.zoomType {
    case .inOut:
        return (start: max(timeline.startTime, 0), end: max(timeline.endTime, timeline.startTime))
    case .inOnly:
        return (start: max(timeline.startTime, 0), end: max(timeline.holdUntil, timeline.startTime))
    case .noZoom:
        return (start: max(timeline.startTime, 0), end: max(timeline.holdUntil, timeline.startTime))
    case .outOnly:
        return (start: max(timeline.startTime, 0), end: max(timeline.endTime, timeline.startTime))
    }
}

private func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
    let safeLeadIn = max(marker.leadInTime, 0)
    let safeZoomIn = max(marker.zoomInDuration, 0.05)
    let safeHold = max(marker.holdDuration, 0.05)
    let safeZoomOut = max(marker.zoomOutDuration, 0.05)
    let peakTime = marker.zoomType == .outOnly
        ? marker.sourceEventTimestamp
        : max(0, marker.sourceEventTimestamp - safeLeadIn)
    let fallbackStart = max(0, marker.sourceEventTimestamp - safeLeadIn - safeZoomIn)
    let fallbackHoldUntil = marker.sourceEventTimestamp + safeHold
    let fallbackEnd = fallbackHoldUntil + safeZoomOut

    switch marker.zoomType {
    case .inOut:
        let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
        let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
        let safeEndTime = marker.endTime.isFinite ? max(marker.endTime, safeHoldUntil) : fallbackEnd
        return (safeStart, peakTime, safeHoldUntil, safeEndTime)

    case .inOnly:
        let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
        let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
        return (safeStart, peakTime, safeHoldUntil, safeHoldUntil)

    case .noZoom:
        let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
        let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
        return (safeStart, peakTime, safeHoldUntil, safeHoldUntil)

    case .outOnly:
        let safeStart = marker.startTime.isFinite ? max(marker.startTime, peakTime) : peakTime
        let safeEndTime = marker.endTime.isFinite ? max(marker.endTime, safeStart) : peakTime + safeZoomOut
        return (safeStart, peakTime, safeStart, safeEndTime)
    }
}

private func markerTypeSymbol(for zoomType: ZoomType) -> String {
    switch zoomType {
    case .inOnly:
        return "arrow.right"
    case .outOnly:
        return "arrow.left"
    case .inOut:
        return "arrow.left.arrow.right"
    case .noZoom:
        return "smallcircle.filled.circle"
    }
}

private func timecodeString(for seconds: Double) -> String {
    let clampedSeconds = max(seconds, 0)
    let totalFrames = Int(clampedSeconds * 30)
    let hours = totalFrames / (30 * 60 * 60)
    let minutes = (totalFrames / (30 * 60)) % 60
    let secs = (totalFrames / 30) % 60
    let frames = totalFrames % 30
    return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
}
