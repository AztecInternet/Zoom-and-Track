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
    let subtitle: String?
    let width: Int
    let height: Int
    let originX: Double
    let originY: Double
    let pointsWidth: Double
    let pointsHeight: Double
    let scaleFactor: Double

    var displayTitle: String {
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
    let id: UUID
    let name: String
    let createdAt: Date
    let captureSource: CaptureSource
    let recordingFileName: String
    let eventFileName: String
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inOut:
            return "Zoom In & Out"
        case .inOnly:
            return "Zoom In Only"
        case .outOnly:
            return "Zoom Out Only"
        }
    }
}

struct ZoomPlanItem: Codable, Identifiable {
    var id: String
    var type: String
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

    private enum CodingKeys: String, CodingKey {
        case id
        case type
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
    }

    init(
        id: String,
        type: String,
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
        bounceAmount: Double
    ) {
        self.id = id
        self.type = type
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
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
        }
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
}
