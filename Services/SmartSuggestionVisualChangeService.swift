import CoreGraphics
import Foundation

struct SmartSuggestionVisualChangeMetadata {
    let regionID: String
    let representativeTime: Double
    let changeScore: Double
    let changedRegion: CGRect?
    let changedAreaPercentage: Double
    let changeNearInteraction: Bool
    let changeFarFromInteraction: Bool
    let likelyPanelOpen: Bool
    let likelyPanelClose: Bool
    let likelyLargeTransition: Bool

    var hasVisibleChange: Bool {
        changeScore >= 0.08 || changedAreaPercentage >= 0.015
    }
}

struct SmartSuggestionVisualChangeDiagnostics {
    let analyzedRegionCount: Int
    let comparedFramePairCount: Int
    let visibleChangeRegionCount: Int
    let largeTransitionRegionCount: Int
    let elapsedSeconds: Double
    let previewLines: [String]
}

struct SmartSuggestionVisualChangeAnalysisResult {
    let metadataByRegionID: [String: SmartSuggestionVisualChangeMetadata]
    let diagnostics: SmartSuggestionVisualChangeDiagnostics
}

struct SmartSuggestionVisualChangeService {
    private struct DownsampledFrame {
        let regionID: String
        let actualTime: Double
        let width: Int
        let height: Int
        let luminance: [UInt8]
    }

    private struct FramePairChange {
        let startTime: Double
        let endTime: Double
        let changeScore: Double
        let changedRegion: CGRect?
        let changedAreaPercentage: Double
    }

    private let sampleWidth = 64
    private let sampleHeight = 36
    private let pixelDifferenceThreshold: Double = 0.11
    private let maximumPreviewLines = 12

    func analyzeChanges(
        in samples: [ActivityRegionFrameSample],
        regions: [ActivityRegion],
        contentCoordinateSize: CGSize
    ) -> SmartSuggestionVisualChangeAnalysisResult {
        let startDate = Date()
        let samplesByRegionID = Dictionary(grouping: samples, by: \.regionID)
        var metadataByRegionID: [String: SmartSuggestionVisualChangeMetadata] = [:]
        var comparedFramePairCount = 0

        for region in regions {
            guard !Task.isCancelled else { break }
            let regionSamples = (samplesByRegionID[region.id] ?? [])
                .sorted { lhs, rhs in
                    if lhs.actualTime == rhs.actualTime {
                        return lhs.requestedTime < rhs.requestedTime
                    }
                    return lhs.actualTime < rhs.actualTime
                }

            let frames = regionSamples.compactMap { sample in
                downsample(sample.image, regionID: sample.regionID, actualTime: sample.actualTime)
            }
            let pairChanges = adjacentPairs(from: frames).compactMap { before, after -> FramePairChange? in
                guard let change = compare(before: before, after: after) else { return nil }
                comparedFramePairCount += 1
                return change
            }
            let strongestChange = pairChanges.max { lhs, rhs in
                if lhs.changeScore == rhs.changeScore {
                    return lhs.changedAreaPercentage < rhs.changedAreaPercentage
                }
                return lhs.changeScore < rhs.changeScore
            }

            metadataByRegionID[region.id] = metadata(
                for: region,
                strongestChange: strongestChange,
                pairChanges: pairChanges,
                contentCoordinateSize: contentCoordinateSize
            )
        }

        let visibleChangeRegionCount = metadataByRegionID.values.filter(\.hasVisibleChange).count
        let largeTransitionRegionCount = metadataByRegionID.values.filter(\.likelyLargeTransition).count
        return SmartSuggestionVisualChangeAnalysisResult(
            metadataByRegionID: metadataByRegionID,
            diagnostics: SmartSuggestionVisualChangeDiagnostics(
                analyzedRegionCount: metadataByRegionID.count,
                comparedFramePairCount: comparedFramePairCount,
                visibleChangeRegionCount: visibleChangeRegionCount,
                largeTransitionRegionCount: largeTransitionRegionCount,
                elapsedSeconds: Date().timeIntervalSince(startDate),
                previewLines: previewLines(from: metadataByRegionID.values)
            )
        )
    }

    private func metadata(
        for region: ActivityRegion,
        strongestChange: FramePairChange?,
        pairChanges: [FramePairChange],
        contentCoordinateSize: CGSize
    ) -> SmartSuggestionVisualChangeMetadata {
        let changeScore = strongestChange?.changeScore ?? 0
        let changedRegion = strongestChange?.changedRegion
        let changedAreaPercentage = strongestChange?.changedAreaPercentage ?? 0
        let hasVisibleChange = changeScore >= 0.08 || changedAreaPercentage >= 0.015
        let changeNearInteraction = hasVisibleChange && isChangeNearInteraction(
            changedRegion: changedRegion,
            region: region,
            contentCoordinateSize: contentCoordinateSize
        )
        let changeFarFromInteraction = hasVisibleChange && !changeNearInteraction && changedAreaPercentage >= 0.02
        let moderateLocalizedChange = hasVisibleChange
            && changedAreaPercentage >= 0.04
            && changedAreaPercentage <= 0.42
            && !(strongestChange?.changedRegion?.isEmpty ?? true)

        return SmartSuggestionVisualChangeMetadata(
            regionID: region.id,
            representativeTime: region.representativeTime,
            changeScore: changeScore,
            changedRegion: changedRegion,
            changedAreaPercentage: changedAreaPercentage,
            changeNearInteraction: changeNearInteraction,
            changeFarFromInteraction: changeFarFromInteraction,
            likelyPanelOpen: moderateLocalizedChange && pairChanges.contains { $0.startTime <= region.representativeTime && $0.endTime >= region.representativeTime },
            likelyPanelClose: moderateLocalizedChange && pairChanges.contains { $0.startTime >= region.representativeTime },
            likelyLargeTransition: hasVisibleChange && (changedAreaPercentage >= 0.45 || changeScore >= 0.70)
        )
    }

    private func downsample(_ image: CGImage, regionID: String, actualTime: Double) -> DownsampledFrame? {
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var luminance = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)
        for index in 0..<luminance.count {
            let pixelIndex = index * bytesPerPixel
            let red = Double(pixels[pixelIndex])
            let green = Double(pixels[pixelIndex + 1])
            let blue = Double(pixels[pixelIndex + 2])
            luminance[index] = UInt8(min(max((red * 0.299) + (green * 0.587) + (blue * 0.114), 0), 255))
        }

        return DownsampledFrame(
            regionID: regionID,
            actualTime: actualTime,
            width: sampleWidth,
            height: sampleHeight,
            luminance: luminance
        )
    }

    private func compare(before: DownsampledFrame, after: DownsampledFrame) -> FramePairChange? {
        guard before.width == after.width,
              before.height == after.height,
              before.luminance.count == after.luminance.count else {
            return nil
        }

        var changedPixelCount = 0
        var changedDifferenceTotal = 0.0
        var minX = before.width
        var minY = before.height
        var maxX = 0
        var maxY = 0

        for index in before.luminance.indices {
            let difference = abs(Double(before.luminance[index]) - Double(after.luminance[index])) / 255.0
            guard difference >= pixelDifferenceThreshold else { continue }

            let x = index % before.width
            let y = index / before.width
            changedPixelCount += 1
            changedDifferenceTotal += difference
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }

        guard changedPixelCount > 0 else {
            return FramePairChange(
                startTime: before.actualTime,
                endTime: after.actualTime,
                changeScore: 0,
                changedRegion: nil,
                changedAreaPercentage: 0
            )
        }

        let totalPixelCount = Double(before.luminance.count)
        let changedAreaPercentage = Double(changedPixelCount) / totalPixelCount
        let averageChangedDifference = changedDifferenceTotal / Double(changedPixelCount)
        let changeScore = min(max((changedAreaPercentage * 2.6) + (averageChangedDifference * 0.55), 0), 1)
        let changedRegion = CGRect(
            x: Double(minX) / Double(before.width),
            y: Double(minY) / Double(before.height),
            width: Double(maxX - minX + 1) / Double(before.width),
            height: Double(maxY - minY + 1) / Double(before.height)
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        return FramePairChange(
            startTime: before.actualTime,
            endTime: after.actualTime,
            changeScore: changeScore,
            changedRegion: changedRegion,
            changedAreaPercentage: changedAreaPercentage
        )
    }

    private func isChangeNearInteraction(
        changedRegion: CGRect?,
        region: ActivityRegion,
        contentCoordinateSize: CGSize
    ) -> Bool {
        guard let changedRegion, !changedRegion.isEmpty else { return false }
        let expandedChangedRegion = changedRegion.insetBy(dx: -0.12, dy: -0.12)
        let sourcePoints = normalizedSourcePoints(
            from: region.sourceEvents,
            contentCoordinateSize: contentCoordinateSize
        )

        if sourcePoints.contains(where: { expandedChangedRegion.contains($0) }) {
            return true
        }

        let changedCenter = CGPoint(x: changedRegion.midX, y: changedRegion.midY)
        if sourcePoints.contains(where: { normalizedDistance(from: $0, to: changedCenter) <= 0.22 }) {
            return true
        }

        if let normalizedArea = region.normalizedArea,
           expandedChangedRegion.intersects(normalizedArea) {
            return true
        }

        return false
    }

    private func normalizedSourcePoints(
        from sourceEvents: [SmartSetupSourceEventReference],
        contentCoordinateSize: CGSize
    ) -> [CGPoint] {
        let safeWidth = max(contentCoordinateSize.width, 1)
        let safeHeight = max(contentCoordinateSize.height, 1)
        return sourceEvents.map { event in
            CGPoint(
                x: min(max(event.x / safeWidth, 0), 1),
                y: min(max(event.y / safeHeight, 0), 1)
            )
        }
    }

    private func normalizedDistance(from lhs: CGPoint, to rhs: CGPoint) -> Double {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return sqrt((deltaX * deltaX) + (deltaY * deltaY))
    }

    private func adjacentPairs(from frames: [DownsampledFrame]) -> [(DownsampledFrame, DownsampledFrame)] {
        guard frames.count >= 2 else { return [] }
        return zip(frames.dropLast(), frames.dropFirst()).map { ($0, $1) }
    }

    private func previewLines(from metadata: Dictionary<String, SmartSuggestionVisualChangeMetadata>.Values) -> [String] {
        metadata
            .sorted { lhs, rhs in
                if lhs.representativeTime == rhs.representativeTime {
                    return lhs.regionID < rhs.regionID
                }
                return lhs.representativeTime < rhs.representativeTime
            }
            .prefix(maximumPreviewLines)
            .map { metadata in
                let time = Self.timeString(metadata.representativeTime)
                let score = String(format: "%.2f", metadata.changeScore)
                let area = Int((metadata.changedAreaPercentage * 100).rounded())
                return "Region: \(time) | Change: \(score) | Area: \(area)% | Near interaction: \(metadata.changeNearInteraction) | Large transition: \(metadata.likelyLargeTransition)"
            }
    }

    private static func timeString(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let wholeSeconds = Int(clampedSeconds)
        let tenths = Int((clampedSeconds - Double(wholeSeconds)) * 10.0)
        let minutes = wholeSeconds / 60
        let secondsRemainder = wholeSeconds % 60
        return String(format: "%02d:%02d.%01d", minutes, secondsRemainder, tenths)
    }
}
