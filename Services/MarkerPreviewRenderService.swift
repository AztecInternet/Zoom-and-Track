@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import CoreImage
import Foundation

private struct DistortionImportedColorMaskSet {
    let red: CIImage?
    let blue: CIImage?
    let cyan: CIImage?
}

private let distortionColorMaskContext = CIContext()
private let distortionColorMaskCache = DistortionColorMaskCache()

private final class DistortionColorMaskCache {
    private let lock = NSLock()
    private var storage: [String: DistortionImportedColorMaskSet] = [:]

    func value(for key: String) -> DistortionImportedColorMaskSet? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func store(_ value: DistortionImportedColorMaskSet, for key: String) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }
}

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
    private let projectBundleService = ProjectBundleService()
    private var importedDistortionMapCache: [String: CIImage] = [:]

    private func importedDistortionMapImage(for mapID: String) -> CIImage? {
        if let cached = importedDistortionMapCache[mapID] {
            return cached
        }

        guard let mapURL = try? projectBundleService.distortionImportedMapURL(for: mapID),
              let image = CIImage(contentsOf: mapURL) else {
            return nil
        }

        importedDistortionMapCache[mapID] = image
        return image
    }

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
                sourceImage: image.cropped(to: outputRect),
                importedDistortionMapProvider: { [weak self] in self?.importedDistortionMapImage(for: $0) }
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
                sourceImage: image.cropped(to: outputRect),
                importedDistortionMapProvider: { [weak self] in self?.importedDistortionMapImage(for: $0) }
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

    func renderDistortionLoupeFrame(
        recordingURL: URL,
        summary: RecordingInspectionSummary,
        selectedMarker: EffectPlanItem,
        time: Double,
        normalizedPoint: CGPoint,
        loupeSize: CGSize = CGSize(width: 280, height: 180)
    ) async throws -> NSImage? {
        guard let focusRegion = selectedMarker.focusRegion else {
            return nil
        }

        let asset = AVURLAsset(url: recordingURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            return nil
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            return nil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let cgImage = try await generator.image(
            at: CMTime(seconds: max(time, 0), preferredTimescale: 600)
        ).image

        let baseOrientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
        )
        let outputSize = cappedRenderSize(for: orientedSize, maxWidth: 960)
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let baseScale = outputSize.width / orientedSize.width
        let contentCoordinateSize = summary.contentCoordinateSize
        let previewState = SharedMotionEngine.activeZoomState(
            at: time,
            zoomMarkers: summary.zoomMarkers,
            contentCoordinateSize: contentCoordinateSize,
            coordinateSpace: .bottomLeft
        )

        var image = CIImage(cgImage: cgImage).transformed(by: baseOrientationTransform)
        image = image.transformed(by: CGAffineTransform(scaleX: baseScale, y: baseScale))

        if let previewState {
            let offset = SharedMotionEngine.previewOffset(for: previewState, outputSize: outputSize)
            image = image.transformed(by: CGAffineTransform(scaleX: previewState.scale, y: previewState.scale))
            image = image.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height))
        }

        let effectImage = makeEffectOverlay(
            at: time,
            effectMarkers: summary.effectMarkers,
            contentCoordinateSize: contentCoordinateSize,
            orientedVideoSize: orientedSize,
            outputSize: outputSize,
            previewState: previewState,
            sourceImage: image.cropped(to: outputRect),
            importedDistortionMapProvider: { [weak self] in self?.importedDistortionMapImage(for: $0) }
        )?.cropped(to: outputRect) ?? image.cropped(to: outputRect)

        let contentPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1) * contentCoordinateSize.width,
            y: min(max(normalizedPoint.y, 0), 1) * contentCoordinateSize.height
        )
        let resolvedPoint = SharedMotionEngine.resolveOverlayPoint(
            contentPoint: contentPoint,
            contentCoordinateSize: contentCoordinateSize,
            orientedVideoSize: orientedSize,
            outputSize: outputSize,
            previewState: previewState
        ).point

        let focusSourceRect = CGRect(
            x: (focusRegion.centerX - (focusRegion.width / 2)) * contentCoordinateSize.width,
            y: (focusRegion.centerY - (focusRegion.height / 2)) * contentCoordinateSize.height,
            width: focusRegion.width * contentCoordinateSize.width,
            height: focusRegion.height * contentCoordinateSize.height
        )
        let focusTopLeft = SharedMotionEngine.resolveOverlayPoint(
            contentPoint: CGPoint(x: focusSourceRect.minX, y: focusSourceRect.minY),
            contentCoordinateSize: contentCoordinateSize,
            orientedVideoSize: orientedSize,
            outputSize: outputSize,
            previewState: previewState
        ).point
        let focusBottomRight = SharedMotionEngine.resolveOverlayPoint(
            contentPoint: CGPoint(x: focusSourceRect.maxX, y: focusSourceRect.maxY),
            contentCoordinateSize: contentCoordinateSize,
            orientedVideoSize: orientedSize,
            outputSize: outputSize,
            previewState: previewState
        ).point
        let transformedFocusRect = CGRect(
            x: focusTopLeft.x,
            y: focusTopLeft.y,
            width: focusBottomRight.x - focusTopLeft.x,
            height: focusBottomRight.y - focusTopLeft.y
        ).standardized

        let desiredCropSize = CGSize(
            width: max(loupeSize.width * 2.2, transformedFocusRect.width * 1.2),
            height: max(loupeSize.height * 2.2, transformedFocusRect.height * 1.2)
        )
        let cropRect = CGRect(
            x: resolvedPoint.x - (desiredCropSize.width / 2),
            y: resolvedPoint.y - (desiredCropSize.height / 2),
            width: desiredCropSize.width,
            height: desiredCropSize.height
        ).intersection(outputRect)
        guard cropRect.width > 1, cropRect.height > 1 else {
            return nil
        }

        let loupeImage = effectImage.cropped(to: cropRect)
        guard let rendered = ciContext.createCGImage(loupeImage, from: cropRect) else {
            return nil
        }
        return NSImage(cgImage: rendered, size: cropRect.size)
    }

    func makeRealtimeEffectPreviewImage(
        pixelBuffer: CVPixelBuffer,
        at currentTime: Double,
        summary: RecordingInspectionSummary,
        effectMarkers: [EffectPlanItem],
        outputSize: CGSize,
        preferredTransform: CGAffineTransform,
        orientedVideoSize: CGSize
    ) -> CIImage? {
        guard outputSize.width > 0,
              outputSize.height > 0,
              orientedVideoSize.width > 0,
              orientedVideoSize.height > 0 else {
            return nil
        }

        let outputRect = CGRect(origin: .zero, size: outputSize)
        let baseOrientationTransform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -CGRect(origin: .zero, size: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )).applying(preferredTransform).origin.x,
                y: -CGRect(origin: .zero, size: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )).applying(preferredTransform).origin.y
            )
        )
        let baseScale = outputSize.width / orientedVideoSize.width
        let previewState = SharedMotionEngine.activeZoomState(
            at: currentTime,
            zoomMarkers: summary.zoomMarkers,
            contentCoordinateSize: summary.contentCoordinateSize,
            coordinateSpace: .bottomLeft
        )

        var image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: baseOrientationTransform)
        image = image.transformed(by: CGAffineTransform(scaleX: baseScale, y: baseScale))

        if let previewState {
            let offset = SharedMotionEngine.previewOffset(for: previewState, outputSize: outputSize)
            image = image.transformed(by: CGAffineTransform(scaleX: previewState.scale, y: previewState.scale))
            image = image.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height))
        }

        return makeEffectOverlay(
            at: currentTime,
            effectMarkers: effectMarkers,
            contentCoordinateSize: summary.contentCoordinateSize,
            orientedVideoSize: orientedVideoSize,
            outputSize: outputSize,
            previewState: previewState,
            sourceImage: image.cropped(to: outputRect),
            importedDistortionMapProvider: { [weak self] in self?.importedDistortionMapImage(for: $0) }
        )?.cropped(to: outputRect)
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
    private let projectBundleService = ProjectBundleService()
    private var importedDistortionMapCache: [String: CIImage] = [:]
    private var activeExportSession: AVAssetExportSession?

    private func importedDistortionMapImage(for mapID: String) -> CIImage? {
        if let cached = importedDistortionMapCache[mapID] {
            return cached
        }

        guard let mapURL = try? projectBundleService.distortionImportedMapURL(for: mapID),
              let image = CIImage(contentsOf: mapURL) else {
            return nil
        }

        importedDistortionMapCache[mapID] = image
        return image
    }

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
                sourceImage: image.cropped(to: outputRect),
                importedDistortionMapProvider: { [weak self] in self?.importedDistortionMapImage(for: $0) }
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
    let distortionIntensity: Double
    let distortion: DistortionConfiguration?
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
    sourceImage: CIImage? = nil,
    importedDistortionMapProvider: ((String) -> CIImage?)? = nil
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

    if effectState.style == .distortion || effectState.style == .heatHazeEdge,
       let sourceImage {
        let outsideMaskImage = maskImage
            .applyingFilter("CIColorInvert")
            .cropped(to: outputRect)
        let distortion = effectState.distortion ?? .defaultConfiguration
        let blendAmount = min(max(distortion.backgroundBlend, 0), 1)
        let blendMaskImage = outsideMaskImage.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: blendAmount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: blendAmount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blendAmount, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: blendAmount)
            ]
        )
        let displacementMap = makeDistortionBackgroundDisplacementMap(
            outputSize: outputSize,
            outsideMaskImage: outsideMaskImage,
            distortion: distortion,
            intensity: effectState.distortionIntensity,
            importedDistortionMapProvider: importedDistortionMapProvider
        )
        let displacedImage = sourceImage
            .clampedToExtent()
            .applyingFilter(
                "CIDisplacementDistortion",
                parameters: [
                    "inputDisplacementImage": displacementMap,
                    kCIInputScaleKey: distortionDisplacementScale(
                        preset: distortion.preset,
                        intensity: effectState.distortionIntensity
                    )
                ]
            )
            .cropped(to: outputRect)
        let softenedDisplacedImage = displacedImage
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: distortionBackgroundBlurRadius(
                    blur: distortion.backgroundBlur,
                    intensity: effectState.distortionIntensity
                )]
            )
            .cropped(to: outputRect)

        outputImage = softenedDisplacedImage
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: sourceImage.cropped(to: outputRect),
                    kCIInputMaskImageKey: blendMaskImage
                ]
            )
            .cropped(to: outputRect)

        if let colorEffectOverlay = makeDistortionImportedColorEffectOverlay(
            outputRect: outputRect,
            outsideMaskImage: outsideMaskImage,
            distortion: distortion,
            intensity: effectState.distortionIntensity,
            currentTime: currentTime,
            importedDistortionMapProvider: importedDistortionMapProvider
        ), let baseImage = outputImage {
            outputImage = colorEffectOverlay
                .applyingFilter(
                    "CIScreenBlendMode",
                    parameters: [kCIInputBackgroundImageKey: baseImage]
                )
                .cropped(to: outputRect)
        }
    }

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
    let distortionIntensity = timingIntensity * min(max(marker.amount, 0), 1)
    let tintIntensity = timingIntensity * min(max(marker.tintAmount, 0), 1)

    guard max(blurIntensity, darkenIntensity, distortionIntensity, tintIntensity) > 0 else { return nil }

    return EffectRenderState(
        style: marker.style,
        region: region,
        blurIntensity: blurIntensity,
        darkenIntensity: darkenIntensity,
        distortionIntensity: distortionIntensity,
        distortion: marker.distortion,
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
    case .distortion:
        return .clear
    case .heatHazeEdge:
        return .clear
    case .tint:
        return state.tintColor.withAlphaComponent(0.42 * state.tintIntensity)
    case .blur:
        return .clear
    }
}

private func makeDistortionBackgroundDisplacementMap(
    outputSize: CGSize,
    outsideMaskImage: CIImage,
    distortion: DistortionConfiguration,
    intensity: Double,
    importedDistortionMapProvider: ((String) -> CIImage?)?
) -> CIImage {
    let outputRect = CGRect(origin: .zero, size: outputSize)
    let neutralMap = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        .cropped(to: outputRect)

    let basePattern: CIImage
    switch distortion.mapSource {
    case .preset:
        basePattern = makeBuiltInDistortionBackgroundDisplacementMap(
            outputSize: outputSize,
            distortion: distortion
        )
    case .importedMap(let id):
        if let importedImage = importedDistortionMapProvider?(id) {
            basePattern = fittedDistortionImportedMap(
                importedImage,
                outputRect: outputRect
            )
        } else {
            basePattern = makeBuiltInDistortionBackgroundDisplacementMap(
                outputSize: outputSize,
                distortion: distortion
            )
        }
    }

    let maskedPattern = basePattern
        .applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: neutralMap,
                kCIInputMaskImageKey: outsideMaskImage
            ]
        )
        .cropped(to: outputRect)

    return maskedPattern
        .applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1 + (2.4 * intensity)
            ]
        )
        .cropped(to: outputRect)
}

private func makeBuiltInDistortionBackgroundDisplacementMap(
    outputSize: CGSize,
    distortion: DistortionConfiguration
) -> CIImage {
    let outputRect = CGRect(origin: .zero, size: outputSize)
    let coarseWidthMultiplier: Double
    let fineWidthMultiplier: Double
    let coarseBlur: Double
    let fineBlur: Double
    let color0: CIColor
    let color1: CIColor

    switch distortion.preset {
    case .atmospheric:
        coarseWidthMultiplier = 0.14
        fineWidthMultiplier = 0.075
        coarseBlur = 34
        fineBlur = 16
        color0 = CIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        color1 = CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    case .heatHaze:
        coarseWidthMultiplier = 0.11
        fineWidthMultiplier = 0.06
        coarseBlur = 24
        fineBlur = 12
        color0 = CIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        color1 = CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    }

    let coarsePattern = CIFilter(
        name: "CICheckerboardGenerator",
        parameters: [
            "inputCenter": CIVector(x: outputSize.width * 0.5, y: outputSize.height * 0.5),
            "inputColor0": color0,
            "inputColor1": color1,
            "inputWidth": max(min(outputSize.width, outputSize.height) * (coarseWidthMultiplier * max(distortion.scale, 0.2)), 20),
            "inputSharpness": 0
        ]
    )!.outputImage!
        .transformed(by: CGAffineTransform(rotationAngle: 0.31))
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: coarseBlur * max(distortion.scale, 0.2)])
        .cropped(to: outputRect)

    let finePattern = CIFilter(
        name: "CICheckerboardGenerator",
        parameters: [
            "inputCenter": CIVector(x: outputSize.width * 0.5, y: outputSize.height * 0.5),
            "inputColor0": color0,
            "inputColor1": color1,
            "inputWidth": max(min(outputSize.width, outputSize.height) * (fineWidthMultiplier * max(distortion.scale, 0.2)), 10),
            "inputSharpness": 0
        ]
    )!.outputImage!
        .transformed(by: CGAffineTransform(rotationAngle: -0.47))
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: fineBlur * max(distortion.scale, 0.2)])
        .cropped(to: outputRect)

    let blendedPattern = coarsePattern
        .applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: finePattern])
        .cropped(to: outputRect)

    return blendedPattern.cropped(to: outputRect)
}

private func makeDistortionImportedColorEffectOverlay(
    outputRect: CGRect,
    outsideMaskImage: CIImage,
    distortion: DistortionConfiguration,
    intensity: Double,
    currentTime: Double,
    importedDistortionMapProvider: ((String) -> CIImage?)?
) -> CIImage? {
    guard case .importedMap(let mapID) = distortion.mapSource,
          let importedImage = importedDistortionMapProvider?(mapID),
          let masks = importedDistortionColorMasks(
            for: importedImage,
            mapID: mapID,
            importedMapHash: distortion.importedMapHash,
            outputRect: outputRect
          ) else {
        return nil
    }

    let glowStrength = max(distortion.colorEffectGlowStrength, 0)
    let glowRadiusMultiplier = 0.55 + (max(distortion.colorEffectGlowRadius, 0) * 1.35)
    let animationIntensity = max(distortion.colorEffectAnimationIntensity, 0)
    let palette = colorEffectPaletteDefinition(for: distortion.colorEffectPalette)
    let motionProfile = colorEffectMotionProfile(for: distortion.colorEffectPalette)
    let baseSeed = normalizedMotionSeed(for: "\(mapID)|\(distortion.colorEffectPalette.rawValue)")
    let glitchState = organicColorGlitchState(
        outputRect: outputRect,
        currentTime: currentTime,
        seedKey: "\(mapID)|\(distortion.importedMapHash ?? "none")|\(distortion.colorEffectPalette.rawValue)",
        animationIntensity: animationIntensity
    )
    let blueAnimation = animatedColorEffectState(
        currentTime: currentTime,
        seed: baseSeed + 0.11,
        profile: motionProfile,
        channelBias: 0.96,
        animationIntensity: animationIntensity
    )
    let redAnimation = animatedColorEffectState(
        currentTime: currentTime,
        seed: baseSeed + 0.47,
        profile: motionProfile,
        channelBias: 1.02,
        animationIntensity: animationIntensity
    )
    let cyanAnimation = animatedColorEffectState(
        currentTime: currentTime,
        seed: baseSeed + 0.79,
        profile: motionProfile,
        channelBias: 1.08,
        animationIntensity: animationIntensity
    )

    let overlays = [
        makeMaskedGlowOverlay(
            maskImage: masks.blue,
            outsideMaskImage: outsideMaskImage,
            outputRect: outputRect,
            innerGlowColor: palette.blueInner,
            outerGlowColor: palette.blueOuter,
            glowOpacity: palette.blueOpacity * (0.7 + (glowStrength * 1.1)) * intensity * blueAnimation.opacityMultiplier,
            innerBlurRadius: 18 * glowRadiusMultiplier * blueAnimation.innerRadiusMultiplier,
            outerBlurRadius: 34 * glowRadiusMultiplier * blueAnimation.outerRadiusMultiplier
        ),
        makeMaskedGlowOverlay(
            maskImage: masks.red,
            outsideMaskImage: outsideMaskImage,
            outputRect: outputRect,
            innerGlowColor: palette.redInner,
            outerGlowColor: palette.redOuter,
            glowOpacity: palette.redOpacity * (0.62 + (glowStrength * 0.95)) * intensity * redAnimation.opacityMultiplier,
            innerBlurRadius: 16 * glowRadiusMultiplier * redAnimation.innerRadiusMultiplier,
            outerBlurRadius: 30 * glowRadiusMultiplier * redAnimation.outerRadiusMultiplier
        ),
        makeMaskedGlowOverlay(
            maskImage: masks.cyan,
            outsideMaskImage: outsideMaskImage,
            outputRect: outputRect,
            innerGlowColor: palette.cyanInner,
            outerGlowColor: palette.cyanOuter,
            glowOpacity: palette.cyanOpacity * (0.84 + (glowStrength * 1.2)) * intensity * cyanAnimation.opacityMultiplier,
            innerBlurRadius: 14 * glowRadiusMultiplier * cyanAnimation.innerRadiusMultiplier,
            outerBlurRadius: 28 * glowRadiusMultiplier * cyanAnimation.outerRadiusMultiplier
        )
    ].compactMap { $0 }

    let glitchOverlays = [
        makeOrganicGlitchGlowOverlay(
            maskImage: masks.blue,
            outsideMaskImage: outsideMaskImage,
            outputRect: outputRect,
            channel: .blue,
            glitchState: glitchState,
            innerGlowColor: palette.blueInner,
            outerGlowColor: palette.blueOuter,
            glowOpacity: palette.blueOpacity * (0.7 + (glowStrength * 1.1)) * intensity * blueAnimation.opacityMultiplier,
            innerBlurRadius: 18 * glowRadiusMultiplier * blueAnimation.innerRadiusMultiplier,
            outerBlurRadius: 34 * glowRadiusMultiplier * blueAnimation.outerRadiusMultiplier
        ),
        makeOrganicGlitchGlowOverlay(
            maskImage: masks.red,
            outsideMaskImage: outsideMaskImage,
            outputRect: outputRect,
            channel: .red,
            glitchState: glitchState,
            innerGlowColor: palette.redInner,
            outerGlowColor: palette.redOuter,
            glowOpacity: palette.redOpacity * (0.62 + (glowStrength * 0.95)) * intensity * redAnimation.opacityMultiplier,
            innerBlurRadius: 16 * glowRadiusMultiplier * redAnimation.innerRadiusMultiplier,
            outerBlurRadius: 30 * glowRadiusMultiplier * redAnimation.outerRadiusMultiplier
        ),
        makeOrganicGlitchGlowOverlay(
            maskImage: masks.cyan,
            outsideMaskImage: outsideMaskImage,
            outputRect: outputRect,
            channel: .cyan,
            glitchState: glitchState,
            innerGlowColor: palette.cyanInner,
            outerGlowColor: palette.cyanOuter,
            glowOpacity: palette.cyanOpacity * (0.84 + (glowStrength * 1.2)) * intensity * cyanAnimation.opacityMultiplier,
            innerBlurRadius: 14 * glowRadiusMultiplier * cyanAnimation.innerRadiusMultiplier,
            outerBlurRadius: 28 * glowRadiusMultiplier * cyanAnimation.outerRadiusMultiplier
        )
    ].compactMap { $0 }

    let allOverlays = overlays + glitchOverlays

    guard let firstOverlay = allOverlays.first else {
        return nil
    }

    return allOverlays.dropFirst().reduce(firstOverlay) { partial, overlay in
        overlay
            .applyingFilter(
                "CISourceOverCompositing",
                parameters: [kCIInputBackgroundImageKey: partial]
            )
            .cropped(to: outputRect)
    }
}

private func makeMaskedGlowOverlay(
    maskImage: CIImage?,
    outsideMaskImage: CIImage,
    outputRect: CGRect,
    innerGlowColor: CIColor,
    outerGlowColor: CIColor,
    glowOpacity: Double,
    innerBlurRadius: Double,
    outerBlurRadius: Double
) -> CIImage? {
    guard let maskImage, glowOpacity > 0.001 else {
        return nil
    }

    let effectiveMask = maskImage
        .applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: outsideMaskImage]
        )
        .applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1.15, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.15, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.15, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.4)
            ]
        )
        .cropped(to: outputRect)
    let transparentImage = CIImage(color: .clear).cropped(to: outputRect)
    let clampedGlowOpacity = min(max(glowOpacity, 0), 2.4)
    let centerCutoutMask = effectiveMask
        .cropped(to: outputRect)
    let innerHaloMask = haloMask(
        from: effectiveMask,
        centerCutoutMask: centerCutoutMask,
        expansionRadius: max(innerBlurRadius * 0.18, 2.5),
        blurRadius: max(innerBlurRadius, 8),
        alphaScale: min(1.0 + (clampedGlowOpacity * 0.2), 1.45),
        outputRect: outputRect
    )
    .applyingFilter(
        "CIMultiplyCompositing",
        parameters: [kCIInputBackgroundImageKey: outsideMaskImage]
    )
    .cropped(to: outputRect)
    let outerHaloMask = haloMask(
        from: effectiveMask,
        centerCutoutMask: centerCutoutMask,
        expansionRadius: max(outerBlurRadius * 0.22, 5.0),
        blurRadius: max(outerBlurRadius, 16),
        alphaScale: min(0.95 + (clampedGlowOpacity * 0.16), 1.3),
        outputRect: outputRect
    )
    .applyingFilter(
        "CIMultiplyCompositing",
        parameters: [kCIInputBackgroundImageKey: outsideMaskImage]
    )
    .cropped(to: outputRect)

    let innerGlow = maskedColorPlate(
        color: innerGlowColor,
        opacity: clampedGlowOpacity,
        mask: innerHaloMask,
        outputRect: outputRect,
        transparentImage: transparentImage
    )
    let outerGlow = maskedColorPlate(
        color: outerGlowColor,
        opacity: min(clampedGlowOpacity * 0.92, 2.2),
        mask: outerHaloMask,
        outputRect: outputRect,
        transparentImage: transparentImage
    )
    let stackedGlow = outerGlow
        .applyingFilter(
            "CISourceOverCompositing",
            parameters: [kCIInputBackgroundImageKey: innerGlow]
        )
        .applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: outsideMaskImage]
        )
        .cropped(to: outputRect)

    return stackedGlow
}

private func haloMask(
    from baseMask: CIImage,
    centerCutoutMask: CIImage,
    expansionRadius: Double,
    blurRadius: Double,
    alphaScale: Double,
    outputRect: CGRect
) -> CIImage {
    baseMask
        .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: expansionRadius])
        .cropped(to: outputRect)
        .clampedToExtent()
        .applyingFilter(
            "CISubtractBlendMode",
            parameters: [kCIInputBackgroundImageKey: centerCutoutMask]
        )
        .cropped(to: outputRect)
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        .cropped(to: outputRect)
        .applyingFilter(
            "CISubtractBlendMode",
            parameters: [kCIInputBackgroundImageKey: centerCutoutMask]
        )
        .cropped(to: outputRect)
        .applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alphaScale)
            ]
        )
        .cropped(to: outputRect)
}

private struct DistortionColorPaletteDefinition {
    let redInner: CIColor
    let redOuter: CIColor
    let redOpacity: Double
    let blueInner: CIColor
    let blueOuter: CIColor
    let blueOpacity: Double
    let cyanInner: CIColor
    let cyanOuter: CIColor
    let cyanOpacity: Double
}

private struct DistortionColorMotionProfile {
    let primaryFrequency: Double
    let secondaryFrequency: Double
    let flareFrequency: Double
    let pulseAmplitude: Double
    let driftAmplitude: Double
    let radiusAmplitude: Double
    let flareAmplitude: Double
    let flareSharpness: Double
}

private struct DistortionColorAnimationState {
    let opacityMultiplier: Double
    let innerRadiusMultiplier: Double
    let outerRadiusMultiplier: Double
}

private enum DistortionColorGlitchChannel {
    case red
    case blue
    case cyan
}

private struct DistortionColorGlitchState {
    let channel: DistortionColorGlitchChannel
    let region: CGRect
    let offsets: [CGSize]
    let opacityMultiplier: Double
    let radiusMultiplier: Double
}

private func colorEffectPaletteDefinition(for palette: DistortionColorEffectPalette) -> DistortionColorPaletteDefinition {
    switch palette {
    case .ember:
        return DistortionColorPaletteDefinition(
            redInner: CIColor(red: 1.0, green: 0.56, blue: 0.18, alpha: 1),
            redOuter: CIColor(red: 1.0, green: 0.14, blue: 0.08, alpha: 1),
            redOpacity: 1.05,
            blueInner: CIColor(red: 1.0, green: 0.74, blue: 0.22, alpha: 1),
            blueOuter: CIColor(red: 1.0, green: 0.34, blue: 0.08, alpha: 1),
            blueOpacity: 0.94,
            cyanInner: CIColor(red: 1.0, green: 0.9, blue: 0.56, alpha: 1),
            cyanOuter: CIColor(red: 1.0, green: 0.46, blue: 0.14, alpha: 1),
            cyanOpacity: 1.12
        )
    case .electric:
        return DistortionColorPaletteDefinition(
            redInner: CIColor(red: 1.0, green: 0.24, blue: 0.7, alpha: 1),
            redOuter: CIColor(red: 0.54, green: 0.0, blue: 1.0, alpha: 1),
            redOpacity: 1.0,
            blueInner: CIColor(red: 0.4, green: 0.82, blue: 1.0, alpha: 1),
            blueOuter: CIColor(red: 0.18, green: 0.28, blue: 1.0, alpha: 1),
            blueOpacity: 1.08,
            cyanInner: CIColor(red: 0.74, green: 1.0, blue: 1.0, alpha: 1),
            cyanOuter: CIColor(red: 0.18, green: 0.56, blue: 1.0, alpha: 1),
            cyanOpacity: 1.18
        )
    case .plasma:
        return DistortionColorPaletteDefinition(
            redInner: CIColor(red: 1.0, green: 0.46, blue: 0.18, alpha: 1),
            redOuter: CIColor(red: 1.0, green: 0.06, blue: 0.36, alpha: 1),
            redOpacity: 1.0,
            blueInner: CIColor(red: 0.28, green: 0.82, blue: 1.0, alpha: 1),
            blueOuter: CIColor(red: 0.44, green: 0.24, blue: 1.0, alpha: 1),
            blueOpacity: 1.04,
            cyanInner: CIColor(red: 0.7, green: 1.0, blue: 0.98, alpha: 1),
            cyanOuter: CIColor(red: 0.48, green: 0.86, blue: 1.0, alpha: 1),
            cyanOpacity: 1.14
        )
    case .frost:
        return DistortionColorPaletteDefinition(
            redInner: CIColor(red: 0.9, green: 0.96, blue: 1.0, alpha: 1),
            redOuter: CIColor(red: 0.52, green: 0.76, blue: 1.0, alpha: 1),
            redOpacity: 0.92,
            blueInner: CIColor(red: 0.78, green: 0.94, blue: 1.0, alpha: 1),
            blueOuter: CIColor(red: 0.34, green: 0.58, blue: 1.0, alpha: 1),
            blueOpacity: 1.0,
            cyanInner: CIColor(red: 0.96, green: 1.0, blue: 1.0, alpha: 1),
            cyanOuter: CIColor(red: 0.6, green: 0.88, blue: 1.0, alpha: 1),
            cyanOpacity: 1.08
        )
    case .ghost:
        return DistortionColorPaletteDefinition(
            redInner: CIColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1),
            redOuter: CIColor(red: 0.76, green: 0.8, blue: 1.0, alpha: 1),
            redOpacity: 0.78,
            blueInner: CIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1),
            blueOuter: CIColor(red: 0.6, green: 0.72, blue: 1.0, alpha: 1),
            blueOpacity: 0.84,
            cyanInner: CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            cyanOuter: CIColor(red: 0.82, green: 0.9, blue: 1.0, alpha: 1),
            cyanOpacity: 0.94
        )
    }
}

private func colorEffectMotionProfile(for palette: DistortionColorEffectPalette) -> DistortionColorMotionProfile {
    switch palette {
    case .ember:
        return DistortionColorMotionProfile(
            primaryFrequency: 0.62,
            secondaryFrequency: 1.14,
            flareFrequency: 1.9,
            pulseAmplitude: 0.14,
            driftAmplitude: 0.08,
            radiusAmplitude: 0.1,
            flareAmplitude: 0.22,
            flareSharpness: 6.5
        )
    case .electric:
        return DistortionColorMotionProfile(
            primaryFrequency: 1.35,
            secondaryFrequency: 2.6,
            flareFrequency: 4.8,
            pulseAmplitude: 0.12,
            driftAmplitude: 0.1,
            radiusAmplitude: 0.08,
            flareAmplitude: 0.18,
            flareSharpness: 10.0
        )
    case .plasma:
        return DistortionColorMotionProfile(
            primaryFrequency: 0.88,
            secondaryFrequency: 1.72,
            flareFrequency: 3.1,
            pulseAmplitude: 0.15,
            driftAmplitude: 0.09,
            radiusAmplitude: 0.11,
            flareAmplitude: 0.16,
            flareSharpness: 7.5
        )
    case .frost:
        return DistortionColorMotionProfile(
            primaryFrequency: 0.54,
            secondaryFrequency: 0.92,
            flareFrequency: 1.4,
            pulseAmplitude: 0.08,
            driftAmplitude: 0.06,
            radiusAmplitude: 0.07,
            flareAmplitude: 0.08,
            flareSharpness: 5.0
        )
    case .ghost:
        return DistortionColorMotionProfile(
            primaryFrequency: 0.42,
            secondaryFrequency: 0.74,
            flareFrequency: 1.08,
            pulseAmplitude: 0.06,
            driftAmplitude: 0.05,
            radiusAmplitude: 0.05,
            flareAmplitude: 0.06,
            flareSharpness: 4.2
        )
    }
}

private func normalizedMotionSeed(for string: String) -> Double {
    var accumulator: UInt64 = 1469598103934665603
    for byte in string.utf8 {
        accumulator ^= UInt64(byte)
        accumulator &*= 1099511628211
    }
    let normalized = Double(accumulator % 10_000) / 10_000
    return normalized
}

private func animatedColorEffectState(
    currentTime: Double,
    seed: Double,
    profile: DistortionColorMotionProfile,
    channelBias: Double,
    animationIntensity: Double
) -> DistortionColorAnimationState {
    let phase = seed * .pi * 2
    let slowPulse = 0.5 + (0.5 * sin((currentTime * profile.primaryFrequency) + phase))
    let driftPulse = 0.5 + (0.5 * sin((currentTime * profile.secondaryFrequency) + (phase * 1.7)))
    let flareWave = max(0, sin((currentTime * profile.flareFrequency) + (phase * 2.3)))
    let flare = pow(flareWave, profile.flareSharpness)
    let intensityMix = 0.25 + (animationIntensity * 1.35)

    let opacityMultiplier = channelBias * (
        0.84
        + (slowPulse * profile.pulseAmplitude * intensityMix)
        + (driftPulse * profile.driftAmplitude * intensityMix)
        + (flare * profile.flareAmplitude * intensityMix)
    )
    let innerRadiusMultiplier = 0.92 + (slowPulse * profile.radiusAmplitude * 0.55 * intensityMix) + (flare * 0.05 * intensityMix)
    let outerRadiusMultiplier = 0.96 + (driftPulse * profile.radiusAmplitude * intensityMix) + (flare * 0.08 * intensityMix)

    return DistortionColorAnimationState(
        opacityMultiplier: opacityMultiplier,
        innerRadiusMultiplier: innerRadiusMultiplier,
        outerRadiusMultiplier: outerRadiusMultiplier
    )
}

private func organicColorGlitchState(
    outputRect: CGRect,
    currentTime: Double,
    seedKey: String,
    animationIntensity: Double
) -> DistortionColorGlitchState? {
    guard animationIntensity > 0.02, outputRect.width > 1, outputRect.height > 1 else {
        return nil
    }

    let slotDuration = 0.46
    let slotIndex = Int(floor(max(currentTime, 0) / slotDuration))
    let slotTime = currentTime - (Double(slotIndex) * slotDuration)
    let eventSeedKey = "\(seedKey)|organic-glitch|\(slotIndex)"
    let eventChance = normalizedMotionSeed(for: "\(eventSeedKey)|chance")
    let chanceThreshold = min(0.42 + (animationIntensity * 0.42), 0.78)
    guard eventChance <= chanceThreshold else {
        return nil
    }

    let activeDuration = 0.14 + (normalizedMotionSeed(for: "\(eventSeedKey)|duration") * 0.16)
    guard slotTime >= 0, slotTime <= activeDuration else {
        return nil
    }

    let frameIndex = Int(floor(slotTime * 42))
    let channelRoll = normalizedMotionSeed(for: "\(eventSeedKey)|channel")
    let channel: DistortionColorGlitchChannel
    if channelRoll < 0.333 {
        channel = .blue
    } else if channelRoll < 0.666 {
        channel = .red
    } else {
        channel = .cyan
    }

    let regionWidth = outputRect.width * (0.10 + (normalizedMotionSeed(for: "\(eventSeedKey)|width") * 0.22))
    let regionHeight = outputRect.height * (0.12 + (normalizedMotionSeed(for: "\(eventSeedKey)|height") * 0.26))
    let maxX = max(outputRect.width - regionWidth, 0)
    let maxY = max(outputRect.height - regionHeight, 0)
    let region = CGRect(
        x: outputRect.minX + (maxX * normalizedMotionSeed(for: "\(eventSeedKey)|x")),
        y: outputRect.minY + (maxY * normalizedMotionSeed(for: "\(eventSeedKey)|y")),
        width: regionWidth,
        height: regionHeight
    )

    let progress = slotTime / max(activeDuration, 0.001)
    let twitchEnvelope = pow(max(sin(progress * .pi), 0), 0.28)
    let movementScale = max(min(outputRect.width, outputRect.height) * 0.042, 5) * (0.48 + (animationIntensity * 1.55))
    let offsets = (0..<3).map { echoIndex in
        let echoSeed = "\(eventSeedKey)|\(frameIndex)|\(echoIndex)"
        let dxRoll = normalizedMotionSeed(for: "\(echoSeed)|dx")
        let dyRoll = normalizedMotionSeed(for: "\(echoSeed)|dy")
        let dxSign = normalizedMotionSeed(for: "\(echoSeed)|dx-sign") < 0.5 ? -1.0 : 1.0
        let dySign = normalizedMotionSeed(for: "\(echoSeed)|dy-sign") < 0.5 ? -1.0 : 1.0
        let echoScale = 1.0 - (Double(echoIndex) * 0.24)

        return CGSize(
            width: dxSign * movementScale * (0.45 + dxRoll) * twitchEnvelope * echoScale,
            height: dySign * movementScale * 0.58 * (0.28 + dyRoll) * twitchEnvelope * echoScale
        )
    }

    return DistortionColorGlitchState(
        channel: channel,
        region: region,
        offsets: offsets,
        opacityMultiplier: (0.58 + (animationIntensity * 1.2)) * twitchEnvelope,
        radiusMultiplier: 0.72 + (normalizedMotionSeed(for: "\(eventSeedKey)|radius") * 0.46)
    )
}

private func makeOrganicGlitchGlowOverlay(
    maskImage: CIImage?,
    outsideMaskImage: CIImage,
    outputRect: CGRect,
    channel: DistortionColorGlitchChannel,
    glitchState: DistortionColorGlitchState?,
    innerGlowColor: CIColor,
    outerGlowColor: CIColor,
    glowOpacity: Double,
    innerBlurRadius: Double,
    outerBlurRadius: Double
) -> CIImage? {
    guard let maskImage,
          let glitchState,
          glitchState.channel == channel,
          glitchState.opacityMultiplier > 0.001 else {
        return nil
    }

    let regionMask = makeRoundedRectMaskImage(
        outputSize: outputRect.size,
        rect: glitchState.region,
        cornerRadius: min(glitchState.region.width, glitchState.region.height) * 0.36,
        feather: max(min(glitchState.region.width, glitchState.region.height) * 0.14, 6)
    )
    .cropped(to: outputRect)
    let localMask = maskImage
        .applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: regionMask]
        )
        .cropped(to: outputRect)

    guard let baseGlitch = makeMaskedGlowOverlay(
        maskImage: localMask,
        outsideMaskImage: outsideMaskImage,
        outputRect: outputRect,
        innerGlowColor: innerGlowColor,
        outerGlowColor: outerGlowColor,
        glowOpacity: glowOpacity * glitchState.opacityMultiplier,
        innerBlurRadius: innerBlurRadius * glitchState.radiusMultiplier,
        outerBlurRadius: outerBlurRadius * glitchState.radiusMultiplier
    ) else {
        return nil
    }

    let shiftedGlows = glitchState.offsets.enumerated().map { index, offset in
        baseGlitch
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.84 - (CGFloat(index) * 0.18))
                ]
            )
            .transformed(by: CGAffineTransform(
                translationX: offset.width,
                y: offset.height
            ))
            .cropped(to: outputRect)
    }

    guard let firstGlow = shiftedGlows.first else {
        return nil
    }

    return shiftedGlows.dropFirst().reduce(firstGlow) { partial, shiftedGlow in
        shiftedGlow
            .applyingFilter(
                "CISourceOverCompositing",
                parameters: [kCIInputBackgroundImageKey: partial]
            )
            .cropped(to: outputRect)
    }
}

private func maskedColorPlate(
    color: CIColor,
    opacity: Double,
    mask: CIImage,
    outputRect: CGRect,
    transparentImage: CIImage
) -> CIImage {
    CIImage(
        color: CIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: CGFloat(opacity)
        )
    )
    .cropped(to: outputRect)
    .applyingFilter(
        "CIBlendWithMask",
        parameters: [
            kCIInputBackgroundImageKey: transparentImage,
            kCIInputMaskImageKey: mask
        ]
    )
    .cropped(to: outputRect)
}

private func fittedDistortionImportedMap(
    _ image: CIImage,
    outputRect: CGRect
) -> CIImage {
    let sourceRect = image.extent
    guard sourceRect.width > 0, sourceRect.height > 0 else {
        return image.cropped(to: outputRect)
    }

    let scale = max(outputRect.width / sourceRect.width, outputRect.height / sourceRect.height)
    let scaledWidth = sourceRect.width * scale
    let scaledHeight = sourceRect.height * scale
    let translatedImage = image
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        .transformed(by: CGAffineTransform(
            translationX: outputRect.midX - (scaledWidth / 2),
            y: outputRect.midY - (scaledHeight / 2)
        ))

    return translatedImage
        .cropped(to: outputRect)
}

private func importedDistortionColorMasks(
    for image: CIImage,
    mapID: String,
    importedMapHash: String?,
    outputRect: CGRect
) -> DistortionImportedColorMaskSet? {
    let cacheKey = [
        mapID,
        importedMapHash ?? "none",
        String(Int(outputRect.width.rounded(.toNearestOrAwayFromZero))),
        String(Int(outputRect.height.rounded(.toNearestOrAwayFromZero)))
    ].joined(separator: "|")
    if let cached = distortionColorMaskCache.value(for: cacheKey) {
        return cached
    }

    let fittedImage = fittedDistortionImportedMap(image, outputRect: outputRect)
    guard let cgImage = distortionColorMaskContext.createCGImage(fittedImage, from: outputRect),
          let rgbaData = normalizedRGBAData(from: cgImage) else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height
    var redMask = [UInt8](repeating: 0, count: width * height)
    var blueMask = [UInt8](repeating: 0, count: width * height)
    var cyanMask = [UInt8](repeating: 0, count: width * height)
    var redCount = 0
    var blueCount = 0
    var cyanCount = 0
    var maxRedMaskValue: UInt8 = 0
    var maxBlueMaskValue: UInt8 = 0
    var maxCyanMaskValue: UInt8 = 0

    for pixelIndex in 0..<(width * height) {
        let componentIndex = pixelIndex * 4
        let red = Double(rgbaData[componentIndex])
        let green = Double(rgbaData[componentIndex + 1])
        let blue = Double(rgbaData[componentIndex + 2])
        let alpha = Double(rgbaData[componentIndex + 3]) / 255

        guard alpha >= 0.06 else { continue }

        let redStrength = maskByteValue(
            normalizedStrength: redMaskStrength(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
        )
        if redStrength > 0 {
            redMask[pixelIndex] = redStrength
            redCount += 1
            maxRedMaskValue = max(maxRedMaskValue, redStrength)
        }

        let blueStrength = maskByteValue(
            normalizedStrength: blueMaskStrength(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
        )
        if blueStrength > 0 {
            blueMask[pixelIndex] = blueStrength
            blueCount += 1
            maxBlueMaskValue = max(maxBlueMaskValue, blueStrength)
        }

        let cyanStrength = maskByteValue(
            normalizedStrength: cyanMaskStrength(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
        )
        if cyanStrength > 0 {
            cyanMask[pixelIndex] = cyanStrength
            cyanCount += 1
            maxCyanMaskValue = max(maxCyanMaskValue, cyanStrength)
        }
    }

    let maskSet = DistortionImportedColorMaskSet(
        red: redCount > 0 ? makeSingleChannelMaskImage(from: redMask, width: width, height: height) : nil,
        blue: blueCount > 0 ? makeSingleChannelMaskImage(from: blueMask, width: width, height: height) : nil,
        cyan: cyanCount > 0 ? makeSingleChannelMaskImage(from: cyanMask, width: width, height: height) : nil
    )
    print(
        "Distortion color-map cache miss mapID=\(mapID) renderSize=\(width)x\(height) " +
        "redCount=\(redCount) blueCount=\(blueCount) cyanCount=\(cyanCount) " +
        "maxRed=\(maxRedMaskValue) maxBlue=\(maxBlueMaskValue) maxCyan=\(maxCyanMaskValue)"
    )
    distortionColorMaskCache.store(maskSet, for: cacheKey)
    return maskSet
}

private func redMaskStrength(red: Double, green: Double, blue: Double, alpha: Double) -> Double {
    guard red > 120, red > green * 1.6, red > blue * 1.6 else {
        return 0
    }

    let intensity = normalizedComponent(red, threshold: 120)
    let dominanceGreen = normalizedDominance(red, other: green, ratio: 1.6)
    let dominanceBlue = normalizedDominance(red, other: blue, ratio: 1.6)
    return clamp01(intensity * min(dominanceGreen, dominanceBlue) * alpha)
}

private func blueMaskStrength(red: Double, green: Double, blue: Double, alpha: Double) -> Double {
    guard blue > 120, blue > red * 1.6, blue > green * 1.6 else {
        return 0
    }

    let intensity = normalizedComponent(blue, threshold: 120)
    let dominanceRed = normalizedDominance(blue, other: red, ratio: 1.6)
    let dominanceGreen = normalizedDominance(blue, other: green, ratio: 1.6)
    return clamp01(intensity * min(dominanceRed, dominanceGreen) * alpha)
}

private func cyanMaskStrength(red: Double, green: Double, blue: Double, alpha: Double) -> Double {
    guard green > 100, blue > 100, red < 110, abs(green - blue) < 90 else {
        return 0
    }

    let greenIntensity = normalizedComponent(green, threshold: 100)
    let blueIntensity = normalizedComponent(blue, threshold: 100)
    let redSuppression = clamp01((110 - red) / 110)
    let balance = clamp01((90 - abs(green - blue)) / 90)
    return clamp01(min(greenIntensity, blueIntensity) * redSuppression * balance * alpha)
}

private func normalizedComponent(_ value: Double, threshold: Double) -> Double {
    clamp01((value - threshold) / max(255 - threshold, 1))
}

private func normalizedDominance(_ dominant: Double, other: Double, ratio: Double) -> Double {
    clamp01((dominant - (other * ratio)) / 255)
}

private func maskByteValue(normalizedStrength: Double) -> UInt8 {
    UInt8(clamp01(normalizedStrength) * 255)
}

private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func normalizedRGBAData(from cgImage: CGImage) -> [UInt8]? {
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    return pixels
}

private func makeSingleChannelMaskImage(from values: [UInt8], width: Int, height: Int) -> CIImage? {
    guard let provider = CGDataProvider(data: Data(values) as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        return nil
    }

    return CIImage(cgImage: cgImage).cropped(
        to: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    )
}

private func distortionDisplacementScale(
    preset: DistortionPreset,
    intensity: Double
) -> Double {
    switch preset {
    case .atmospheric:
        return 220 * intensity
    case .heatHaze:
        return 425 * intensity
    }
}

private func distortionBackgroundBlurRadius(
    blur: Double,
    intensity: Double
) -> Double {
    18 * min(max(blur, 0), 1) * intensity
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
