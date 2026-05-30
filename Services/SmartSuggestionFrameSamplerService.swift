import AVFoundation
import CoreGraphics
import Foundation

struct ActivityRegion: Identifiable {
    enum Kind: String {
        case click
        case clickSequence
        case pause
        case repeatedArea
        case unknown
    }

    let id: String
    let kind: Kind
    let startTime: Double
    let endTime: Double
    let sourceEvents: [SmartSetupSourceEventReference]
    let representativeTime: Double
    let sourceSuggestionIDs: [String]
    let normalizedArea: CGRect?
}

struct ActivityRegionFrameSample {
    let regionID: String
    let requestedTime: Double
    let actualTime: Double
    let image: CGImage
}

struct ActivityRegionFrameSamplingDiagnostics {
    let regionCount: Int
    let sampledFrameCount: Int
    let failedSampleCount: Int
    let elapsedSeconds: Double
}

struct ActivityRegionFrameSamplingResult {
    let samples: [ActivityRegionFrameSample]
    let diagnostics: ActivityRegionFrameSamplingDiagnostics
}

struct ActivityRegionBuilder {
    private static let clickPaddingBefore = 0.35
    private static let clickPaddingAfter = 0.50
    private static let defaultPadding = 0.35
    private static let maximumFallbackClickRegions = 20

    static func activityRegions(
        from suggestions: [SmartSetupSuggestion],
        events: [RecordedEvent],
        duration: Double,
        contentCoordinateSize: CGSize
    ) -> [ActivityRegion] {
        let suggestionRegions = suggestions.map { suggestion in
            activityRegion(
                from: suggestion,
                duration: duration,
                contentCoordinateSize: contentCoordinateSize
            )
        }

        if !suggestionRegions.isEmpty {
            return suggestionRegions
        }

        return fallbackClickRegions(
            from: events,
            duration: duration,
            contentCoordinateSize: contentCoordinateSize
        )
    }

    private static func activityRegion(
        from suggestion: SmartSetupSuggestion,
        duration: Double,
        contentCoordinateSize: CGSize
    ) -> ActivityRegion {
        let sourceEvents = suggestion.sourceEvents.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        let kind = regionKind(for: suggestion, sourceEvents: sourceEvents)
        let bounds = timeBounds(for: suggestion, sourceEvents: sourceEvents, duration: duration)
        let representativeTime = representativeTime(
            for: suggestion,
            sourceEvents: sourceEvents,
            startTime: bounds.start,
            endTime: bounds.end,
            duration: duration
        )

        return ActivityRegion(
            id: "suggestion-\(suggestion.suggestionID)",
            kind: kind,
            startTime: bounds.start,
            endTime: bounds.end,
            sourceEvents: sourceEvents,
            representativeTime: representativeTime,
            sourceSuggestionIDs: [suggestion.suggestionID],
            normalizedArea: normalizedArea(
                from: sourceEvents,
                contentCoordinateSize: contentCoordinateSize
            )
        )
    }

    private static func fallbackClickRegions(
        from events: [RecordedEvent],
        duration: Double,
        contentCoordinateSize: CGSize
    ) -> [ActivityRegion] {
        let clickEvents = events
            .filter { $0.type == .leftMouseDown || $0.type == .rightMouseDown }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }
            .prefix(maximumFallbackClickRegions)

        return clickEvents.map { event in
            let sourceEvent = SmartSetupSourceEventReference(event: event)
            return ActivityRegion(
                id: "event-click-\(stableTimeKey(event.timestamp))-\(stablePointKey(event.x))-\(stablePointKey(event.y))",
                kind: .click,
                startTime: clamp(event.timestamp - clickPaddingBefore, duration: duration),
                endTime: clamp(event.timestamp + clickPaddingAfter, duration: duration),
                sourceEvents: [sourceEvent],
                representativeTime: clamp(event.timestamp, duration: duration),
                sourceSuggestionIDs: [],
                normalizedArea: normalizedArea(
                    from: [sourceEvent],
                    contentCoordinateSize: contentCoordinateSize
                )
            )
        }
    }

    private static func regionKind(
        for suggestion: SmartSetupSuggestion,
        sourceEvents: [SmartSetupSourceEventReference]
    ) -> ActivityRegion.Kind {
        let clickCount = sourceEvents.filter { $0.type == .leftMouseDown || $0.type == .rightMouseDown }.count
        if clickCount >= 2 {
            return .clickSequence
        }
        if clickCount == 1 {
            return .click
        }
        if suggestion.reasons.contains(.cursorPause) {
            return .pause
        }
        if suggestion.reasons.contains(.repeatedActivityZone) || suggestion.reasons.contains(.denseActivity) {
            return .repeatedArea
        }
        return .unknown
    }

    private static func timeBounds(
        for suggestion: SmartSetupSuggestion,
        sourceEvents: [SmartSetupSourceEventReference],
        duration: Double
    ) -> (start: Double, end: Double) {
        if let range = suggestion.sourceTimeRange {
            return (
                clamp(range.startTime, duration: duration),
                clamp(range.endTime, duration: duration)
            )
        }

        if let first = sourceEvents.first, let last = sourceEvents.last {
            return (
                clamp(first.timestamp - defaultPadding, duration: duration),
                clamp(last.timestamp + defaultPadding, duration: duration)
            )
        }

        let time = clamp(proposalTime(for: suggestion), duration: duration)
        return (
            clamp(time - defaultPadding, duration: duration),
            clamp(time + defaultPadding, duration: duration)
        )
    }

    private static func representativeTime(
        for suggestion: SmartSetupSuggestion,
        sourceEvents: [SmartSetupSourceEventReference],
        startTime: Double,
        endTime: Double,
        duration: Double
    ) -> Double {
        if let event = sourceEvents.first(where: { $0.type == .leftMouseDown || $0.type == .rightMouseDown }) {
            return clamp(event.timestamp, duration: duration)
        }
        if let first = sourceEvents.first {
            return clamp(first.timestamp, duration: duration)
        }
        return clamp((startTime + endTime) / 2, duration: duration)
    }

    private static func proposalTime(for suggestion: SmartSetupSuggestion) -> Double {
        switch suggestion.proposal {
        case .zoom(let proposal):
            return proposal.sourceEventTimestamp
        case .zoomAdjustment(let proposal):
            return proposal.startTime
        case .effect(let proposal):
            return proposal.sourceEventTimestamp
        case .regionTighten(let proposal):
            return proposal.sourceTime
        }
    }

    private static func normalizedArea(
        from sourceEvents: [SmartSetupSourceEventReference],
        contentCoordinateSize: CGSize
    ) -> CGRect? {
        let safeWidth = max(contentCoordinateSize.width, 1)
        let safeHeight = max(contentCoordinateSize.height, 1)
        guard !sourceEvents.isEmpty else { return nil }

        let normalizedPoints = sourceEvents.map { event in
            CGPoint(
                x: min(max(event.x / safeWidth, 0), 1),
                y: min(max(event.y / safeHeight, 0), 1)
            )
        }
        guard let firstPoint = normalizedPoints.first else { return nil }

        let bounds = normalizedPoints.reduce(
            CGRect(origin: firstPoint, size: .zero)
        ) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        return bounds.insetBy(dx: -0.04, dy: -0.04).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func clamp(_ time: Double, duration: Double) -> Double {
        min(max(time, 0), max(duration, 0))
    }

    private static func stableTimeKey(_ time: Double) -> Int {
        Int((time * 100).rounded())
    }

    private static func stablePointKey(_ point: Double) -> Int {
        Int(point.rounded())
    }
}

private final class ImageGenerationState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: (image: CGImage, actualTime: Double)?

    var value: (image: CGImage, actualTime: Double)? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(image: CGImage, actualTime: Double) {
        lock.lock()
        storedValue = (image, actualTime)
        lock.unlock()
    }
}

final class SmartSuggestionFrameSamplerService {
    private let maximumRegions = 20
    private let maximumFramesPerRegion = 5
    private let maximumFrameSize = CGSize(width: 1600, height: 1600)
    private var sampleCache: [String: ActivityRegionFrameSample] = [:]

    func sampleFrames(
        recordingURL: URL,
        duration: Double,
        regions: [ActivityRegion]
    ) async -> ActivityRegionFrameSamplingResult {
        let startDate = Date()
        guard !regions.isEmpty else {
            return ActivityRegionFrameSamplingResult(
                samples: [],
                diagnostics: ActivityRegionFrameSamplingDiagnostics(
                    regionCount: 0,
                    sampledFrameCount: 0,
                    failedSampleCount: 0,
                    elapsedSeconds: 0
                )
            )
        }

        let asset = AVURLAsset(url: recordingURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = maximumFrameSize
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        var samples: [ActivityRegionFrameSample] = []
        var failedSampleCount = 0
        let sampledRegions = Array(regions.prefix(maximumRegions))

        for region in sampledRegions {
            guard !Task.isCancelled else { break }
            for requestedTime in sampleTimes(for: region, duration: duration).prefix(maximumFramesPerRegion) {
                guard !Task.isCancelled else { break }
                let cacheKey = cacheKey(recordingURL: recordingURL, regionID: region.id, requestedTime: requestedTime)
                if let cachedSample = sampleCache[cacheKey] {
                    samples.append(cachedSample)
                    continue
                }

                if let generatedFrame = await generateImage(
                    at: requestedTime,
                    imageGenerator: imageGenerator
                ) {
                    let sample = ActivityRegionFrameSample(
                        regionID: region.id,
                        requestedTime: requestedTime,
                        actualTime: generatedFrame.actualTime,
                        image: generatedFrame.image
                    )
                    sampleCache[cacheKey] = sample
                    samples.append(sample)
                } else {
                    failedSampleCount += 1
                }
            }
        }

        return ActivityRegionFrameSamplingResult(
            samples: samples,
            diagnostics: ActivityRegionFrameSamplingDiagnostics(
                regionCount: regions.count,
                sampledFrameCount: samples.count,
                failedSampleCount: failedSampleCount,
                elapsedSeconds: Date().timeIntervalSince(startDate)
            )
        )
    }

    private func generateImage(
        at requestedTime: Double,
        imageGenerator: AVAssetImageGenerator
    ) async -> (image: CGImage, actualTime: Double)? {
        await withCheckedContinuation { continuation in
            imageGenerator.generateCGImageAsynchronously(
                for: CMTime(seconds: requestedTime, preferredTimescale: 600)
            ) { image, actualTime, error in
                guard let image, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: (
                        image: image,
                        actualTime: actualTime.seconds.isFinite ? actualTime.seconds : requestedTime
                    )
                )
            }
        }
    }

    private func sampleTimes(for region: ActivityRegion, duration: Double) -> [Double] {
        let midpoint = (region.startTime + region.endTime) / 2
        let rawTimes: [Double]
        switch region.kind {
        case .click:
            rawTimes = [region.representativeTime - 0.35, region.representativeTime, region.representativeTime + 0.50]
        case .clickSequence:
            rawTimes = [region.startTime, midpoint, region.endTime, region.endTime + 0.50]
        case .pause:
            rawTimes = [region.startTime, midpoint, region.endTime]
        case .repeatedArea, .unknown:
            rawTimes = [region.startTime, region.representativeTime, region.endTime]
        }

        return uniqueTimes(rawTimes.map { clamp($0, duration: duration) })
    }

    private func uniqueTimes(_ times: [Double]) -> [Double] {
        var seenKeys = Set<Int>()
        var unique: [Double] = []
        for time in times {
            let key = Int((time * 100).rounded())
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            unique.append(time)
        }
        return unique
    }

    private func clamp(_ time: Double, duration: Double) -> Double {
        min(max(time, 0), max(duration, 0))
    }

    private func cacheKey(recordingURL: URL, regionID: String, requestedTime: Double) -> String {
        "\(recordingURL.path)-\(regionID)-\(Int((requestedTime * 100).rounded()))"
    }
}
