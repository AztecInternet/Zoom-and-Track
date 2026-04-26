//
//  ScreenCaptureService.swift
//  Zoom and Track
//

import AppKit
import CoreMedia
import ScreenCaptureKit

final class ScreenCaptureService: NSObject {
    private let sampleQueue = DispatchQueue(label: "TutorialCapture.ScreenCapture")
    private var stream: SCStream?
    private var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    private var onStreamStop: ((Error?) -> Void)?

    func fetchTargets() async throws -> (displays: [ShareableCaptureTarget], windows: [ShareableCaptureTarget]) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (number.uint32Value, screen)
        })

        let displays = content.displays.map { display -> ShareableCaptureTarget in
            let screen = screensByID[display.displayID]
            let width = screen.map { Int($0.frame.width * $0.backingScaleFactor) } ?? Int(display.width) * 2
            let height = screen.map { Int($0.frame.height * $0.backingScaleFactor) } ?? Int(display.height) * 2
            let title = screen?.localizedName ?? "Display \(display.displayID)"

            return ShareableCaptureTarget(
                id: "display-\(display.displayID)",
                kind: .display,
                sourceID: display.displayID,
                title: title,
                subtitle: "\(width)x\(height)",
                width: width,
                height: height
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let windows = content.windows
            .filter { !$0.frame.isEmpty }
            .map { window -> ShareableCaptureTarget in
                let rawTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = rawTitle.isEmpty ? "Untitled Window" : rawTitle
                let appName = window.owningApplication?.applicationName
                let width = max(Int(window.frame.width * 2), 1)
                let height = max(Int(window.frame.height * 2), 1)

                return ShareableCaptureTarget(
                    id: "window-\(window.windowID)",
                    kind: .window,
                    sourceID: window.windowID,
                    title: title,
                    subtitle: appName,
                    width: width,
                    height: height
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return (displays, windows)
    }

    func startCapture(
        target: ShareableCaptureTarget,
        onSampleBuffer: @escaping (CMSampleBuffer) -> Void,
        onStreamStop: @escaping (Error?) -> Void
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try makeFilter(for: target, content: content)
        let configuration = SCStreamConfiguration()
        configuration.width = target.width
        configuration.height = target.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.capturesAudio = false
        configuration.showsCursor = true

        self.onSampleBuffer = onSampleBuffer
        self.onStreamStop = onStreamStop

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stopCapture() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
        self.onSampleBuffer = nil
        self.onStreamStop = nil
    }

    private func makeFilter(for target: ShareableCaptureTarget, content: SCShareableContent) throws -> SCContentFilter {
        switch target.kind {
        case .display:
            guard let display = content.displays.first(where: { $0.displayID == target.sourceID }) else {
                throw NSError(domain: "ScreenCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected display is no longer available."])
            }
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        case .window:
            guard let window = content.windows.first(where: { $0.windowID == target.sourceID }) else {
                throw NSError(domain: "ScreenCaptureService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Selected window is no longer available."])
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }
}

extension ScreenCaptureService: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStreamStop?(error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        onSampleBuffer?(sampleBuffer)
    }
}
