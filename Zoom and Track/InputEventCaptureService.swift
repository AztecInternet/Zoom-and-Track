//
//  InputEventCaptureService.swift
//  Zoom and Track
//

import AppKit
import CoreMedia
import Foundation

@MainActor
final class InputEventCaptureService {
    private struct PendingEvent {
        let type: RecordedEventType
        let uptime: TimeInterval
        let x: Double
        let y: Double
    }

    private let maxCursorSampleRate: TimeInterval = 1.0 / 15.0

    private var leftMouseDownMonitor: Any?
    private var leftMouseUpMonitor: Any?
    private var rightMouseDownMonitor: Any?
    private var rightMouseUpMonitor: Any?
    private var cursorTimer: Timer?

    private var pendingEvents: [PendingEvent] = []
    private var lastCursorPosition: CGPoint?
    private var sessionStartUptime: TimeInterval?

    func start() {
        stop()

        recordCursorMoveIfNeeded(at: NSEvent.mouseLocation, uptime: ProcessInfo.processInfo.systemUptime)

        leftMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in
                self?.recordMouseEvent(type: .leftMouseDown, event: event)
            }
        }
        leftMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in
                self?.recordMouseEvent(type: .leftMouseUp, event: event)
            }
        }
        rightMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in
                self?.recordMouseEvent(type: .rightMouseDown, event: event)
            }
        }
        rightMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            Task { @MainActor in
                self?.recordMouseEvent(type: .rightMouseUp, event: event)
            }
        }

        cursorTimer = Timer.scheduledTimer(withTimeInterval: maxCursorSampleRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = NSEvent.mouseLocation
                let uptime = ProcessInfo.processInfo.systemUptime
                self.recordCursorMoveIfNeeded(at: location, uptime: uptime)
            }
        }
        if let cursorTimer {
            RunLoop.main.add(cursorTimer, forMode: .common)
        }
    }

    func setSessionStart(videoTimestamp: CMTime, uptime: TimeInterval) {
        guard sessionStartUptime == nil else { return }
        sessionStartUptime = uptime
    }

    func stop() {
        [leftMouseDownMonitor, leftMouseUpMonitor, rightMouseDownMonitor, rightMouseUpMonitor]
            .compactMap { $0 }
            .forEach(NSEvent.removeMonitor)

        leftMouseDownMonitor = nil
        leftMouseUpMonitor = nil
        rightMouseDownMonitor = nil
        rightMouseUpMonitor = nil

        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    func finish() -> [RecordedEvent] {
        let events = pendingEvents.compactMap(makeRecordedEvent(from:))
            .sorted { $0.timestamp < $1.timestamp }

        pendingEvents.removeAll()
        lastCursorPosition = nil
        sessionStartUptime = nil

        return events
    }

    func cancel() {
        stop()
        pendingEvents.removeAll()
        lastCursorPosition = nil
        sessionStartUptime = nil
    }

    private func recordMouseEvent(type: RecordedEventType, event: NSEvent) {
        appendPendingEvent(type: type, location: NSEvent.mouseLocation, uptime: event.timestamp)
    }

    private func recordCursorMoveIfNeeded(at location: CGPoint, uptime: TimeInterval) {
        guard lastCursorPosition != location else { return }
        lastCursorPosition = location
        appendPendingEvent(type: .cursorMoved, location: location, uptime: uptime)
    }

    private func appendPendingEvent(type: RecordedEventType, location: CGPoint, uptime: TimeInterval) {
        pendingEvents.append(
            PendingEvent(
                type: type,
                uptime: uptime,
                x: location.x,
                y: location.y
            )
        )
    }

    private func makeRecordedEvent(from pendingEvent: PendingEvent) -> RecordedEvent? {
        guard let sessionStartUptime else { return nil }

        let relativeTimestamp = pendingEvent.uptime - sessionStartUptime
        guard relativeTimestamp >= 0 else { return nil }

        return RecordedEvent(
            type: pendingEvent.type,
            timestamp: relativeTimestamp,
            x: pendingEvent.x,
            y: pendingEvent.y
        )
    }
}
