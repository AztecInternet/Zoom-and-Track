//
//  Models.swift
//  Zoom and Track
//

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

struct ZoomPlanItem: Codable, Identifiable {
    let id: String
    let type: String
    let sourceEventTimestamp: Double
    let centerX: Double
    let centerY: Double
    let zoomScale: Double
    let startTime: Double
    let holdUntil: Double
    let endTime: Double
    let enabled: Bool
}

struct RecordingInspectionSummary {
    let bundleURL: URL
    let bundleName: String
    let recordingURL: URL
    let videoAspectRatio: CGFloat
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
