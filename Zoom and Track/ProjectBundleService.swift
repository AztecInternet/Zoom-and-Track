//
//  ProjectBundleService.swift
//  Zoom and Track
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation

struct ProjectBundleService {
    private let fileManager = FileManager.default
    private let selectedOutputFolderBookmarkKey = "SelectedOutputFolderBookmark"
    private let lastRecordingBundleBookmarkKey = "LastRecordingBundleBookmark"
    private let lastRecordingBundlePathKey = "LastRecordingBundlePath"

    enum OutputDirectoryResolution {
        case none
        case resolved(URL)
        case invalid(String)
    }

    enum RecordingBundleResolution {
        case none
        case resolved(URL)
        case invalid(String)
    }

    func createWorkspace(outputDirectory: URL? = nil) throws -> RecordingWorkspace {
        let timestamp = Self.projectTimestampFormatter.string(from: Date())
        let projectName = "Recording \(timestamp)"
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("TutorialCapture", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let finalBase: URL
        let requiresSecurityScopedAccess: Bool
        let securityScopedOutputDirectoryURL: URL?
        if let outputDirectory {
            guard outputDirectory.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "ProjectBundleService",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "You no longer have access to the selected output folder. Choose Output Folder again."]
                )
            }
            finalBase = outputDirectory
            requiresSecurityScopedAccess = true
            securityScopedOutputDirectoryURL = outputDirectory
        } else {
            finalBase = try moviesDirectory()
                .appendingPathComponent("FlowTrack Capture", isDirectory: true)
            requiresSecurityScopedAccess = false
            securityScopedOutputDirectoryURL = nil
        }

        do {
            try fileManager.createDirectory(at: finalBase, withIntermediateDirectories: true)
            _ = uniqueProjectURL(baseDirectory: finalBase, projectName: projectName)
        } catch {
            stopScopedAccess(for: securityScopedOutputDirectoryURL)
            throw error
        }

        let finalProjectURL = uniqueProjectURL(baseDirectory: finalBase, projectName: projectName)

        return RecordingWorkspace(
            temporaryDirectory: tempRoot,
            temporaryRecordingURL: tempRoot.appendingPathComponent("recording.mov"),
            finalProjectURL: finalProjectURL,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess,
            securityScopedOutputDirectoryURL: securityScopedOutputDirectoryURL
        )
    }

    func finalizeWorkspace(_ workspace: RecordingWorkspace, manifest: ProjectManifest, events: [RecordedEvent]) throws -> URL {
        defer {
            stopScopedAccess(for: workspace.securityScopedOutputDirectoryURL)
        }

        do {
            try fileManager.createDirectory(at: workspace.finalProjectURL, withIntermediateDirectories: true)

            let finalRecordingURL = workspace.finalProjectURL.appendingPathComponent("recording.mov")
            try fileManager.moveItem(at: workspace.temporaryRecordingURL, to: finalRecordingURL)

            let projectData = try JSONEncoder.manifestEncoder.encode(manifest)
            try projectData.write(to: workspace.finalProjectURL.appendingPathComponent("project.json"))

            let envelope = RecordedEventEnvelope(
                schemaVersion: 1,
                timebase: "recording-relative-seconds",
                events: events
            )
            let eventsData = try JSONEncoder.eventsEncoder.encode(envelope)
            try eventsData.write(to: workspace.finalProjectURL.appendingPathComponent("events.json"))

            let zoomPlan = generateZoomPlan(from: events, captureSource: manifest.captureSource)
            let zoomPlanData = try JSONEncoder.zoomPlanEncoder.encode(zoomPlan)
            try zoomPlanData.write(to: workspace.finalProjectURL.appendingPathComponent("zoomPlan.json"))
        } catch {
            throw error
        }

        try removeIfExists(workspace.temporaryDirectory)
        return workspace.finalProjectURL
    }

    func cleanupWorkspace(_ workspace: RecordingWorkspace?) {
        guard let workspace else { return }
        defer {
            stopScopedAccess(for: workspace.securityScopedOutputDirectoryURL)
        }
        try? removeIfExists(workspace.finalProjectURL)
        try? removeIfExists(workspace.temporaryDirectory)
    }

    func chooseOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.directoryURL = resolvedSelectedOutputDirectory() ?? defaultOutputDirectorySuggestion()

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        guard persistOutputDirectory(url) else {
            return nil
        }

        return url
    }

    func resolvedSelectedOutputDirectory() -> URL? {
        switch resolveSelectedOutputDirectory() {
        case .resolved(let url):
            return url
        case .none, .invalid:
            return nil
        }
    }

    func resolveSelectedOutputDirectory() -> OutputDirectoryResolution {
        guard let bookmarkData = UserDefaults.standard.data(forKey: selectedOutputFolderBookmarkKey) else {
            return .none
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                guard persistOutputDirectory(url) else {
                    UserDefaults.standard.removeObject(forKey: selectedOutputFolderBookmarkKey)
                    return .invalid("Saved output folder access is stale. Choose Output Folder again.")
                }
            }

            guard url.startAccessingSecurityScopedResource() else {
                UserDefaults.standard.removeObject(forKey: selectedOutputFolderBookmarkKey)
                return .invalid("Saved output folder access is invalid. Choose Output Folder again.")
            }
            url.stopAccessingSecurityScopedResource()

            return .resolved(url)
        } catch {
            UserDefaults.standard.removeObject(forKey: selectedOutputFolderBookmarkKey)
            return .invalid("Saved output folder access is invalid. Choose Output Folder again.")
        }
    }

    func openRecordingBundle() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Recording"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        guard url.pathExtension == "captureproj" else {
            return nil
        }

        return url
    }

    func loadRecordingInspection(from bundleURL: URL) async throws -> RecordingInspectionSummary {
        let accessURL = try beginPlaybackAccess(for: bundleURL)
        defer {
            endPlaybackAccess(accessURL)
        }

        guard bundleURL.pathExtension == "captureproj" else {
            throw NSError(domain: "ProjectBundleService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Selected item is not a .captureproj bundle."])
        }

        let manifestURL = bundleURL.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw NSError(domain: "ProjectBundleService", code: 3, userInfo: [NSLocalizedDescriptionKey: "project.json is missing from the bundle."])
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder.manifestDecoder.decode(ProjectManifest.self, from: manifestData)

        let recordingURL = bundleURL.appendingPathComponent(manifest.recordingFileName)
        guard fileManager.fileExists(atPath: recordingURL.path) else {
            throw NSError(domain: "ProjectBundleService", code: 4, userInfo: [NSLocalizedDescriptionKey: "recording.mov is missing from the bundle."])
        }

        let eventsURL = bundleURL.appendingPathComponent(manifest.eventFileName)
        let envelope = loadEventsEnvelope(from: eventsURL)
        let zoomPlanURL = bundleURL.appendingPathComponent("zoomPlan.json")
        let zoomPlan = try loadOrCreateZoomPlan(from: zoomPlanURL, events: envelope.events, captureSource: manifest.captureSource)

        let asset = AVURLAsset(url: recordingURL)
        let durationTime = try await asset.load(.duration)
        let videoPixelSize = try await loadVideoPixelSize(from: asset)
        let videoAspectRatio = try await loadVideoAspectRatio(from: asset)
        let durationSeconds = CMTimeGetSeconds(durationTime)
        let duration = durationSeconds.isFinite ? durationSeconds : nil

        return RecordingInspectionSummary(
            bundleURL: bundleURL,
            bundleName: bundleURL.deletingPathExtension().lastPathComponent,
            recordingURL: recordingURL,
            videoAspectRatio: videoAspectRatio,
            contentCoordinateSize: videoPixelSize,
            captureSourceKind: manifest.captureSource.kind,
            captureSourceTitle: manifest.captureSource.title,
            totalEventCount: envelope.events.count,
            cursorMovedCount: envelope.events.filter { $0.type == .cursorMoved }.count,
            leftMouseDownCount: envelope.events.filter { $0.type == .leftMouseDown }.count,
            leftMouseUpCount: envelope.events.filter { $0.type == .leftMouseUp }.count,
            rightMouseDownCount: envelope.events.filter { $0.type == .rightMouseDown }.count,
            rightMouseUpCount: envelope.events.filter { $0.type == .rightMouseUp }.count,
            firstEventTimestamp: envelope.events.first?.timestamp,
            lastEventTimestamp: envelope.events.last?.timestamp,
            duration: duration,
            zoomMarkers: zoomPlan.items
        )
    }

    func persistLastRecordingBundle(_ url: URL) -> Bool {
        UserDefaults.standard.set(url.path, forKey: lastRecordingBundlePathKey)
        if persistSecurityScopedURL(url, key: lastRecordingBundleBookmarkKey) {
            return true
        }
        return fileManager.fileExists(atPath: url.path)
    }

    func resolveLastRecordingBundle() -> RecordingBundleResolution {
        switch resolveSecurityScopedURL(
            forKey: lastRecordingBundleBookmarkKey,
            invalidMessage: "Saved recording access is invalid. Open Recording again."
        ) {
        case .resolved(let url):
            return .resolved(url)
        case .invalid(let message):
            return .invalid(message)
        case .none:
            guard let path = UserDefaults.standard.string(forKey: lastRecordingBundlePathKey) else {
                return .none
            }
            let url = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: url.path) else {
                UserDefaults.standard.removeObject(forKey: lastRecordingBundlePathKey)
                return .invalid("Saved recording could not be found at \(url.path). Open Recording again.")
            }
            return .resolved(url)
        }
    }

    func beginPlaybackAccess(for bundleURL: URL) throws -> URL? {
        if bundleURL.startAccessingSecurityScopedResource() {
            return bundleURL
        }

        if let selectedOutputDirectory = resolvedSelectedOutputDirectory(),
           bundleURL.path.hasPrefix(selectedOutputDirectory.path) {
            guard selectedOutputDirectory.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "ProjectBundleService",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Playback could not access \(bundleURL.path). Choose Output Folder again."]
                )
            }
            return selectedOutputDirectory
        }

        return nil
    }

    func endPlaybackAccess(_ url: URL?) {
        url?.stopAccessingSecurityScopedResource()
    }

    func saveZoomPlan(_ zoomPlan: ZoomPlanEnvelope, in bundleURL: URL) throws {
        let accessURL = try beginPlaybackAccess(for: bundleURL)
        defer {
            endPlaybackAccess(accessURL)
        }

        let zoomPlanURL = bundleURL.appendingPathComponent("zoomPlan.json")
        let data = try JSONEncoder.zoomPlanEncoder.encode(zoomPlan)
        try data.write(to: zoomPlanURL)
    }

    private func moviesDirectory() throws -> URL {
        guard let directory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "ProjectBundleService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Movies directory is unavailable."])
        }
        return directory
    }

    private func uniqueProjectURL(baseDirectory: URL, projectName: String) -> URL {
        var candidate = baseDirectory.appendingPathComponent("\(projectName).captureproj", isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = baseDirectory.appendingPathComponent("\(projectName) \(suffix).captureproj", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private func removeIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func loadEventsEnvelope(from url: URL) -> RecordedEventEnvelope {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder.eventsDecoder.decode(RecordedEventEnvelope.self, from: data) else {
            return RecordedEventEnvelope(schemaVersion: 1, timebase: "recording-relative-seconds", events: [])
        }
        return envelope
    }

    private func loadOrCreateZoomPlan(from url: URL, events: [RecordedEvent], captureSource: CaptureSource) throws -> ZoomPlanEnvelope {
        if fileManager.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let zoomPlan = try? JSONDecoder.zoomPlanDecoder.decode(ZoomPlanEnvelope.self, from: data) {
            return zoomPlan
        }

        let zoomPlan = generateZoomPlan(from: events, captureSource: captureSource)
        let data = try JSONEncoder.zoomPlanEncoder.encode(zoomPlan)
        try data.write(to: url)
        return zoomPlan
    }

    private func generateZoomPlan(from events: [RecordedEvent], captureSource: CaptureSource) -> ZoomPlanEnvelope {
        let clickEvents = events.filter { $0.type == .leftMouseDown }.sorted { $0.timestamp < $1.timestamp }
        var zoomItems: [ZoomPlanItem] = []
        var lastIncludedTimestamp: Double?

        for event in clickEvents {
            if let lastIncludedTimestamp, event.timestamp - lastIncludedTimestamp < 0.75 {
                continue
            }

            let index = zoomItems.count + 1
            let normalizedPoint = normalizeToVideoCoordinates(event: event, captureSource: captureSource)
            let leadInTime = 0.15
            let zoomInDuration = 0.30
            let holdDuration = 1.15
            let zoomOutDuration = 0.40
            let startTime = max(0, event.timestamp - leadInTime - zoomInDuration)
            let holdUntil = event.timestamp + holdDuration
            let endTime = holdUntil + zoomOutDuration
            zoomItems.append(
                ZoomPlanItem(
                    id: String(format: "zoom-%04d", index),
                    type: "zoom",
                    sourceEventTimestamp: event.timestamp,
                    rawX: event.x,
                    rawY: event.y,
                    centerX: normalizedPoint.x,
                    centerY: normalizedPoint.y,
                    zoomScale: 1.8,
                    startTime: startTime,
                    holdUntil: holdUntil,
                    endTime: endTime,
                    leadInTime: leadInTime,
                    zoomInDuration: zoomInDuration,
                    holdDuration: holdDuration,
                    zoomOutDuration: zoomOutDuration,
                    enabled: true,
                    duration: leadInTime + zoomInDuration + holdDuration + zoomOutDuration,
                    easeStyle: .smooth,
                    zoomType: .inOut,
                    bounceAmount: 0.35
                )
            )
            lastIncludedTimestamp = event.timestamp
        }

        return ZoomPlanEnvelope(
            schemaVersion: 1,
            source: "events.json",
            items: zoomItems
        )
    }

    private func normalizeToVideoCoordinates(event: RecordedEvent, captureSource: CaptureSource) -> CGPoint {
        guard let originX = captureSource.originX,
              let originY = captureSource.originY,
              let pointsWidth = captureSource.pointsWidth,
              let pointsHeight = captureSource.pointsHeight,
              let scaleFactor = captureSource.scaleFactor,
              pointsWidth > 0,
              pointsHeight > 0,
              scaleFactor > 0 else {
            return CGPoint(x: event.x, y: event.y)
        }

        let localXPoints = event.x - originX
        let localYPoints = event.y - originY

        let clampedXPoints = min(max(localXPoints, 0), pointsWidth)
        let clampedYPoints = min(max(localYPoints, 0), pointsHeight)

        let pixelX = clampedXPoints * scaleFactor
        let pixelY = (pointsHeight - clampedYPoints) * scaleFactor

        return CGPoint(x: pixelX, y: pixelY)
    }

    private func loadVideoAspectRatio(from asset: AVURLAsset) async throws -> CGFloat {
        let videoPixelSize = try await loadVideoPixelSize(from: asset)
        guard videoPixelSize.width > 0, videoPixelSize.height > 0 else {
            return 16.0 / 9.0
        }

        return videoPixelSize.width / videoPixelSize.height
    }

    private func loadVideoPixelSize(from asset: AVURLAsset) async throws -> CGSize {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            return CGSize(width: 1920, height: 1080)
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)

        guard width > 0, height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }

        return CGSize(width: width, height: height)
    }

    private func persistOutputDirectory(_ url: URL) -> Bool {
        persistSecurityScopedURL(url, key: selectedOutputFolderBookmarkKey)
    }

    private func persistSecurityScopedURL(_ url: URL, key: String) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: key)
            return true
        } catch {
            return false
        }
    }

    private func resolveSecurityScopedURL(forKey key: String, invalidMessage: String) -> RecordingBundleResolution {
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            return .none
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                guard persistSecurityScopedURL(url, key: key) else {
                    UserDefaults.standard.removeObject(forKey: key)
                    return .invalid(invalidMessage)
                }
            }

            return .resolved(url)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            return .invalid(invalidMessage)
        }
    }

    private func defaultOutputDirectorySuggestion() -> URL? {
        try? moviesDirectory().appendingPathComponent("FlowTrack Capture", isDirectory: true)
    }

    private func stopScopedAccess(for url: URL?) {
        url?.stopAccessingSecurityScopedResource()
    }

    private func withScopedAccess<T>(to url: URL, required: Bool, operation: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if required && !didAccess {
            throw NSError(domain: "ProjectBundleService", code: 6, userInfo: [NSLocalizedDescriptionKey: "You no longer have access to the selected output folder. Choose Output Folder again."])
        }
        return try operation()
    }

    private static let projectTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()
}

private extension JSONEncoder {
    static let manifestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let eventsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()

    static let zoomPlanEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()
}

private extension JSONDecoder {
    static let manifestDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let eventsDecoder = JSONDecoder()
    static let zoomPlanDecoder = JSONDecoder()
}
