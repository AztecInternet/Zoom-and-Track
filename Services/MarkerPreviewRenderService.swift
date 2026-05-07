@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import CoreImage
import Foundation

struct RenderedMarkerPreview {
    let outputURL: URL
    let sourceStartTime: Double
    let sourceEndTime: Double
    let deleteWhenFinished: Bool
}

final class MarkerPreviewRenderService {
    private let ciContext = CIContext()
    private let previewPaddingBefore: Double = 0.10
    private let previewPaddingAfter: Double = 0.10

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
        let assetDuration = try await asset.load(.duration).seconds

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
        let previewBounds = SharedMotionEngine.previewBounds(for: selectedMarker)
        let sourceStartTime = max(0, previewBounds.startTime - previewPaddingBefore)
        let sourceEndTime = min(
            max(previewBounds.endTime + previewPaddingAfter, sourceStartTime + 0.05),
            max(assetDuration, sourceStartTime + 0.05)
        )
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
        let effectMarkers = summary.effectMarkers
        let contentCoordinateSize = summary.contentCoordinateSize
        logRenderedPreviewDebug(
            marker: selectedMarker,
            contentCoordinateSize: contentCoordinateSize,
            renderSize: outputSize
        )

        let videoComposition = try await AVVideoComposition.videoComposition(with: composition) { [weak self] request in
            guard let self else {
                request.finish(with: NSError(domain: "MarkerPreviewRenderService", code: 4))
                return
            }

            let sourceTime = sourceStartTime + request.compositionTime.seconds
            let previewState = SharedMotionEngine.activeZoomState(
                at: sourceTime,
                zoomMarkers: markers,
                contentCoordinateSize: contentCoordinateSize,
                coordinateSpace: .bottomLeft
            )

            var image = request.sourceImage.transformed(by: baseOrientationTransform)
            image = image.transformed(by: CGAffineTransform(scaleX: baseScale, y: baseScale))

            let pulseImage = makeClickPulseOverlay(
                at: sourceTime,
                markers: markers,
                contentCoordinateSize: contentCoordinateSize,
                orientedVideoSize: orientedSize,
                outputSize: outputSize,
                previewState: previewState
            )
            if let previewState {
                let offset = SharedMotionEngine.previewOffset(for: previewState, outputSize: outputSize)
                image = image.transformed(by: CGAffineTransform(scaleX: previewState.scale, y: previewState.scale))
                image = image.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height))
            }

            let effectImage = makeEffectOverlay(
                at: sourceTime,
                effectMarkers: effectMarkers,
                contentCoordinateSize: contentCoordinateSize,
                orientedVideoSize: orientedSize,
                outputSize: outputSize,
                previewState: previewState,
                sourceImage: image.cropped(to: outputRect)
            )

            var outputImage = image.cropped(to: outputRect)
            if let effectImage {
                outputImage = effectImage.cropped(to: outputRect)
            }
            if let pulseImage {
                outputImage = pulseImage.cropped(to: outputRect).composited(over: outputImage)
            }
            request.finish(with: outputImage, context: self.ciContext)
        }
        configureVideoComposition(videoComposition, renderSize: outputSize, frameDuration: frameDuration)

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
            try await export(exportSession, to: outputURL, fileType: .mov)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        return RenderedMarkerPreview(
            outputURL: outputURL,
            sourceStartTime: sourceStartTime,
            sourceEndTime: sourceEndTime,
            deleteWhenFinished: true
        )
    }

    func renderEffectPreview(
        recordingURL: URL,
        summary: RecordingInspectionSummary,
        selectedMarker: EffectPlanItem
    ) async throws -> RenderedMarkerPreview {
        let asset = AVURLAsset(url: recordingURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "The recording is missing a video track."]
            )
        }

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
        let assetDuration = try await asset.load(.duration).seconds

        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "The recording has an invalid video size."]
            )
        }

        let baseOrientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
        )
        let outputSize = cappedRenderSize(for: orientedSize, maxWidth: 1440)
        let previewBounds = effectPreviewBounds(for: selectedMarker)
        let sourceStartTime = max(0, previewBounds.startTime - previewPaddingBefore)
        let sourceEndTime = min(
            max(previewBounds.endTime + previewPaddingAfter, sourceStartTime + 0.05),
            max(assetDuration, sourceStartTime + 0.05)
        )
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
                code: 8,
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
        let effectMarkers = summary.effectMarkers
        let contentCoordinateSize = summary.contentCoordinateSize

        let videoComposition = try await AVVideoComposition.videoComposition(with: composition) { [weak self] request in
            guard let self else {
                request.finish(with: NSError(domain: "MarkerPreviewRenderService", code: 9))
                return
            }

            let sourceTime = sourceStartTime + request.compositionTime.seconds
            let previewState = SharedMotionEngine.activeZoomState(
                at: sourceTime,
                zoomMarkers: markers,
                contentCoordinateSize: contentCoordinateSize,
                coordinateSpace: .bottomLeft
            )

            var image = request.sourceImage.transformed(by: baseOrientationTransform)
            image = image.transformed(by: CGAffineTransform(scaleX: baseScale, y: baseScale))

            let pulseImage = makeClickPulseOverlay(
                at: sourceTime,
                markers: markers,
                contentCoordinateSize: contentCoordinateSize,
                orientedVideoSize: orientedSize,
                outputSize: outputSize,
                previewState: previewState
            )
            if let previewState {
                let offset = SharedMotionEngine.previewOffset(for: previewState, outputSize: outputSize)
                image = image.transformed(by: CGAffineTransform(scaleX: previewState.scale, y: previewState.scale))
                image = image.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height))
            }

            let effectImage = makeEffectOverlay(
                at: sourceTime,
                effectMarkers: effectMarkers,
                contentCoordinateSize: contentCoordinateSize,
                orientedVideoSize: orientedSize,
                outputSize: outputSize,
                previewState: previewState,
                sourceImage: image.cropped(to: outputRect)
            )

            var outputImage = image.cropped(to: outputRect)
            if let effectImage {
                outputImage = effectImage.cropped(to: outputRect)
            }
            if let pulseImage {
                outputImage = pulseImage.cropped(to: outputRect).composited(over: outputImage)
            }
            request.finish(with: outputImage, context: self.ciContext)
        }
        configureVideoComposition(videoComposition, renderSize: outputSize, frameDuration: frameDuration)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("effect-preview-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(
                domain: "MarkerPreviewRenderService",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Could not create an export session."]
            )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition
        exportSession.timeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)

        do {
            try await export(exportSession, to: outputURL, fileType: .mov)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        return RenderedMarkerPreview(
            outputURL: outputURL,
            sourceStartTime: sourceStartTime,
            sourceEndTime: sourceEndTime,
            deleteWhenFinished: true
        )
    }

    private func export(
        _ session: AVAssetExportSession,
        to outputURL: URL,
        fileType: AVFileType
    ) async throws {
        try await session.export(to: outputURL, as: fileType)
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
        case .inOnly, .noZoom:
            return (startTime, max(marker.holdUntil, marker.sourceEventTimestamp))
        }
    }

    private func effectPreviewBounds(for marker: EffectPlanItem) -> (startTime: Double, endTime: Double) {
        (
            startTime: max(0, marker.startTime),
            endTime: max(marker.endTime, marker.startTime + 0.05)
        )
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

}

enum ExportRenderPhase {
    case preparing
    case exporting
    case finalizing
}

struct ExportRenderResult {
    let outputURL: URL
    let renderSize: CGSize
}

final class ExportRenderService {
    private let ciContext = CIContext()
    private let maxFallbackWidth: CGFloat = 3840
    private var activeExportSession: AVAssetExportSession?

    func cancelExport() {
        activeExportSession?.cancelExport()
    }

    func exportRecording(
        recordingURL: URL,
        summary: RecordingInspectionSummary,
        outputURL: URL,
        progressHandler: @escaping @MainActor @Sendable (ExportRenderPhase, Double) async -> Void
    ) async throws -> ExportRenderResult {
        await progressHandler(.preparing, 0.02)

        let asset = AVURLAsset(url: recordingURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw NSError(
                domain: "ExportRenderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The recording is missing a video track."]
            )
        }

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
        let assetDuration = try await asset.load(.duration)

        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            throw NSError(
                domain: "ExportRenderService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The recording has an invalid video size."]
            )
        }

        let baseOrientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
        )
        let outputSize = stabilizedRenderSize(for: orientedSize)
        let markers = summary.zoomMarkers.filter(\.enabled)
        let effectMarkers = summary.effectMarkers

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(
                domain: "ExportRenderService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create a composition video track."]
            )
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: assetDuration),
            of: sourceVideoTrack,
            at: .zero
        )

        if let audioTrack,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: audioTrack,
                at: .zero
            )
        }

        let frameRate = max(nominalFrameRate.isFinite && nominalFrameRate > 0 ? nominalFrameRate : 30, 30)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let baseScale = outputSize.width / orientedSize.width

        let videoComposition = try await AVVideoComposition.videoComposition(with: composition) { [weak self] request in
            guard let self else {
                request.finish(with: NSError(domain: "ExportRenderService", code: 4))
                return
            }

            let sourceTime = request.compositionTime.seconds
            let previewState = SharedMotionEngine.activeZoomState(
                at: sourceTime,
                zoomMarkers: markers,
                contentCoordinateSize: summary.contentCoordinateSize,
                coordinateSpace: .bottomLeft
            )

            var image = request.sourceImage.transformed(by: baseOrientationTransform)
            image = image.transformed(by: CGAffineTransform(scaleX: baseScale, y: baseScale))

            let pulseImage = makeClickPulseOverlay(
                at: sourceTime,
                markers: markers,
                contentCoordinateSize: summary.contentCoordinateSize,
                orientedVideoSize: orientedSize,
                outputSize: outputSize,
                previewState: previewState
            )
            if let previewState {
                let offset = SharedMotionEngine.previewOffset(for: previewState, outputSize: outputSize)
                image = image.transformed(by: CGAffineTransform(scaleX: previewState.scale, y: previewState.scale))
                image = image.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height))
            }

            let effectImage = makeEffectOverlay(
                at: sourceTime,
                effectMarkers: effectMarkers,
                contentCoordinateSize: summary.contentCoordinateSize,
                orientedVideoSize: orientedSize,
                outputSize: outputSize,
                previewState: previewState,
                sourceImage: image.cropped(to: outputRect)
            )

            var outputImage = image.cropped(to: outputRect)
            if let effectImage {
                outputImage = effectImage.cropped(to: outputRect)
            }
            if let pulseImage {
                outputImage = pulseImage.cropped(to: outputRect).composited(over: outputImage)
            }

            request.finish(with: outputImage, context: self.ciContext)
        }
        configureVideoComposition(videoComposition, renderSize: outputSize, frameDuration: frameDuration)

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(
                domain: "ExportRenderService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Could not create an export session."]
            )
        }

        activeExportSession = exportSession
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition

        await progressHandler(.exporting, 0.05)

        do {
            try await export(
                exportSession: exportSession,
                to: outputURL,
                fileType: .mov,
                progressHandler: progressHandler
            )
            await progressHandler(.finalizing, 1.0)
            activeExportSession = nil
            return ExportRenderResult(outputURL: outputURL, renderSize: outputSize)
        } catch {
            activeExportSession = nil
            if error is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw error
        }
    }

    private func export(
        exportSession: AVAssetExportSession,
        to outputURL: URL,
        fileType: AVFileType,
        progressHandler: @escaping @MainActor @Sendable (ExportRenderPhase, Double) async -> Void
    ) async throws {
        let progressTask = Task {
            for await state in exportSession.states(updateInterval: 0.12) {
                guard !Task.isCancelled else { break }
                if case .exporting(let progress) = state {
                    await progressHandler(.exporting, progress.fractionCompleted)
                }
            }
        }

        defer {
            progressTask.cancel()
        }

        try await exportSession.export(to: outputURL, as: fileType)
    }

    private func stabilizedRenderSize(for sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > maxFallbackWidth else {
            return CGSize(width: floor(sourceSize.width), height: floor(sourceSize.height))
        }

        let scale = maxFallbackWidth / sourceSize.width
        return CGSize(
            width: floor(maxFallbackWidth),
            height: floor(sourceSize.height * scale)
        )
    }
}

private struct EffectRenderState {
    let style: EffectStyle
    let region: EffectFocusRegion
    let blurIntensity: Double
    let darkenIntensity: Double
    let tintIntensity: Double
    let cornerRadius: CGFloat
    let feather: CGFloat
    let tintColor: NSColor
}

private func makeClickPulseOverlay(
    at currentTime: Double,
    markers: [ZoomPlanItem],
    contentCoordinateSize: CGSize,
    orientedVideoSize: CGSize,
    outputSize: CGSize,
    previewState: SharedMotionEngine.PreviewState?
) -> CIImage? {
    let activePulses = markers.compactMap { marker -> (SharedMotionEngine.ClickPulseRenderState, CGPoint)? in
        guard let pulseState = SharedMotionEngine.clickPulseRenderState(at: currentTime, marker: marker) else {
            return nil
        }
        let resolution = SharedMotionEngine.resolveOverlayPoint(
            contentPoint: CGPoint(x: marker.centerX, y: marker.centerY),
            contentCoordinateSize: contentCoordinateSize,
            orientedVideoSize: orientedVideoSize,
            outputSize: outputSize,
            previewState: previewState,
        )
        guard resolution.isVisible else { return nil }
        return (pulseState, resolution.point)
    }
    guard !activePulses.isEmpty else { return nil }

    let width = max(Int(outputSize.width.rounded(.up)), 1)
    let height = max(Int(outputSize.height.rounded(.up)), 1)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.translateBy(x: 0, y: outputSize.height)
    context.scaleBy(x: 1, y: -1)

    for (pulse, center) in activePulses {
        drawClickPulse(
            center: center,
            time: pulse.progress,
            preset: pulse.preset,
            in: context,
            outputSize: outputSize
        )
    }

    guard let cgImage = context.makeImage() else { return nil }
    return CIImage(cgImage: cgImage)
}

private func makeEffectOverlay(
    at currentTime: Double,
    effectMarkers: [EffectPlanItem],
    contentCoordinateSize: CGSize,
    orientedVideoSize: CGSize,
    outputSize: CGSize,
    previewState: SharedMotionEngine.PreviewState?,
    sourceImage: CIImage? = nil
) -> CIImage? {
    guard let effectState = activeEffectRenderState(at: currentTime, effectMarkers: effectMarkers),
          contentCoordinateSize.width > 0,
          contentCoordinateSize.height > 0,
          outputSize.width > 0,
          outputSize.height > 0 else {
        return nil
    }

    let sourceRect = CGRect(
        x: (effectState.region.centerX - (effectState.region.width / 2)) * contentCoordinateSize.width,
        y: (effectState.region.centerY - (effectState.region.height / 2)) * contentCoordinateSize.height,
        width: effectState.region.width * contentCoordinateSize.width,
        height: effectState.region.height * contentCoordinateSize.height
    )

    let topLeft = SharedMotionEngine.resolveOverlayPoint(
        contentPoint: CGPoint(x: sourceRect.minX, y: sourceRect.minY),
        contentCoordinateSize: contentCoordinateSize,
        orientedVideoSize: orientedVideoSize,
        outputSize: outputSize,
        previewState: previewState
    )
    let bottomRight = SharedMotionEngine.resolveOverlayPoint(
        contentPoint: CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
        contentCoordinateSize: contentCoordinateSize,
        orientedVideoSize: orientedVideoSize,
        outputSize: outputSize,
        previewState: previewState
    )

    let transformedRect = CGRect(
        x: topLeft.point.x,
        y: topLeft.point.y,
        width: bottomRight.point.x - topLeft.point.x,
        height: bottomRight.point.y - topLeft.point.y
    ).standardized

    let outputRect = CGRect(origin: .zero, size: outputSize)
    let radius = min(effectState.cornerRadius, min(transformedRect.width, transformedRect.height) / 2)

    let maskImage = makeRoundedRectMaskImage(
        outputSize: outputSize,
        rect: transformedRect,
        cornerRadius: radius,
        feather: effectState.feather
    )

    var outputImage = sourceImage?.cropped(to: outputRect)

    if effectState.style == .blur || effectState.style == .blurDarken,
       let sourceImage {
        let blurRadius = 28 * effectState.blurIntensity
        let blurredImage = sourceImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: outputRect)
        outputImage = sourceImage
            .cropped(to: outputRect)
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: blurredImage,
                    kCIInputMaskImageKey: maskImage
                ]
            )
            .cropped(to: outputRect)
    }

    let overlayColor = effectOverlayColor(for: effectState)
    if overlayColor.alphaComponent > 0.001 {
        let overlayImage = makeOutsideRegionOverlayImage(
            outputSize: outputSize,
            maskImage: maskImage,
            overlayColor: overlayColor
        )
        if let outputImage {
            return overlayImage.composited(over: outputImage).cropped(to: outputRect)
        }
        return overlayImage
    }

    return outputImage
}

private func activeEffectRenderState(
    at currentTime: Double,
    effectMarkers: [EffectPlanItem]
) -> EffectRenderState? {
    let eligibleMarkers = effectMarkers
        .filter { $0.enabled && $0.focusRegion != nil && currentTime >= $0.startTime && currentTime <= $0.endTime }
        .sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.sourceEventTimestamp < rhs.sourceEventTimestamp
            }
            return lhs.startTime < rhs.startTime
        }

    guard let marker = eligibleMarkers.last,
          let region = marker.focusRegion else {
        return nil
    }

    let fadeInDuration = max(marker.holdStartTime - marker.startTime, 0)
    let fadeOutDuration = max(marker.endTime - marker.holdEndTime, 0)
    let fadeInProgress = fadeInDuration <= 0.0001
        ? 1.0
        : min(max((currentTime - marker.startTime) / fadeInDuration, 0), 1)
    let fadeOutProgress = fadeOutDuration <= 0.0001
        ? 1.0
        : min(max((marker.endTime - currentTime) / fadeOutDuration, 0), 1)
    let timingIntensity = min(fadeInProgress, fadeOutProgress)
    let blurIntensity = timingIntensity * min(max(marker.blurAmount, 0), 1)
    let darkenIntensity = timingIntensity * min(max(marker.darkenAmount, 0), 1)
    let tintIntensity = timingIntensity * min(max(marker.tintAmount, 0), 1)

    guard max(blurIntensity, darkenIntensity, tintIntensity) > 0 else { return nil }

    return EffectRenderState(
        style: marker.style,
        region: region,
        blurIntensity: blurIntensity,
        darkenIntensity: darkenIntensity,
        tintIntensity: tintIntensity,
        cornerRadius: CGFloat(max(marker.cornerRadius, 0)),
        feather: CGFloat(max(marker.feather, 0)),
        tintColor: NSColor(
            red: CGFloat(min(max(marker.tintColor.red, 0), 1)),
            green: CGFloat(min(max(marker.tintColor.green, 0), 1)),
            blue: CGFloat(min(max(marker.tintColor.blue, 0), 1)),
            alpha: CGFloat(min(max(marker.tintColor.alpha, 0), 1))
        )
    )
}

private func effectOverlayColor(for state: EffectRenderState) -> NSColor {
    switch state.style {
    case .darken:
        return NSColor.black.withAlphaComponent(state.darkenIntensity)
    case .blurDarken:
        return NSColor.black.withAlphaComponent(state.darkenIntensity)
    case .tint:
        return state.tintColor.withAlphaComponent(0.42 * state.tintIntensity)
    case .blur:
        return .clear
    }
}

private func makeRoundedRectMaskImage(
    outputSize: CGSize,
    rect: CGRect,
    cornerRadius: CGFloat,
    feather: CGFloat
) -> CIImage {
    let width = max(Int(outputSize.width.rounded(.up)), 1)
    let height = max(Int(outputSize.height.rounded(.up)), 1)
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.translateBy(x: 0, y: outputSize.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(origin: .zero, size: outputSize))
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.fillPath()
    let image = CIImage(cgImage: context.makeImage()!)
    guard feather > 0.001 else {
        return image
    }

    return image
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
        .cropped(to: CGRect(origin: .zero, size: outputSize))
}

private func makeOutsideRegionOverlayImage(
    outputSize: CGSize,
    maskImage: CIImage,
    overlayColor: NSColor
) -> CIImage {
    let outputRect = CGRect(origin: .zero, size: outputSize)
    let overlayImage = CIImage(color: CIColor(cgColor: overlayColor.cgColor)).cropped(to: outputRect)
    let clearImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: outputRect)
    let outsideMask = maskImage
        .applyingFilter("CIColorInvert")
        .cropped(to: outputRect)

    return overlayImage
        .applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: clearImage,
                kCIInputMaskImageKey: outsideMask
            ]
        )
        .cropped(to: outputRect)
}

private func drawClickPulse(
    center: CGPoint,
    time: Double,
    preset: ClickPulsePreset,
    in context: CGContext,
    outputSize: CGSize
) {
    let baseRadius = max(min(outputSize.width, outputSize.height) * 0.035, 18)
    let p = CGFloat(time)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let icy = CGColor(red: 0.82, green: 0.94, blue: 1.0, alpha: 1)

    switch preset {
    case .subtleRing:
        strokeCircle(
            in: context,
            center: center,
            radius: baseRadius + (baseRadius * 1.6 * p),
            lineWidth: max(1.5, baseRadius * 0.12 * (1 - (p * 0.4))),
            color: icy,
            alpha: 0.32 * (1 - p)
        )
    case .doubleRing:
        strokeCircle(
            in: context,
            center: center,
            radius: baseRadius + (baseRadius * 1.3 * p),
            lineWidth: max(1.4, baseRadius * 0.11),
            color: white,
            alpha: 0.34 * (1 - p)
        )
        let delayed = max((p - 0.22) / 0.78, 0)
        if delayed > 0 {
            strokeCircle(
                in: context,
                center: center,
                radius: baseRadius * 0.85 + (baseRadius * 1.9 * delayed),
                lineWidth: max(1.2, baseRadius * 0.1),
                color: icy,
                alpha: 0.24 * (1 - delayed)
            )
        }
    case .softGlow:
        fillCircle(
            in: context,
            center: center,
            radius: baseRadius * (0.6 + (0.9 * p)),
            color: icy,
            alpha: 0.18 * (1 - p)
        )
        fillCircle(
            in: context,
            center: center,
            radius: baseRadius * (1.0 + (1.6 * p)),
            color: white,
            alpha: 0.08 * (1 - p)
        )
    case .radarPing:
        strokeCircle(
            in: context,
            center: center,
            radius: baseRadius * 0.8 + (baseRadius * 2.6 * p),
            lineWidth: max(1.2, baseRadius * 0.1 * (1 - (p * 0.25))),
            color: icy,
            alpha: 0.3 * (1 - p)
        )
        fillCircle(
            in: context,
            center: center,
            radius: baseRadius * 0.22,
            color: white,
            alpha: 0.18 * (1 - (p * 0.6))
        )
    case .expandingDot:
        fillCircle(
            in: context,
            center: center,
            radius: baseRadius * (0.24 + (0.8 * p)),
            color: white,
            alpha: 0.24 * (1 - p)
        )
    }
}

private func strokeCircle(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat,
    color: CGColor,
    alpha: CGFloat
) {
    guard alpha > 0.001 else { return }
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.setStrokeColor(color.copy(alpha: alpha) ?? color)
    context.setLineWidth(lineWidth)
    context.strokeEllipse(in: rect)
}

private func fillCircle(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color: CGColor,
    alpha: CGFloat
) {
    guard alpha > 0.001 else { return }
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.setFillColor(color.copy(alpha: alpha) ?? color)
    context.fillEllipse(in: rect)
}

private func configureVideoComposition(
    _ videoComposition: AVVideoComposition,
    renderSize: CGSize,
    frameDuration: CMTime
) {
    // Preserve the existing output sizing while using the non-deprecated composition factory.
    videoComposition.setValue(NSValue(size: renderSize), forKey: #keyPath(AVVideoComposition.renderSize))
    videoComposition.setValue(NSValue(time: frameDuration), forKey: #keyPath(AVVideoComposition.frameDuration))
}
