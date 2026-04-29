//
//  Models.swift
//  Zoom and Track
//

import CoreGraphics
import Foundation

enum CaptureTargetKind: String, Codable {
    case display
    case window
}

struct ShareableCaptureTarget: Identifiable, Equatable {
    let id: String
    let kind: CaptureTargetKind
    let sourceID: UInt32
    let title: String
    let ownerName: String?
    let ownerBundleIdentifier: String?
    let ownerProcessID: Int32?
    let subtitle: String?
    let width: Int
    let height: Int
    let originX: Double
    let originY: Double
    let pointsWidth: Double
    let pointsHeight: Double
    let scaleFactor: Double

    var displayTitle: String {
        if let ownerName, !ownerName.isEmpty {
            return "\(title) (\(ownerName))"
        }
        if let subtitle, !subtitle.isEmpty {
            return "\(title) (\(subtitle))"
        }
        return title
    }
}

enum RecordingSessionState: Equatable {
    case idle
    case loadingTargets
    case preparing
    case recording
    case stopping
    case finished(URL)
    case failed(String)
}

struct CaptureSource: Codable {
    let kind: CaptureTargetKind
    let sourceID: UInt32
    let title: String
    let subtitle: String?
    let width: Int
    let height: Int
    let originX: Double?
    let originY: Double?
    let pointsWidth: Double?
    let pointsHeight: Double?
    let scaleFactor: Double?
}

struct ProjectManifest: Codable {
    let captureID: UUID
    let name: String
    let collectionName: String
    let projectName: String
    let captureType: CaptureType
    let captureTitle: String
    let createdAt: Date
    let updatedAt: Date
    let captureSource: CaptureSource
    let recordingFileName: String
    let eventFileName: String

    private enum CodingKeys: String, CodingKey {
        case captureID
        case id
        case name
        case collectionName
        case projectName
        case captureType
        case captureTitle
        case createdAt
        case updatedAt
        case captureSource
        case recordingFileName
        case eventFileName
    }

    init(
        captureID: UUID,
        name: String,
        collectionName: String,
        projectName: String,
        captureType: CaptureType,
        captureTitle: String,
        createdAt: Date,
        updatedAt: Date,
        captureSource: CaptureSource,
        recordingFileName: String,
        eventFileName: String
    ) {
        self.captureID = captureID
        self.name = name
        self.collectionName = collectionName
        self.projectName = projectName
        self.captureType = captureType
        self.captureTitle = captureTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.captureSource = captureSource
        self.recordingFileName = recordingFileName
        self.eventFileName = eventFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureID = try container.decodeIfPresent(UUID.self, forKey: .captureID)
            ?? container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        collectionName = try container.decodeIfPresent(String.self, forKey: .collectionName) ?? "Default Collection"
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? "General Project"
        captureType = try container.decodeIfPresent(CaptureType.self, forKey: .captureType) ?? .other
        captureTitle = try container.decodeIfPresent(String.self, forKey: .captureTitle) ?? name
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        captureSource = try container.decode(CaptureSource.self, forKey: .captureSource)
        recordingFileName = try container.decode(String.self, forKey: .recordingFileName)
        eventFileName = try container.decode(String.self, forKey: .eventFileName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captureID, forKey: .captureID)
        try container.encode(name, forKey: .name)
        try container.encode(collectionName, forKey: .collectionName)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(captureType, forKey: .captureType)
        try container.encode(captureTitle, forKey: .captureTitle)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(captureSource, forKey: .captureSource)
        try container.encode(recordingFileName, forKey: .recordingFileName)
        try container.encode(eventFileName, forKey: .eventFileName)
    }
}

struct CaptureMetadata: Equatable {
    var collectionName: String
    var projectName: String
    var captureType: CaptureType
    var captureTitle: String

    var resolvedCollectionName: String {
        let trimmed = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Default Collection" : trimmed
    }

    var resolvedProjectName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "General Project" : trimmed
    }

    var resolvedCaptureTitle: String {
        let trimmed = captureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Capture" : trimmed
    }
}

enum CaptureType: String, Codable, CaseIterable, Identifiable {
    case demo
    case tutorial
    case support
    case marketing
    case training
    case bugReport
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .demo:
            return "Demo"
        case .tutorial:
            return "Tutorial"
        case .support:
            return "Support"
        case .marketing:
            return "Marketing"
        case .training:
            return "Training"
        case .bugReport:
            return "Bug Report"
        case .other:
            return "Other"
        }
    }
}

struct CaptureLibraryItem: Codable, Identifiable, Equatable {
    let captureID: UUID
    let title: String
    let captureType: CaptureType
    let collectionName: String
    let projectName: String
    let createdAt: Date
    let updatedAt: Date
    let duration: Double?
    let bundleRelativePath: String
    let status: CaptureLibraryItemStatus
    let statusMessage: String?

    init(
        captureID: UUID,
        title: String,
        captureType: CaptureType,
        collectionName: String,
        projectName: String,
        createdAt: Date,
        updatedAt: Date,
        duration: Double?,
        bundleRelativePath: String,
        status: CaptureLibraryItemStatus = .available,
        statusMessage: String? = nil
    ) {
        self.captureID = captureID
        self.title = title
        self.captureType = captureType
        self.collectionName = collectionName
        self.projectName = projectName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.bundleRelativePath = bundleRelativePath
        self.status = status
        self.statusMessage = statusMessage
    }

    var id: UUID { captureID }

    var isAvailable: Bool {
        status == .available
    }

    var canOpenInEditor: Bool {
        switch status {
        case .available, .missingEvents, .missingZoomPlan:
            return true
        case .missingBundle, .missingManifest, .missingRecording:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case captureID
        case title
        case captureType
        case collectionName
        case projectName
        case createdAt
        case updatedAt
        case duration
        case bundleRelativePath
        case status
        case statusMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureID = try container.decode(UUID.self, forKey: .captureID)
        title = try container.decode(String.self, forKey: .title)
        captureType = try container.decode(CaptureType.self, forKey: .captureType)
        collectionName = try container.decode(String.self, forKey: .collectionName)
        projectName = try container.decode(String.self, forKey: .projectName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        bundleRelativePath = try container.decode(String.self, forKey: .bundleRelativePath)
        status = try container.decodeIfPresent(CaptureLibraryItemStatus.self, forKey: .status) ?? .available
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
    }
}

enum CaptureLibraryItemStatus: String, Codable {
    case available
    case missingBundle
    case missingManifest
    case missingRecording
    case missingEvents
    case missingZoomPlan

    var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .missingBundle:
            return "Missing Bundle"
        case .missingManifest:
            return "Missing Manifest"
        case .missingRecording:
            return "Missing Recording"
        case .missingEvents:
            return "Missing Events"
        case .missingZoomPlan:
            return "Missing Zoom Plan"
        }
    }
}

struct CaptureLibraryIndex: Codable {
    let updatedAt: Date
    let items: [CaptureLibraryItem]
}

struct CaptureLibrarySnapshot {
    let items: [CaptureLibraryItem]
    let statusMessage: String?
}

struct RecordingWorkspace {
    let temporaryDirectory: URL
    let temporaryRecordingURL: URL
    let finalProjectURL: URL
    let requiresSecurityScopedAccess: Bool
    let securityScopedOutputDirectoryURL: URL?
}

enum RecordedEventType: String, Codable {
    case cursorMoved
    case leftMouseDown
    case leftMouseUp
    case rightMouseDown
    case rightMouseUp
}

struct RecordedEvent: Codable {
    let type: RecordedEventType
    let timestamp: Double
    let x: Double
    let y: Double
}

struct RecordedEventEnvelope: Codable {
    let schemaVersion: Int
    let timebase: String
    let events: [RecordedEvent]
}

struct ZoomPlanEnvelope: Codable {
    let schemaVersion: Int
    let source: String
    let items: [ZoomPlanItem]
}

enum ZoomEaseStyle: String, Codable, CaseIterable, Identifiable {
    case smooth
    case fastIn
    case fastOut
    case linear
    case bounce

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smooth:
            return "Smooth"
        case .fastIn:
            return "Fast In"
        case .fastOut:
            return "Fast Out"
        case .linear:
            return "Linear"
        case .bounce:
            return "Bounce"
        }
    }
}

enum ZoomType: String, Codable, CaseIterable, Identifiable {
    case inOut
    case inOnly
    case outOnly
    case noZoom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inOut:
            return "Zoom In & Out"
        case .inOnly:
            return "Zoom In Only"
        case .outOnly:
            return "Zoom Out Only"
        case .noZoom:
            return "No Zoom"
        }
    }
}

enum NoZoomFallbackMode: String, Codable, CaseIterable, Identifiable {
    case pan
    case scale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pan:
            return "Pan"
        case .scale:
            return "Scale"
        }
    }
}

enum ZoomMarkerKind: String, Codable {
    case clickFocus
}

enum ClickPulsePreset: String, Codable, CaseIterable, Identifiable {
    case subtleRing
    case doubleRing
    case softGlow
    case radarPing
    case expandingDot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subtleRing:
            return "Subtle Ring"
        case .doubleRing:
            return "Double Ring"
        case .softGlow:
            return "Soft Glow"
        case .radarPing:
            return "Radar Ping"
        case .expandingDot:
            return "Expanding Dot"
        }
    }
}

struct ClickPulseConfiguration: Codable, Equatable {
    var preset: ClickPulsePreset

    static let defaultConfiguration = ClickPulseConfiguration(preset: .subtleRing)

    var duration: Double {
        switch preset {
        case .subtleRing:
            return 0.55
        case .doubleRing:
            return 0.7
        case .softGlow:
            return 0.5
        case .radarPing:
            return 0.85
        case .expandingDot:
            return 0.45
        }
    }
}

struct ZoomPlanItem: Codable, Identifiable {
    var id: String
    var type: String
    var markerName: String?
    var markerKind: ZoomMarkerKind
    var sourceEventTimestamp: Double
    var rawX: Double?
    var rawY: Double?
    var centerX: Double
    var centerY: Double
    var zoomScale: Double
    var startTime: Double
    var holdUntil: Double
    var endTime: Double
    var leadInTime: Double
    var zoomInDuration: Double
    var holdDuration: Double
    var zoomOutDuration: Double
    var enabled: Bool
    var duration: Double
    var easeStyle: ZoomEaseStyle
    var zoomType: ZoomType
    var bounceAmount: Double
    var clickPulse: ClickPulseConfiguration?
    var noZoomFallbackMode: NoZoomFallbackMode
    var displayOrder: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case markerName
        case markerKind
        case sourceEventTimestamp
        case rawX
        case rawY
        case centerX
        case centerY
        case zoomScale
        case startTime
        case holdUntil
        case endTime
        case leadInTime
        case zoomInDuration
        case holdDuration
        case zoomOutDuration
        case enabled
        case duration
        case easeStyle
        case zoomType
        case bounceAmount
        case clickPulse
        case noZoomFallbackMode
        case displayOrder
    }

    init(
        id: String,
        type: String,
        markerName: String? = nil,
        markerKind: ZoomMarkerKind = .clickFocus,
        sourceEventTimestamp: Double,
        rawX: Double?,
        rawY: Double?,
        centerX: Double,
        centerY: Double,
        zoomScale: Double,
        startTime: Double,
        holdUntil: Double,
        endTime: Double,
        leadInTime: Double,
        zoomInDuration: Double,
        holdDuration: Double,
        zoomOutDuration: Double,
        enabled: Bool,
        duration: Double,
        easeStyle: ZoomEaseStyle,
        zoomType: ZoomType,
        bounceAmount: Double,
        clickPulse: ClickPulseConfiguration? = nil,
        noZoomFallbackMode: NoZoomFallbackMode = .pan,
        displayOrder: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.markerName = markerName
        self.markerKind = markerKind
        self.sourceEventTimestamp = sourceEventTimestamp
        self.rawX = rawX
        self.rawY = rawY
        self.centerX = centerX
        self.centerY = centerY
        self.zoomScale = zoomScale
        self.startTime = startTime
        self.holdUntil = holdUntil
        self.endTime = endTime
        self.leadInTime = leadInTime
        self.zoomInDuration = zoomInDuration
        self.holdDuration = holdDuration
        self.zoomOutDuration = zoomOutDuration
        self.enabled = enabled
        self.duration = duration
        self.easeStyle = easeStyle
        self.zoomType = zoomType
        self.bounceAmount = bounceAmount
        self.clickPulse = clickPulse
        self.noZoomFallbackMode = noZoomFallbackMode
        self.displayOrder = displayOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        markerName = try container.decodeIfPresent(String.self, forKey: .markerName)
        markerKind = try container.decodeIfPresent(ZoomMarkerKind.self, forKey: .markerKind) ?? .clickFocus
        sourceEventTimestamp = try container.decode(Double.self, forKey: .sourceEventTimestamp)
        rawX = try container.decodeIfPresent(Double.self, forKey: .rawX)
        rawY = try container.decodeIfPresent(Double.self, forKey: .rawY)
        centerX = try container.decode(Double.self, forKey: .centerX)
        centerY = try container.decode(Double.self, forKey: .centerY)
        zoomScale = try container.decodeIfPresent(Double.self, forKey: .zoomScale) ?? 1.8
        startTime = try container.decode(Double.self, forKey: .startTime)
        holdUntil = try container.decode(Double.self, forKey: .holdUntil)
        endTime = try container.decode(Double.self, forKey: .endTime)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        easeStyle = try container.decodeIfPresent(ZoomEaseStyle.self, forKey: .easeStyle) ?? .smooth
        zoomType = try container.decodeIfPresent(ZoomType.self, forKey: .zoomType) ?? .inOut
        bounceAmount = try container.decodeIfPresent(Double.self, forKey: .bounceAmount) ?? 0.35
        clickPulse = try container.decodeIfPresent(ClickPulseConfiguration.self, forKey: .clickPulse)
        noZoomFallbackMode = try container.decodeIfPresent(NoZoomFallbackMode.self, forKey: .noZoomFallbackMode) ?? .pan
        displayOrder = try container.decodeIfPresent(Int.self, forKey: .displayOrder)

        let legacyDuration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? max(endTime - startTime, 0.5)
        let legacyPhases = ZoomPlanItem.legacyPhaseTiming(totalDuration: legacyDuration)

        leadInTime = try container.decodeIfPresent(Double.self, forKey: .leadInTime) ?? legacyPhases.leadInTime
        zoomInDuration = try container.decodeIfPresent(Double.self, forKey: .zoomInDuration) ?? legacyPhases.zoomInDuration
        holdDuration = try container.decodeIfPresent(Double.self, forKey: .holdDuration) ?? legacyPhases.holdDuration
        zoomOutDuration = try container.decodeIfPresent(Double.self, forKey: .zoomOutDuration) ?? legacyPhases.zoomOutDuration
        switch zoomType {
        case .inOut:
            duration = max(leadInTime + zoomInDuration + holdDuration + zoomOutDuration, 0.5)
        case .inOnly:
            duration = max(leadInTime + zoomInDuration + holdDuration, 0.5)
        case .outOnly:
            duration = max(zoomOutDuration, 0.25)
        case .noZoom:
            duration = max(leadInTime + zoomInDuration + holdDuration, 0.5)
        }
    }

    var totalSegmentDuration: Double {
        switch zoomType {
        case .inOut:
            return max(leadInTime + zoomInDuration + holdDuration + zoomOutDuration, 0.5)
        case .inOnly:
            return max(leadInTime + zoomInDuration + holdDuration, 0.5)
        case .outOnly:
            return max(zoomOutDuration, 0.25)
        case .noZoom:
            return max(leadInTime + zoomInDuration + holdDuration, 0.5)
        }
    }

    var isClickFocus: Bool {
        markerKind == .clickFocus
    }

    var isClickPulseEnabled: Bool {
        clickPulse != nil
    }

    static func legacyPhaseTiming(totalDuration: Double) -> (leadInTime: Double, zoomInDuration: Double, holdDuration: Double, zoomOutDuration: Double) {
        let safeTotal = max(totalDuration, 0.25)
        let baseLeadIn = 0.15
        let baseZoomIn = min(0.30, safeTotal * 0.18)
        let baseZoomOut = min(0.40, safeTotal * 0.22)
        let minimumHold = 0.25

        if safeTotal >= baseLeadIn + baseZoomIn + baseZoomOut + minimumHold {
            return (
                leadInTime: baseLeadIn,
                zoomInDuration: baseZoomIn,
                holdDuration: safeTotal - baseLeadIn - baseZoomIn - baseZoomOut,
                zoomOutDuration: baseZoomOut
            )
        }

        let availableAfterLead = max(safeTotal - baseLeadIn, 0.1)
        let weightTotal = 0.18 + 0.22 + 0.60
        let scale = availableAfterLead / weightTotal
        let scaledZoomIn = max(0.08, 0.18 * scale)
        let scaledZoomOut = max(0.08, 0.22 * scale)
        let scaledHold = max(availableAfterLead - scaledZoomIn - scaledZoomOut, 0.09)

        return (
            leadInTime: min(baseLeadIn, safeTotal * 0.25),
            zoomInDuration: scaledZoomIn,
            holdDuration: scaledHold,
            zoomOutDuration: scaledZoomOut
        )
    }
}

struct RecordingInspectionSummary {
    let bundleURL: URL
    let bundleName: String
    let captureID: UUID
    let collectionName: String
    let projectName: String
    let captureType: CaptureType
    let captureTitle: String
    let createdAt: Date
    let updatedAt: Date
    let recordingURL: URL
    let videoAspectRatio: CGFloat
    let contentCoordinateSize: CGSize
    let captureSourceKind: CaptureTargetKind
    let captureSourceTitle: String
    let totalEventCount: Int
    let cursorMovedCount: Int
    let leftMouseDownCount: Int
    let leftMouseUpCount: Int
    let rightMouseDownCount: Int
    let rightMouseUpCount: Int
    let firstEventTimestamp: Double?
    let lastEventTimestamp: Double?
    let duration: Double?
    let zoomMarkers: [ZoomPlanItem]

    var displayTitle: String {
        captureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? bundleName : captureTitle
    }

    var displaySubtitle: String {
        "\(collectionName) • \(projectName) • \(captureType.displayName)"
    }
}

enum SharedMotionEngine {
    enum CoordinateSpace {
        case topLeft
        case bottomLeft
    }

    struct PreviewState {
        let scale: CGFloat
        let normalizedPoint: CGPoint
    }

    struct ClickPulseRenderState {
        let preset: ClickPulsePreset
        let progress: Double
    }

    struct OverlayGeometryResolution {
        let point: CGPoint
        let isVisible: Bool
        let clipped: Bool
    }

    struct Timeline {
        let startTime: Double
        let peakTime: Double
        let holdUntil: Double
        let endTime: Double
    }

    private enum MotionDirection {
        case entering
        case exiting
    }

    private struct MotionProgressSample {
        let scale: Double
        let pan: Double
    }

    private enum MotionTuning {
        static let bounceMinBlend = 0.3
        static let bounceMaxDamping = 6.5
        static let bounceMinDamping = 3.5
        static let bounceMinFrequency = 9.0
        static let bounceMaxFrequency = 16.0
        static let panBounceInfluence = 0.35
    }

    static func previewBounds(for marker: ZoomPlanItem) -> (startTime: Double, endTime: Double) {
        let startTime = max(0, marker.startTime)
        let pulseEndTime = marker.sourceEventTimestamp + (marker.clickPulse?.duration ?? 0)
        switch marker.zoomType {
        case .inOut, .outOnly:
            return (startTime, max(marker.endTime, pulseEndTime))
        case .inOnly, .noZoom:
            return (startTime, max(marker.holdUntil, pulseEndTime))
        }
    }

    static func zoomTimeline(for marker: ZoomPlanItem) -> Timeline {
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
            return Timeline(startTime: safeStart, peakTime: peakTime, holdUntil: safeHoldUntil, endTime: safeEndTime)
        case .inOnly:
            let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
            let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
            return Timeline(startTime: safeStart, peakTime: peakTime, holdUntil: safeHoldUntil, endTime: safeHoldUntil)
        case .outOnly:
            let safeStart = marker.startTime.isFinite ? max(marker.startTime, peakTime) : peakTime
            let safeEndTime = marker.endTime.isFinite ? max(marker.endTime, safeStart) : peakTime + safeZoomOut
            return Timeline(startTime: safeStart, peakTime: peakTime, holdUntil: safeStart, endTime: safeEndTime)
        case .noZoom:
            let safeStart = marker.startTime.isFinite ? max(0, min(marker.startTime, peakTime)) : fallbackStart
            let safeHoldUntil = marker.holdUntil.isFinite ? max(marker.holdUntil, peakTime) : fallbackHoldUntil
            return Timeline(startTime: safeStart, peakTime: peakTime, holdUntil: safeHoldUntil, endTime: safeHoldUntil)
        }
    }

    static func activeZoomState(
        at currentTime: Double,
        zoomMarkers: [ZoomPlanItem],
        contentCoordinateSize: CGSize,
        coordinateSpace: CoordinateSpace
    ) -> PreviewState? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let enabledMarkers = zoomMarkers
            .filter(\.enabled)
            .sorted { $0.sourceEventTimestamp < $1.sourceEventTimestamp }
        guard !enabledMarkers.isEmpty else {
            return nil
        }

        var currentState = PreviewState(scale: 1, normalizedPoint: CGPoint(x: 0.5, y: 0.5))
        var restingState = currentState

        for marker in enabledMarkers {
            let timeline = zoomTimeline(for: marker)
            if currentTime < timeline.startTime {
                break
            }

            let normalizedPoint = normalizedPoint(
                for: marker,
                contentCoordinateSize: contentCoordinateSize,
                coordinateSpace: coordinateSpace
            )
            let stateEvent = PreviewState(
                scale: max(CGFloat(marker.zoomScale), 1),
                normalizedPoint: normalizedPoint
            )

            switch marker.zoomType {
            case .inOut:
                if currentTime <= timeline.endTime {
                    return inOutPreviewState(at: currentTime, stateEvent: stateEvent, timeline: timeline, marker: marker)
                }
                currentState = PreviewState(scale: 1, normalizedPoint: normalizedPoint)
                restingState = currentState
            case .inOnly:
                if currentTime <= timeline.peakTime {
                    return inOnlyPreviewState(at: currentTime, stateEvent: stateEvent, timeline: timeline, marker: marker)
                }
                currentState = PreviewState(scale: stateEvent.scale, normalizedPoint: normalizedPoint)
                restingState = currentState
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
                currentState = PreviewState(scale: 1, normalizedPoint: normalizedPoint)
                restingState = currentState
            case .noZoom:
                let targetState = noZoomTargetState(
                    currentState: currentState,
                    restingState: restingState,
                    targetPoint: normalizedPoint,
                    fallbackMode: marker.noZoomFallbackMode
                )
                if currentTime <= timeline.peakTime {
                    return noZoomPreviewState(
                        at: currentTime,
                        currentState: currentState,
                        targetState: targetState,
                        timeline: timeline,
                        marker: marker
                    )
                }
                if currentTime <= timeline.holdUntil {
                    return targetState
                }
                currentState = targetState
            }
        }

        return currentState.scale > 1.0001 ? currentState : nil
    }

    static func previewOffset(for previewState: PreviewState, outputSize: CGSize) -> CGSize {
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

    static func resolveOverlayPoint(
        contentPoint: CGPoint,
        contentCoordinateSize: CGSize,
        orientedVideoSize: CGSize,
        outputSize: CGSize,
        previewState: PreviewState?,
    ) -> OverlayGeometryResolution {
        guard contentCoordinateSize.width > 0,
              contentCoordinateSize.height > 0,
              orientedVideoSize.width > 0,
              orientedVideoSize.height > 0,
              outputSize.width > 0,
              outputSize.height > 0 else {
            return OverlayGeometryResolution(point: .zero, isVisible: false, clipped: true)
        }

        let normalizedX = contentPoint.x / contentCoordinateSize.width
        let normalizedY = contentPoint.y / contentCoordinateSize.height
        let scale = outputSize.width / orientedVideoSize.width
        let baseVisibleRect = CGRect(
            origin: .zero,
            size: CGSize(width: orientedVideoSize.width * scale, height: orientedVideoSize.height * scale)
        )

        let basePoint = CGPoint(
            x: baseVisibleRect.minX + (normalizedX * baseVisibleRect.width),
            y: baseVisibleRect.minY + (normalizedY * baseVisibleRect.height)
        )
        var point = basePoint

        if let previewState {
            let offset = previewOffset(for: previewState, outputSize: outputSize)
            let basePointBottomLeft = CGPoint(
                x: basePoint.x,
                y: outputSize.height - basePoint.y
            )
            let transformedBottomLeft = CGPoint(
                x: basePointBottomLeft.x * previewState.scale + offset.width,
                y: basePointBottomLeft.y * previewState.scale + offset.height
            )
            point = CGPoint(
                x: transformedBottomLeft.x,
                y: outputSize.height - transformedBottomLeft.y
            )
        }

        let outputRect = CGRect(origin: .zero, size: outputSize)
        let isVisible = outputRect.contains(point)
        let clipped = !isVisible || normalizedX < 0 || normalizedX > 1 || normalizedY < 0 || normalizedY > 1 || !baseVisibleRect.contains(basePoint)
        return OverlayGeometryResolution(
            point: point,
            isVisible: isVisible,
            clipped: clipped
        )
    }

    static func clickPulseRenderState(
        at currentTime: Double,
        marker: ZoomPlanItem
    ) -> ClickPulseRenderState? {
        guard marker.enabled, let clickPulse = marker.clickPulse, marker.isClickFocus else { return nil }
        let pulseProgress = normalizedProgress(
            currentTime,
            start: marker.sourceEventTimestamp,
            end: marker.sourceEventTimestamp + clickPulse.duration
        )
        guard pulseProgress > 0, pulseProgress < 1 else { return nil }
        return ClickPulseRenderState(
            preset: clickPulse.preset,
            progress: pulseProgress
        )
    }

    private static func normalizedPoint(
        for marker: ZoomPlanItem,
        contentCoordinateSize: CGSize,
        coordinateSpace: CoordinateSpace
    ) -> CGPoint {
        let normalizedX = min(max(marker.centerX / contentCoordinateSize.width, 0), 1)
        let baseY = min(max(marker.centerY / contentCoordinateSize.height, 0), 1)
        let normalizedY = coordinateSpace == .bottomLeft ? (1 - baseY) : baseY
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private static func inOutPreviewState(
        at currentTime: Double,
        stateEvent: PreviewState,
        timeline: Timeline,
        marker: ZoomPlanItem
    ) -> PreviewState {
        if currentTime <= timeline.peakTime {
            let progress = motionProgress(
                currentTime: currentTime,
                startTime: timeline.startTime,
                endTime: timeline.peakTime,
                easeStyle: marker.easeStyle,
                direction: .entering,
                bounceAmount: marker.bounceAmount
            )
            return PreviewState(
                scale: interpolate(from: 1, to: stateEvent.scale, progress: progress.scale),
                normalizedPoint: CGPoint(
                    x: interpolate(from: 0.5, to: stateEvent.normalizedPoint.x, progress: progress.pan),
                    y: interpolate(from: 0.5, to: stateEvent.normalizedPoint.y, progress: progress.pan)
                )
            )
        }

        if currentTime <= timeline.holdUntil {
            return stateEvent
        }

        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.holdUntil,
            endTime: timeline.endTime,
            easeStyle: marker.easeStyle,
            direction: .exiting,
            bounceAmount: marker.bounceAmount
        )
        return PreviewState(
            scale: max(interpolate(from: stateEvent.scale, to: 1, progress: progress.scale), 1),
            normalizedPoint: CGPoint(
                x: interpolate(from: stateEvent.normalizedPoint.x, to: 0.5, progress: progress.pan),
                y: interpolate(from: stateEvent.normalizedPoint.y, to: 0.5, progress: progress.pan)
            )
        )
    }

    private static func inOnlyPreviewState(
        at currentTime: Double,
        stateEvent: PreviewState,
        timeline: Timeline,
        marker: ZoomPlanItem
    ) -> PreviewState {
        if currentTime <= timeline.peakTime {
            let progress = motionProgress(
                currentTime: currentTime,
                startTime: timeline.startTime,
                endTime: timeline.peakTime,
                easeStyle: marker.easeStyle,
                direction: .entering,
                bounceAmount: marker.bounceAmount
            )
            return PreviewState(
                scale: interpolate(from: 1, to: stateEvent.scale, progress: progress.scale),
                normalizedPoint: CGPoint(
                    x: interpolate(from: 0.5, to: stateEvent.normalizedPoint.x, progress: progress.pan),
                    y: interpolate(from: 0.5, to: stateEvent.normalizedPoint.y, progress: progress.pan)
                )
            )
        }

        return stateEvent
    }

    private static func outOnlyPreviewState(
        at currentTime: Double,
        currentState: PreviewState,
        targetPoint: CGPoint,
        timeline: Timeline,
        easeStyle: ZoomEaseStyle,
        bounceAmount: Double
    ) -> PreviewState {
        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.startTime,
            endTime: timeline.endTime,
            easeStyle: easeStyle,
            direction: .exiting,
            bounceAmount: bounceAmount
        )
        return PreviewState(
            scale: max(interpolate(from: currentState.scale, to: 1, progress: progress.scale), 1),
            normalizedPoint: CGPoint(
                x: interpolate(from: currentState.normalizedPoint.x, to: targetPoint.x, progress: progress.pan),
                y: interpolate(from: currentState.normalizedPoint.y, to: targetPoint.y, progress: progress.pan)
            )
        )
    }

    private static func noZoomPreviewState(
        at currentTime: Double,
        currentState: PreviewState,
        targetState: PreviewState,
        timeline: Timeline,
        marker: ZoomPlanItem
    ) -> PreviewState {
        let progress = motionProgress(
            currentTime: currentTime,
            startTime: timeline.startTime,
            endTime: timeline.peakTime,
            easeStyle: marker.easeStyle,
            direction: .entering,
            bounceAmount: marker.bounceAmount
        )
        return PreviewState(
            scale: max(interpolate(from: currentState.scale, to: targetState.scale, progress: progress.scale), 1),
            normalizedPoint: CGPoint(
                x: interpolate(from: currentState.normalizedPoint.x, to: targetState.normalizedPoint.x, progress: progress.pan),
                y: interpolate(from: currentState.normalizedPoint.y, to: targetState.normalizedPoint.y, progress: progress.pan)
            )
        )
    }

    private static func noZoomTargetState(
        currentState: PreviewState,
        restingState: PreviewState,
        targetPoint: CGPoint,
        fallbackMode: NoZoomFallbackMode
    ) -> PreviewState {
        guard restingState.scale > 1.0001 else {
            return currentState
        }

        if visibleRect(for: restingState).contains(targetPoint) {
            return restingState
        }

        switch fallbackMode {
        case .pan:
            return PreviewState(
                scale: restingState.scale,
                normalizedPoint: centeredPanTarget(from: restingState, toward: targetPoint)
            )
        case .scale:
            let fittedScale = maximumVisibleScale(for: targetPoint, anchoredTo: restingState)
            return PreviewState(scale: fittedScale, normalizedPoint: restingState.normalizedPoint)
        }
    }

    private static func visibleRect(for state: PreviewState) -> CGRect {
        let viewportWidth = 1 / max(state.scale, 1)
        let viewportHeight = 1 / max(state.scale, 1)
        let minX = min(max(state.normalizedPoint.x - (viewportWidth / 2), 0), 1 - viewportWidth)
        let minY = min(max(state.normalizedPoint.y - (viewportHeight / 2), 0), 1 - viewportHeight)
        return CGRect(x: minX, y: minY, width: viewportWidth, height: viewportHeight)
    }

    private static func centeredPanTarget(from state: PreviewState, toward targetPoint: CGPoint) -> CGPoint {
        let rect = visibleRect(for: state)
        let viewportWidth = rect.width
        let viewportHeight = rect.height

        var minX = targetPoint.x - (viewportWidth / 2)
        minX = min(max(minX, 0), 1 - viewportWidth)

        var minY = targetPoint.y - (viewportHeight / 2)
        minY = min(max(minY, 0), 1 - viewportHeight)

        return CGPoint(
            x: minX + (viewportWidth / 2),
            y: minY + (viewportHeight / 2)
        )
    }

    private static func maximumVisibleScale(for targetPoint: CGPoint, anchoredTo state: PreviewState) -> CGFloat {
        guard !visibleRect(for: state).contains(targetPoint) else {
            return state.scale
        }

        var low: CGFloat = 1
        var high = max(state.scale, 1)
        for _ in 0..<16 {
            let mid = (low + high) / 2
            let candidate = PreviewState(scale: mid, normalizedPoint: state.normalizedPoint)
            if visibleRect(for: candidate).contains(targetPoint) {
                low = mid
            } else {
                high = mid
            }
        }
        return max(low, 1)
    }

    private static func normalizedProgress(_ value: Double, start: Double, end: Double) -> Double {
        guard end > start else { return 1 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private static func interpolate(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        from + ((to - from) * CGFloat(progress))
    }

    private static func motionProgress(
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

    private static func bounceProgress(_ progress: Double, amount: Double) -> Double {
        let clampedAmount = min(max(amount, 0), 1)
        let smoothProgress = eased(progress, style: .smooth, direction: .entering)
        if clampedAmount <= 0 {
            return smoothProgress
        }

        let damping = MotionTuning.bounceMaxDamping - ((MotionTuning.bounceMaxDamping - MotionTuning.bounceMinDamping) * clampedAmount)
        let frequency = MotionTuning.bounceMinFrequency + ((MotionTuning.bounceMaxFrequency - MotionTuning.bounceMinFrequency) * clampedAmount)
        let rawSpring = 1 - (exp(-damping * smoothProgress) * cos(frequency * smoothProgress))
        let terminalSpring = 1 - (exp(-damping) * cos(frequency))
        guard rawSpring.isFinite, terminalSpring.isFinite, abs(terminalSpring) > .ulpOfOne else {
            return smoothProgress
        }

        let normalizedSpring = rawSpring / terminalSpring
        let blend = MotionTuning.bounceMinBlend + ((1 - MotionTuning.bounceMinBlend) * clampedAmount)
        let resolvedProgress = smoothProgress + ((normalizedSpring - smoothProgress) * blend)
        return min(max(resolvedProgress, 0), 1.08)
    }

    private static func eased(_ progress: Double, style: ZoomEaseStyle, direction: MotionDirection) -> Double {
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
            return progress
        }
    }
}
