import AppKit
import SwiftUI

struct TimelineVisibleRange: Equatable {
    let fullDuration: Double
    let startTime: Double
    let duration: Double

    var endTime: Double {
        startTime + duration
    }

    init(fullDuration: Double, startTime: Double = 0, duration: Double? = nil) {
        let safeFullDuration = max(fullDuration, 0.001)
        let safeDuration = min(max(duration ?? safeFullDuration, 0.001), safeFullDuration)
        let maxStartTime = max(safeFullDuration - safeDuration, 0)
        let safeStartTime = min(max(startTime, 0), maxStartTime)

        self.fullDuration = safeFullDuration
        self.startTime = safeStartTime
        self.duration = safeDuration
    }

    func contains(_ time: Double) -> Bool {
        time >= startTime && time <= endTime
    }

    func ratio(for time: Double) -> Double {
        (time - startTime) / max(duration, 0.001)
    }

    func clampedRatio(for time: Double) -> Double {
        min(max(ratio(for: time), 0), 1)
    }

    func clippedRange(start: Double, end: Double) -> (start: Double, end: Double)? {
        let clippedStart = max(start, startTime)
        let clippedEnd = min(max(end, start), endTime)

        guard clippedEnd >= clippedStart else {
            return nil
        }

        return (clippedStart, clippedEnd)
    }
}

extension ContentView {
    func playbackTransportBar(_ summary: RecordingInspectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    viewModel.jumpPlaybackToStart()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canUsePlaybackTransport && !viewModel.isRenderedPreviewActive)

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaybackActive ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canUsePlaybackTransport && !viewModel.isRenderedPreviewActive && viewModel.playbackPresentationMode != .previewCompletedSlate)

                Text(timecodeString(for: viewModel.currentPlaybackTime))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    @ViewBuilder
    func referenceTimelineSegment(
        startRatio: Double,
        eventRatio: Double,
        endRatio: Double,
        lane: Int,
        width: CGFloat,
        verticalOrigin: CGFloat,
        tint: Color,
        opacity: Double
    ) -> some View {
        let laneHeight: CGFloat = 9
        let laneSpacing: CGFloat = 4
        let laneY = verticalOrigin + (CGFloat(lane) * (laneHeight + laneSpacing))
        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width
        let eventX = CGFloat(eventRatio) * width
        let barWidth = max(endX - startX, 10)

        ZStack {
            Capsule(style: .continuous)
                .fill(tint.opacity(opacity))
                .frame(width: barWidth, height: laneHeight)
                .position(x: startX + (barWidth / 2), y: laneY + (laneHeight / 2))

            Capsule(style: .continuous)
                .fill(tint.opacity(min(opacity + 0.12, 1)))
                .frame(width: 5, height: 14)
                .position(x: eventX, y: laneY + (laneHeight / 2))
        }
        .allowsHitTesting(false)
    }

    func timelineLane(for startRatio: Double, endRatio: Double, laneEndRatios: inout [Double]) -> Int {
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

    func timelineVisibleRange(for duration: Double) -> TimelineVisibleRange {
        let safeDuration = max(duration, 0.001)
        let safeZoomScale = clampedTimelineZoomScale(timelineZoomScale, duration: safeDuration)
        return TimelineVisibleRange(
            fullDuration: safeDuration,
            startTime: visibleTimelineStartTime,
            duration: safeDuration / safeZoomScale
        )
    }

    func timelineMaximumZoomScale(for duration: Double) -> Double {
        let minimumVisibleDuration = 2.0
        let safeDuration = max(duration, 0.001)

        guard safeDuration > minimumVisibleDuration else {
            return 1
        }

        return min(40, max(1, safeDuration / minimumVisibleDuration))
    }

    func clampedTimelineZoomScale(_ zoomScale: Double, duration: Double) -> Double {
        min(max(zoomScale, 1), timelineMaximumZoomScale(for: duration))
    }

    func clampedTimelineStartTime(_ startTime: Double, visibleDuration: Double, fullDuration: Double) -> Double {
        let maxStartTime = max(fullDuration - visibleDuration, 0)
        return min(max(startTime, 0), maxStartTime)
    }

    func zoomTimelineVisibleRange(
        magnification: CGFloat,
        anchorX: CGFloat,
        width: CGFloat,
        duration: Double
    ) -> Bool {
        let safeDuration = max(duration, 0.001)
        let maximumZoomScale = timelineMaximumZoomScale(for: safeDuration)

        guard maximumZoomScale > 1, abs(magnification) > 0.0001 else {
            return false
        }

        let safeWidth = max(width, 1)
        let clampedAnchorX = min(max(anchorX, 0), safeWidth)
        let anchorRatio = Double(clampedAnchorX / safeWidth)
        let currentRange = timelineVisibleRange(for: safeDuration)
        let anchorTime = timelineTime(for: clampedAnchorX, width: safeWidth, visibleRange: currentRange)
        let scaleFactor = max(0.2, 1 + Double(magnification))
        let newZoomScale = clampedTimelineZoomScale(timelineZoomScale * scaleFactor, duration: safeDuration)
        let newVisibleDuration = safeDuration / newZoomScale
        let newStartTime = clampedTimelineStartTime(
            anchorTime - (anchorRatio * newVisibleDuration),
            visibleDuration: newVisibleDuration,
            fullDuration: safeDuration
        )

        timelineZoomScale = newZoomScale
        visibleTimelineStartTime = newStartTime
        return true
    }

    func panTimelineVisibleRange(
        deltaX: CGFloat,
        width: CGFloat,
        duration: Double
    ) -> Bool {
        let safeDuration = max(duration, 0.001)
        let currentRange = timelineVisibleRange(for: safeDuration)

        guard currentRange.duration < safeDuration, abs(deltaX) > 0.01 else {
            return false
        }

        let secondsPerPoint = currentRange.duration / Double(max(width, 1))
        let newStartTime = clampedTimelineStartTime(
            visibleTimelineStartTime - (Double(deltaX) * secondsPerPoint),
            visibleDuration: currentRange.duration,
            fullDuration: safeDuration
        )

        visibleTimelineStartTime = newStartTime
        return true
    }

    func timelineTime(for x: CGFloat, width: CGFloat, visibleRange: TimelineVisibleRange) -> Double {
        let clampedX = min(max(x, 0), max(width, 1))
        return visibleRange.startTime + (Double(clampedX / max(width, 1)) * visibleRange.duration)
    }

    func timelineX(for time: Double, visibleRange: TimelineVisibleRange, width: CGFloat) -> CGFloat {
        CGFloat(visibleRange.clampedRatio(for: time)) * width
    }

    func timelineSnapTarget(
        at x: CGFloat,
        width: CGFloat,
        visibleRange: TimelineVisibleRange,
        markers: [ZoomPlanItem]
    ) -> (marker: ZoomPlanItem, time: Double)? {
        let snapThreshold: CGFloat = 10
        let markerPositions = markers
            .filter { visibleRange.contains($0.sourceEventTimestamp) }
            .map { marker in
                (marker, CGFloat(visibleRange.clampedRatio(for: marker.sourceEventTimestamp)) * width)
            }

        guard let nearest = markerPositions.min(by: { abs($0.1 - x) < abs($1.1 - x) }),
              abs(nearest.1 - x) <= snapThreshold else {
            return nil
        }

        return (nearest.0, nearest.0.sourceEventTimestamp)
    }

    func effectTimelineSnapTarget(
        at x: CGFloat,
        width: CGFloat,
        visibleRange: TimelineVisibleRange,
        markers: [EffectPlanItem]
    ) -> (marker: EffectPlanItem, time: Double)? {
        let snapThreshold: CGFloat = 10
        let markerPositions = markers
            .filter { visibleRange.contains($0.snapTime) }
            .map { marker in
                (marker, CGFloat(visibleRange.clampedRatio(for: marker.snapTime)) * width)
            }

        guard let nearest = markerPositions.min(by: { abs($0.1 - x) < abs($1.1 - x) }),
              abs(nearest.1 - x) <= snapThreshold else {
            return nil
        }

        return (nearest.0, nearest.0.snapTime)
    }

    func effectTimelineHitTarget(
        at point: CGPoint,
        width: CGFloat,
        verticalOrigin: CGFloat,
        layouts: [EffectTimelineSegmentLayout]
    ) -> EffectPlanItem? {
        let laneHeight: CGFloat = 9
        let laneSpacing: CGFloat = 4
        let minimumHitWidth: CGFloat = 18
        let verticalHitSlop: CGFloat = 8

        return layouts.reversed().first { layout in
            let startX = CGFloat(layout.startRatio) * width
            let endX = CGFloat(layout.endRatio) * width
            let actualBarWidth = max(endX - startX, 1)
            let hitWidth = max(actualBarWidth, minimumHitWidth)
            let hitPadding = max((hitWidth - actualBarWidth) / 2, 0)
            let minX = startX - hitPadding
            let maxX = endX + hitPadding
            let laneY = verticalOrigin + (CGFloat(layout.lane) * (laneHeight + laneSpacing))
            let minY = laneY - verticalHitSlop
            let maxY = laneY + laneHeight + verticalHitSlop

            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }?.marker
    }
}

struct TimelineTrackpadGestureCaptureView: NSViewRepresentable {
    let onMagnify: (CGFloat, CGFloat, CGFloat) -> Bool
    let onHorizontalScroll: (CGFloat, CGFloat, CGFloat) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = TimelineTrackpadGestureCaptureNSView()
        context.coordinator.installMonitor(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var parent: TimelineTrackpadGestureCaptureView
        private var monitor: Any?

        init(parent: TimelineTrackpadGestureCaptureView) {
            self.parent = parent
        }

        func installMonitor(for view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self, weak view] event in
                guard let self, let view, self.eventIsInsideView(event, view: view) else {
                    return event
                }

                let location = view.convert(event.locationInWindow, from: nil)
                let width = max(view.bounds.width, 1)

                switch event.type {
                case .magnify:
                    return self.parent.onMagnify(event.magnification, location.x, width) ? nil : event
                case .scrollWheel:
                    guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                          abs(event.scrollingDeltaX) > 0.01 else {
                        return event
                    }

                    return self.parent.onHorizontalScroll(event.scrollingDeltaX, location.x, width) ? nil : event
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func eventIsInsideView(_ event: NSEvent, view: NSView) -> Bool {
            guard let window = view.window, event.window === window else {
                return false
            }

            let location = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(location)
        }
    }
}

private final class TimelineTrackpadGestureCaptureNSView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
