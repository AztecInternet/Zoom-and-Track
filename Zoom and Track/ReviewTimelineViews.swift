import SwiftUI

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

    func timelineTime(for x: CGFloat, width: CGFloat, duration: Double) -> Double {
        let clampedX = min(max(x, 0), max(width, 1))
        return Double(clampedX / max(width, 1)) * duration
    }

    func timelineX(for time: Double, duration: Double, width: CGFloat) -> CGFloat {
        let safeDuration = max(duration, 0.001)
        let clampedTime = min(max(time, 0), safeDuration)
        return CGFloat(clampedTime / safeDuration) * width
    }

    func timelineSnapTarget(
        at x: CGFloat,
        width: CGFloat,
        duration: Double,
        markers: [ZoomPlanItem]
    ) -> (marker: ZoomPlanItem, time: Double)? {
        let snapThreshold: CGFloat = 10
        let markerPositions = markers.map { marker in
            let ratio = min(max(marker.sourceEventTimestamp / max(duration, 0.001), 0), 1)
            return (marker, CGFloat(ratio) * width)
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
        duration: Double,
        markers: [EffectPlanItem]
    ) -> (marker: EffectPlanItem, time: Double)? {
        let snapThreshold: CGFloat = 10
        let markerPositions = markers.map { marker in
            let ratio = min(max(marker.snapTime / max(duration, 0.001), 0), 1)
            return (marker, CGFloat(ratio) * width)
        }

        guard let nearest = markerPositions.min(by: { abs($0.1 - x) < abs($1.1 - x) }),
              abs(nearest.1 - x) <= snapThreshold else {
            return nil
        }

        return (nearest.0, nearest.0.snapTime)
    }
}
