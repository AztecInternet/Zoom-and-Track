import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

struct RenderedMarkerPreview {
    let outputURL: URL
    let sourceStartTime: Double
    let sourceEndTime: Double
}

final class MarkerPreviewRenderService {
    private let ciContext = CIContext()

    func renderPreview(
        recordingURL: URL,
        summary: RecordingInspectionSummary,
        selectedMarker: ZoomPlanItem
    ) async throws -> RenderedMarkerPreview {
        let asset = AVURLAsset(url: recordingURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The recording is missing a video track."]
            )
        }

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)

        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The recording has an invalid video size."]
            )
        }

        let baseOrientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
        )
        let outputSize = cappedRenderSize(for: orientedSize, maxWidth: 1440)
        let previewBounds = previewBounds(for: selectedMarker)
        let sourceStartTime = max(0, previewBounds.startTime)
        let sourceEndTime = max(previewBounds.endTime, sourceStartTime + 0.05)
        let sourceTimeRange = CMTimeRange(
            start: CMTime(seconds: sourceStartTime, preferredTimescale: 600),
            end: CMTime(seconds: sourceEndTime, preferredTimescale: 600)
        )

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create a composition video track."]
            )
        }
        try compositionVideoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: .zero)

        if let audioTrack,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(sourceTimeRange, of: audioTrack, at: .zero)
        }

        let frameRate = max(nominalFrameRate.isFinite && nominalFrameRate > 0 ? nominalFrameRate : 30, 30)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let baseScale = outputSize.width / orientedSize.width
        let markers = summary.zoomMarkers
        let contentCoordinateSize = summary.contentCoordinateSize
        logRenderedPreviewDebug(
            marker: selectedMarker,
            contentCoordinateSize: contentCoordinateSize,
            renderSize: outputSize
        )

        let videoComposition = AVMutableVideoComposition(asset: composition) { [weak self] request in
            guard let self else {
                request.finish(with: NSError(domain: "MarkerPreviewRenderService", code: 4))
                return
            }

            let sourceTime = sourceStartTime + request.compositionTime.seconds
            let previewState = self.activeZoomPreviewState(
                at: sourceTime,
                zoomMarkers: markers,
                contentCoordinateSize: contentCoordinateSize
            )

            var image = request.sourceImage.transformed(by: baseOrientationTransform)
            image = image.transformed(by: CGAffineTransform(scaleX: baseScale, y: baseScale))

            if let previewState {
                let offset = self.zoomPreviewOffset(for: previewState, outputSize: outputSize)
                image = image.transformed(by: CGAffineTransform(scaleX: previewState.scale, y: previewState.scale))
                image = image.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height))
            }

            let croppedImage = image.cropped(to: outputRect)
            request.finish(with: croppedImage, context: self.ciContext)
        }
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = frameDuration

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-preview-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Could not create an export session."]
            )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition
        exportSession.timeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)

        do {
            try await export(exportSession)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        return RenderedMarkerPreview(
            outputURL: outputURL,
            sourceStartTime: sourceStartTime,
            sourceEndTime: sourceEndTime
        )
    }

    private func export(_ session: AVAssetExportSession) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing: session.error ?? NSError(domain: "MarkerPreviewRenderService", code: 6))
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: NSError(domain: "MarkerPreviewRenderService", code: 7))
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
    }

    private func cappedRenderSize(for sourceSize: CGSize, maxWidth: CGFloat) -> CGSize {
        guard sourceSize.width > maxWidth else { return sourceSize }
        let scale = maxWidth / sourceSize.width
        return CGSize(width: maxWidth.rounded(.down), height: (sourceSize.height * scale).rounded(.down))
    }

    private func previewBounds(for marker: ZoomPlanItem) -> (startTime: Double, endTime: Double) {
        let startTime = max(0, marker.startTime)
        switch marker.zoomType {
        case .inOut, .outOnly:
            return (startTime, max(marker.endTime, marker.sourceEventTimestamp))
        case .inOnly:
            return (startTime, max(marker.holdUntil, marker.sourceEventTimestamp))
        }
    }

    private func activeZoomPreviewState(
        at currentTime: Double,
        zoomMarkers: [ZoomPlanItem],
        contentCoordinateSize: CGSize
    ) -> ZoomPreviewState? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let enabledMarkers = zoomMarkers
            .filter(\.enabled)
            .sorted { $0.sourceEventTimestamp < $1.sourceEventTimestamp }
        guard !enabledMarkers.isEmpty else {
            return nil
        }

        var currentState = ZoomPreviewState(scale: 1, normalizedPoint: CGPoint(x: 0.5, y: 0.5))

        for marker in enabledMarkers {
            let timeline = zoomTimeline(for: marker)
            if currentTime < timeline.startTime {
                break
            }

            let normalizedPoint = CGPoint(
                x: min(max(marker.centerX / contentCoordinateSize.width, 0), 1),
                y: normalizedRenderY(for: marker, contentCoordinateSize: contentCoordinateSize)
            )
            let stateEvent = ZoomStateEvent(
                marker: marker,
                normalizedPoint: normalizedPoint,
                scale: max(CGFloat(marker.zoomScale), 1)
            )

            switch marker.zoomType {
            case .inOut:
                if currentTime <= timeline.endTime {
                    return inOutPreviewState(at: currentTime, stateEvent: stateEvent, timeline: timeline)
                }
                currentState = ZoomPreviewState(scale: 1, normalizedPoint: normalizedPoint)

            case .inOnly:
                if currentTime <= timeline.peakTime {
                    return inOnlyPreviewState(at: currentTime, stateEvent: stateEvent, timeline: timeline)
                }
                currentState = ZoomPreviewState(scale: stateEvent.scale, normalizedPoint: normalizedPoint)

            case .outOnly:
                if currentTime <= timeline.endTime {
                    return outOnlyPreviewState(
                        at: currentTime,
                        currentState: currentState,
                        targetPoint: normalizedPoint,
                        timeline: timeline,
                        easeStyle: marker.easeStyle,
                        bounceAmount: marker.bounceAmount
                    )
                }
                currentState = ZoomPreviewState(scale: 1, normalizedPoint: normalizedPoint)
            }
        }

        return currentState.scale > 1.0001 ? currentState : nil
    }

    private func normalizedRenderY(for marker: ZoomPlanItem, contentCoordinateSize: CGSize) -> CGFloat {
        let normalizedYBeforeCorrection = min(max(marker.centerY / contentCoordinateSize.height, 0), 1)
        return 1 - normalizedYBeforeCorrection
    }

    private func logRenderedPreviewDebug(
        marker: ZoomPlanItem,
        contentCoordinateSize: CGSize,
        renderSize: CGSize
    ) {
        let normalizedX = min(max(marker.centerX / contentCoordinateSize.width, 0), 1)
        let normalizedYBeforeCorrection = min(max(marker.centerY / contentCoordinateSize.height, 0), 1)
        let normalizedYAfterCorrection = 1 - normalizedYBeforeCorrection
        print(
            """
            rendered preview debug
            marker id = \(marker.id)
            marker center = (\(marker.centerX), \(marker.centerY))
            content size = (\(contentCoordinateSize.width), \(contentCoordinateSize.height))
            normalizedX = \(normalizedX)
            normalizedY before = \(normalizedYBeforeCorrection)
            normalizedY after = \(normalizedYAfterCorrection)
            render size = (\(renderSize.width), \(renderSize.height))
            """
        )
    }

    private func zoomPreviewOffset(for previewState: ZoomPreviewState, outputSize: CGSize) -> CGSize {
        let scaledWidth = outputSize.width * previewState.scale
        let scaledHeight = outputSize.height * previewState.scale
        let targetX = previewState.normalizedPoint.x * outputSize.width
        let targetY = previewState.normalizedPoint.y * outputSize.height
        let desiredX = (outputSize.width / 2) - (targetX * previewState.scale)
        let desiredY = (outputSize.height / 2) - (targetY * previewState.scale)
        let minX = outputSize.width - scaledWidth
        let minY = outputSize.height - scaledHeight

        return CGSize(
            width: min(max(desiredX, minX), 0),
            height: min(max(desiredY, minY), 0)
        )
    }

    private func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
        let peakTime = marker.sourceEventTimestamp
        let safeLeadIn = max(marker.leadInTime, 0)
        let safeZoomIn = max(marker.zoomInDuration, 0.05)
        let safeHold = max(marker.holdDuration, 0.05)
        let safeZoomOut = max(marker.zoomOutDuration, 0.05)
        let fallbackStart = max(0, peakTime - safeLeadIn - safeZoomIn)
        let fallbackHoldUntil = peakTime + safeHold
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
        case .outOnly:
            let safeStart = marker.startTime.isFinite ? max(marker.startTime, peakTime) : peakTime
            let safeEndTime = marker.endTime.isFinite ? max(marker.endTime, safeStart) : peakTime + safeZoomOut
            return (safeStart, peakTime, safeStart, safeEndTime)
        }
    }

    private func zoomScale(
        at currentTime: Double,
        for marker: ZoomPlanItem,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)
    ) -> CGFloat {
        let maxScale = max(marker.zoomScale, 1)
        if currentTime <= timeline.peakTime {
            let progress = motionProgress(
                currentTime: currentTime,
                startTime: timeline.startTime,
                endTime: timeline.peakTime,
                easeStyle: marker.easeStyle,
                direction: .entering,
                bounceAmount: marker.bounceAmount
            )
            return interpolate(from: 1, to: maxScale, progress: progress.scale)
        }

        if currentTime <= timeline.holdUntil {
            return CGFloat(maxScale)
        }

        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.holdUntil,
            endTime: timeline.endTime,
            easeStyle: marker.easeStyle,
            direction: .exiting,
            bounceAmount: marker.bounceAmount
        )
        return max(interpolate(from: maxScale, to: 1, progress: progress.scale), 1)
    }

    private func normalizedProgress(_ value: Double, start: Double, end: Double) -> Double {
        guard end > start else { return 1 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private func interpolate(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        from + ((to - from) * CGFloat(progress))
    }

    private func motionProgress(
        currentTime: Double,
        startTime: Double,
        endTime: Double,
        easeStyle: ZoomEaseStyle,
        direction: MotionDirection,
        bounceAmount: Double
    ) -> MotionProgressSample {
        let progress = normalizedProgress(currentTime, start: startTime, end: endTime)
        let scaleProgress = easeStyle == .bounce
            ? bounceProgress(progress, amount: bounceAmount)
            : eased(progress, style: easeStyle, direction: direction)
        let panProgress: Double
        if easeStyle == .bounce {
            let smoothProgress = eased(progress, style: .smooth, direction: direction)
            panProgress = smoothProgress + ((scaleProgress - smoothProgress) * MotionTuning.panBounceInfluence)
        } else {
            panProgress = eased(progress, style: easeStyle, direction: direction)
        }
        return MotionProgressSample(scale: scaleProgress, pan: panProgress)
    }

    private func bounceProgress(_ progress: Double, amount: Double) -> Double {
        let clampedAmount = min(max(amount, 0), 1)
        let approachFraction = MotionTuning.bounceApproachFraction
        if progress <= approachFraction {
            let approachProgress = normalizedProgress(progress, start: 0, end: approachFraction)
            return eased(approachProgress, style: .smooth, direction: .entering)
        }

        let bounceProgress = normalizedProgress(progress, start: approachFraction, end: 1)
        let overshoot = MotionTuning.bounceMinOvershoot + (MotionTuning.bounceMaxOvershoot * clampedAmount)
        let envelope = pow(1 - bounceProgress, 2.2) * overshoot
        let oscillation = sin(bounceProgress * .pi * MotionTuning.bounceOscillationCount)
        return 1 + (envelope * oscillation)
    }

    private func eased(_ progress: Double, style: ZoomEaseStyle, direction: MotionDirection) -> Double {
        switch style {
        case .smooth:
            return 0.5 - (cos(progress * .pi) * 0.5)
        case .fastIn:
            return direction == .entering ? (1 - pow(1 - progress, 3)) : pow(progress, 3)
        case .fastOut:
            return direction == .entering ? pow(progress, 3) : (1 - pow(1 - progress, 3))
        case .linear:
            return progress
        case .bounce:
            return bounceProgress(progress, amount: 0.35)
        }
    }

    private func inOutPreviewState(
        at currentTime: Double,
        stateEvent: ZoomStateEvent,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)
    ) -> ZoomPreviewState {
        let scale = zoomScale(at: currentTime, for: stateEvent.marker, timeline: timeline)
        return ZoomPreviewState(scale: max(scale, 1), normalizedPoint: stateEvent.normalizedPoint)
    }

    private func inOnlyPreviewState(
        at currentTime: Double,
        stateEvent: ZoomStateEvent,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double)
    ) -> ZoomPreviewState {
        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.startTime,
            endTime: timeline.peakTime,
            easeStyle: stateEvent.marker.easeStyle,
            direction: .entering,
            bounceAmount: stateEvent.marker.bounceAmount
        )
        let scale = interpolate(from: 1, to: stateEvent.scale, progress: progress.scale)
        return ZoomPreviewState(scale: max(scale, 1), normalizedPoint: stateEvent.normalizedPoint)
    }

    private func outOnlyPreviewState(
        at currentTime: Double,
        currentState: ZoomPreviewState,
        targetPoint: CGPoint,
        timeline: (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double),
        easeStyle: ZoomEaseStyle,
        bounceAmount: Double
    ) -> ZoomPreviewState {
        let startScale = max(currentState.scale, 1)
        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.startTime,
            endTime: timeline.endTime,
            easeStyle: easeStyle,
            direction: .exiting,
            bounceAmount: bounceAmount
        )
        let scale = max(interpolate(from: startScale, to: 1, progress: progress.scale), 1)
        let x = currentState.normalizedPoint.x + ((targetPoint.x - currentState.normalizedPoint.x) * progress.pan)
        let y = currentState.normalizedPoint.y + ((targetPoint.y - currentState.normalizedPoint.y) * progress.pan)
        return ZoomPreviewState(scale: scale, normalizedPoint: CGPoint(x: x, y: y))
    }
}

private struct ZoomPreviewState {
    let scale: CGFloat
    let normalizedPoint: CGPoint
}

private struct ZoomStateEvent {
    let marker: ZoomPlanItem
    let normalizedPoint: CGPoint
    let scale: CGFloat
}

private struct MotionProgressSample {
    let scale: Double
    let pan: Double
}

private enum MotionDirection {
    case entering
    case exiting
}

private enum MotionTuning {
    static let bounceApproachFraction = 0.64
    static let bounceMinOvershoot = 0.06
    static let bounceMaxOvershoot = 0.18
    static let bounceOscillationCount = 4.0
    static let panBounceInfluence = 0.18
}
