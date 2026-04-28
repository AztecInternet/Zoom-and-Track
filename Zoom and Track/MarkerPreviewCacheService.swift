import AVFoundation
import CryptoKit
import Foundation

final class MarkerPreviewCacheService {
    private let fileManager = FileManager.default
    private let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    private let previewRenderVersion = 3

    func cachedPreview(
        for recordingURL: URL,
        summary: RecordingInspectionSummary,
        marker: ZoomPlanItem
    ) async throws -> RenderedMarkerPreview? {
        let cacheURL = try await cacheURL(for: recordingURL, summary: summary, marker: marker)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        guard try await isPlayablePreview(at: cacheURL) else {
            try? fileManager.removeItem(at: cacheURL)
            return nil
        }

        let bounds = previewBounds(for: marker)
        return RenderedMarkerPreview(
            outputURL: cacheURL,
            sourceStartTime: bounds.startTime,
            sourceEndTime: bounds.endTime,
            deleteWhenFinished: false
        )
    }

    func storePreview(
        _ renderedPreview: RenderedMarkerPreview,
        for recordingURL: URL,
        summary: RecordingInspectionSummary,
        marker: ZoomPlanItem
    ) async throws -> RenderedMarkerPreview {
        let cacheURL = try await cacheURL(for: recordingURL, summary: summary, marker: marker)
        try ensureCacheDirectoryExists()
        try? fileManager.removeItem(at: cacheURL)
        try fileManager.moveItem(at: renderedPreview.outputURL, to: cacheURL)
        pruneStaleFiles()

        return RenderedMarkerPreview(
            outputURL: cacheURL,
            sourceStartTime: renderedPreview.sourceStartTime,
            sourceEndTime: renderedPreview.sourceEndTime,
            deleteWhenFinished: false
        )
    }

    func pruneStaleFiles() {
        guard let directoryEnumerator = fileManager.enumerator(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = Date().addingTimeInterval(-cacheLifetime)
        for case let fileURL as URL in directoryEnumerator {
            guard fileURL.pathExtension == "mov" else { continue }
            guard
                let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                resourceValues.isRegularFile == true
            else {
                continue
            }

            if let modificationDate = resourceValues.contentModificationDate, modificationDate < expirationDate {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private var cacheDirectoryURL: URL {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return cachesURL
            .appendingPathComponent("FlowTrack Capture", isDirectory: true)
            .appendingPathComponent("MarkerPreviews", isDirectory: true)
    }

    private func ensureCacheDirectoryExists() throws {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private func cacheURL(
        for recordingURL: URL,
        summary: RecordingInspectionSummary,
        marker: ZoomPlanItem
    ) async throws -> URL {
        try ensureCacheDirectoryExists()
        let key = try await cacheKey(for: recordingURL, summary: summary, marker: marker)
        return cacheDirectoryURL
            .appendingPathComponent(key)
            .appendingPathExtension("mov")
    }

    private func cacheKey(
        for recordingURL: URL,
        summary: RecordingInspectionSummary,
        marker: ZoomPlanItem
    ) async throws -> String {
        let fileAttributes = try fileManager.attributesOfItem(atPath: recordingURL.path)
        let fileModificationDate = (fileAttributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0
        let renderSize = try await renderSize(for: recordingURL)

        let keyMaterial = [
            "recordingPath=\(recordingURL.standardizedFileURL.path)",
            "recordingModificationDate=\(fileModificationDate)",
            "recordingFileSize=\(fileSize)",
            "markerID=\(marker.id)",
            "sourceEventTimestamp=\(marker.sourceEventTimestamp)",
            "centerX=\(marker.centerX)",
            "centerY=\(marker.centerY)",
            "rawX=\(marker.rawX.map(String.init(describing:)) ?? "none")",
            "rawY=\(marker.rawY.map(String.init(describing:)) ?? "none")",
            "leadInTime=\(marker.leadInTime)",
            "zoomInDuration=\(marker.zoomInDuration)",
            "holdDuration=\(marker.holdDuration)",
            "zoomOutDuration=\(marker.zoomOutDuration)",
            "zoomScale=\(marker.zoomScale)",
            "zoomType=\(marker.zoomType.rawValue)",
            "easeStyle=\(marker.easeStyle.rawValue)",
            "bounceAmount=\(marker.bounceAmount)",
            "clickPulsePreset=\(marker.clickPulse?.preset.rawValue ?? "none")",
            "enabled=\(marker.enabled)",
            "renderWidth=\(renderSize.width)",
            "renderHeight=\(renderSize.height)",
            "previewRenderVersion=\(previewRenderVersion)",
            "contentWidth=\(summary.contentCoordinateSize.width)",
            "contentHeight=\(summary.contentCoordinateSize.height)"
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(keyMaterial.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func renderSize(for recordingURL: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: recordingURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw NSError(
                domain: "MarkerPreviewCacheService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The recording is missing a video track."]
            )
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            throw NSError(
                domain: "MarkerPreviewCacheService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The recording has an invalid video size."]
            )
        }
        return cappedRenderSize(for: orientedSize, maxWidth: 1440)
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

    private func isPlayablePreview(at url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { return false }
        let duration = try await asset.load(.duration)
        return duration.isValid && duration.seconds.isFinite && duration.seconds > 0.05
    }
}
