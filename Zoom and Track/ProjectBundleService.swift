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
    private let libraryIndexFileName = "library-index.json"
    private let manifestFileNames = ["manifest.json", "project.json"]

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

    func createWorkspace(outputDirectory: URL? = nil, captureMetadata: CaptureMetadata) throws -> RecordingWorkspace {
        let timestamp = Self.bundleTimestampFormatter.string(from: Date())
        let bundleName = "cap_\(timestamp)_\(UUID().uuidString.prefix(6).lowercased())"
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
            finalBase = try defaultLibraryRootURL()
            requiresSecurityScopedAccess = false
            securityScopedOutputDirectoryURL = nil
        }

        do {
            let capturesDirectory = try libraryCapturesDirectory(
                libraryRoot: finalBase,
                collectionName: captureMetadata.resolvedCollectionName,
                projectName: captureMetadata.resolvedProjectName
            )
            let exportsDirectory = capturesDirectory.deletingLastPathComponent().appendingPathComponent("Exports", isDirectory: true)
            try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
            _ = uniqueProjectURL(baseDirectory: capturesDirectory, projectName: bundleName)
        } catch {
            stopScopedAccess(for: securityScopedOutputDirectoryURL)
            throw error
        }

        let capturesDirectory = try libraryCapturesDirectory(
            libraryRoot: finalBase,
            collectionName: captureMetadata.resolvedCollectionName,
            projectName: captureMetadata.resolvedProjectName
        )
        let finalProjectURL = uniqueProjectURL(baseDirectory: capturesDirectory, projectName: bundleName)

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
            try projectData.write(to: workspace.finalProjectURL.appendingPathComponent("project.json"), options: .atomic)
            try projectData.write(to: workspace.finalProjectURL.appendingPathComponent("manifest.json"), options: .atomic)

            let envelope = RecordedEventEnvelope(
                schemaVersion: 1,
                timebase: "recording-relative-seconds",
                events: events
            )
            let eventsData = try JSONEncoder.eventsEncoder.encode(envelope)
            try eventsData.write(to: workspace.finalProjectURL.appendingPathComponent("events.json"), options: .atomic)

            let zoomPlan = generateZoomPlan(from: events, captureSource: manifest.captureSource)
            let zoomPlanData = try JSONEncoder.zoomPlanEncoder.encode(zoomPlan)
            try zoomPlanData.write(to: workspace.finalProjectURL.appendingPathComponent("zoomPlan.json"), options: .atomic)
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

        let manifestURL = try resolveManifestURL(in: bundleURL)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw NSError(domain: "ProjectBundleService", code: 3, userInfo: [NSLocalizedDescriptionKey: "This capture is missing its manifest file."])
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
            captureID: manifest.captureID,
            collectionName: manifest.collectionName,
            projectName: manifest.projectName,
            captureType: manifest.captureType,
            captureTitle: manifest.captureTitle,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
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
        try data.write(to: zoomPlanURL, options: .atomic)
    }

    func updateCaptureMetadata(
        in bundleURL: URL,
        captureMetadata: CaptureMetadata,
        updatedAt: Date = Date()
    ) throws -> ProjectManifest {
        let accessURL = try beginPlaybackAccess(for: bundleURL)
        defer {
            endPlaybackAccess(accessURL)
        }

        let existingManifest = try loadManifest(from: bundleURL)
        let updatedManifest = ProjectManifest(
            captureID: existingManifest.captureID,
            name: existingManifest.name,
            collectionName: captureMetadata.resolvedCollectionName,
            projectName: captureMetadata.resolvedProjectName,
            captureType: captureMetadata.captureType,
            captureTitle: captureMetadata.resolvedCaptureTitle,
            createdAt: existingManifest.createdAt,
            updatedAt: updatedAt,
            captureSource: existingManifest.captureSource,
            recordingFileName: existingManifest.recordingFileName,
            eventFileName: existingManifest.eventFileName
        )

        let projectData = try JSONEncoder.manifestEncoder.encode(updatedManifest)
        for fileName in manifestFileNames {
            try projectData.write(
                to: bundleURL.appendingPathComponent(fileName),
                options: .atomic
            )
        }

        return updatedManifest
    }

    func libraryRootURL() throws -> URL {
        if let selectedOutputDirectory = resolvedSelectedOutputDirectory() {
            return selectedOutputDirectory
        }
        return try defaultLibraryRootURL()
    }

    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
        let libraryRoot = try libraryRootURL()
        let accessURL = libraryRoot.startAccessingSecurityScopedResource() ? libraryRoot : nil
        defer {
            accessURL?.stopAccessingSecurityScopedResource()
        }

        let indexURL = libraryRoot.appendingPathComponent(libraryIndexFileName)
        var notices: [String] = []
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder.manifestDecoder.decode(CaptureLibraryIndex.self, from: data) {
            let validated = try await validateIndexedItems(index.items, libraryRoot: libraryRoot, notices: &notices)
            let scannedItems = try await scanLibraryItems(libraryRoot: libraryRoot)
            let mergedItems = mergeLibraryItems(indexItems: validated, scannedItems: scannedItems, notices: &notices)
            try persistLibraryIndex(mergedItems, libraryRoot: libraryRoot)
            return CaptureLibrarySnapshot(
                items: mergedItems.sorted { $0.createdAt > $1.createdAt },
                statusMessage: notices.isEmpty ? nil : notices.joined(separator: " ")
            )
        }

        if fileManager.fileExists(atPath: indexURL.path) {
            notices.append("Library index was unreadable and has been rebuilt.")
        }
        let scannedItems = try await scanLibraryItems(libraryRoot: libraryRoot)
        try persistLibraryIndex(scannedItems, libraryRoot: libraryRoot)
        return CaptureLibrarySnapshot(
            items: scannedItems.sorted { $0.createdAt > $1.createdAt },
            statusMessage: notices.isEmpty ? nil : notices.joined(separator: " ")
        )
    }

    func registerCaptureInLibrary(_ summary: RecordingInspectionSummary) throws {
        let libraryRoot = try libraryRootURL()
        let accessURL = libraryRoot.startAccessingSecurityScopedResource() ? libraryRoot : nil
        defer {
            accessURL?.stopAccessingSecurityScopedResource()
        }

        let relativePath = relativeBundlePath(for: summary.bundleURL, libraryRoot: libraryRoot)
        let newItem = CaptureLibraryItem(
            captureID: summary.captureID,
            title: summary.displayTitle,
            captureType: summary.captureType,
            collectionName: summary.collectionName,
            projectName: summary.projectName,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
            duration: summary.duration,
            bundleRelativePath: relativePath,
            status: .available,
            statusMessage: nil
        )

        let indexURL = libraryRoot.appendingPathComponent(libraryIndexFileName)
        var items: [CaptureLibraryItem] = []
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder.manifestDecoder.decode(CaptureLibraryIndex.self, from: data) {
            items = index.items.filter { $0.captureID != newItem.captureID }
        }
        items.append(newItem)
        try persistLibraryIndex(items, libraryRoot: libraryRoot)
    }

    private func moviesDirectory() throws -> URL {
        guard let directory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "ProjectBundleService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Movies directory is unavailable."])
        }
        return directory
    }

    private func defaultLibraryRootURL() throws -> URL {
        try moviesDirectory().appendingPathComponent("FlowTrack Capture Library", isDirectory: true)
    }

    private func libraryCapturesDirectory(libraryRoot: URL, collectionName: String, projectName: String) throws -> URL {
        let collectionsDirectory = libraryRoot
            .appendingPathComponent("Collections", isDirectory: true)
            .appendingPathComponent(sanitizedProjectName(from: collectionName), isDirectory: true)
            .appendingPathComponent(sanitizedProjectName(from: projectName), isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        try fileManager.createDirectory(at: collectionsDirectory, withIntermediateDirectories: true)
        return collectionsDirectory
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

    private func sanitizedProjectName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Capture" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = fallback.components(separatedBy: invalidCharacters).joined(separator: " ")
        let collapsedWhitespace = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsedWhitespace.isEmpty ? "Capture" : collapsedWhitespace
    }

    private func relativeBundlePath(for bundleURL: URL, libraryRoot: URL) -> String {
        let rootPath = libraryRoot.standardizedFileURL.path + "/"
        let bundlePath = bundleURL.standardizedFileURL.path
        if bundlePath.hasPrefix(rootPath) {
            return String(bundlePath.dropFirst(rootPath.count))
        }
        return bundleURL.lastPathComponent
    }

    private func persistLibraryIndex(_ items: [CaptureLibraryItem], libraryRoot: URL) throws {
        try fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let index = CaptureLibraryIndex(updatedAt: Date(), items: items.sorted { $0.createdAt > $1.createdAt })
        let data = try JSONEncoder.manifestEncoder.encode(index)
        try data.write(to: libraryRoot.appendingPathComponent(libraryIndexFileName), options: .atomic)
    }

    private func validateIndexedItems(
        _ items: [CaptureLibraryItem],
        libraryRoot: URL,
        notices: inout [String]
    ) async throws -> [CaptureLibraryItem] {
        var validatedItems: [CaptureLibraryItem] = []
        var removedCount = 0

        for item in items {
            let bundleURL = libraryRoot.appendingPathComponent(item.bundleRelativePath, isDirectory: true)
            guard fileManager.fileExists(atPath: bundleURL.path) else {
                removedCount += 1
                continue
            }

            validatedItems.append(try await validatedLibraryItem(at: bundleURL, libraryRoot: libraryRoot, fallbackItem: item))
        }

        if removedCount > 0 {
            let noun = removedCount == 1 ? "entry" : "entries"
            notices.append("Removed \(removedCount) stale library \(noun).")
        }

        return validatedItems
    }

    private func mergeLibraryItems(
        indexItems: [CaptureLibraryItem],
        scannedItems: [CaptureLibraryItem],
        notices: inout [String]
    ) -> [CaptureLibraryItem] {
        var mergedByPath = Dictionary(uniqueKeysWithValues: indexItems.map { ($0.bundleRelativePath, $0) })
        var restoredCount = 0

        for item in scannedItems {
            if mergedByPath[item.bundleRelativePath] == nil {
                restoredCount += 1
            }
            mergedByPath[item.bundleRelativePath] = item
        }

        if restoredCount > 0 {
            let noun = restoredCount == 1 ? "capture" : "captures"
            notices.append("Restored \(restoredCount) rediscovered \(noun) to the library.")
        }

        return Array(mergedByPath.values)
    }

    private func scanLibraryItems(libraryRoot: URL) async throws -> [CaptureLibraryItem] {
        let collectionsDirectory = libraryRoot.appendingPathComponent("Collections", isDirectory: true)
        guard fileManager.fileExists(atPath: collectionsDirectory.path) else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: collectionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var items: [CaptureLibraryItem] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "captureproj" else { continue }
            items.append(try await validatedLibraryItem(at: url, libraryRoot: libraryRoot, fallbackItem: nil))
            enumerator?.skipDescendants()
        }
        return items
    }

    private func loadManifest(from bundleURL: URL) throws -> ProjectManifest {
        let manifestURL = try resolveManifestURL(in: bundleURL)
        let manifestData = try Data(contentsOf: manifestURL)
        return try JSONDecoder.manifestDecoder.decode(ProjectManifest.self, from: manifestData)
    }

    private func resolveManifestURL(in bundleURL: URL) throws -> URL {
        for fileName in manifestFileNames {
            let candidate = bundleURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw NSError(
            domain: "ProjectBundleService",
            code: 8,
            userInfo: [NSLocalizedDescriptionKey: "This capture is missing its manifest file."]
        )
    }

    private func validatedLibraryItem(
        at bundleURL: URL,
        libraryRoot: URL,
        fallbackItem: CaptureLibraryItem?
    ) async throws -> CaptureLibraryItem {
        let relativePath = relativeBundlePath(for: bundleURL, libraryRoot: libraryRoot)

        guard fileManager.fileExists(atPath: bundleURL.path) else {
            return fallbackLibraryItem(
                fallbackItem,
                relativePath: relativePath,
                status: .missingBundle,
                statusMessage: "Capture bundle could not be found."
            )
        }

        let manifest: ProjectManifest
        do {
            manifest = try loadManifest(from: bundleURL)
        } catch {
            return fallbackLibraryItem(
                fallbackItem,
                relativePath: relativePath,
                status: .missingManifest,
                statusMessage: "Capture is missing its manifest file."
            )
        }

        let recordingURL = bundleURL.appendingPathComponent(manifest.recordingFileName)
        guard fileManager.fileExists(atPath: recordingURL.path) else {
            return libraryItem(
                from: manifest,
                bundleURL: bundleURL,
                libraryRoot: libraryRoot,
                duration: nil,
                status: .missingRecording,
                statusMessage: "Capture is missing recording.mov."
            )
        }

        let eventsURL = bundleURL.appendingPathComponent(manifest.eventFileName)
        guard fileManager.fileExists(atPath: eventsURL.path) else {
            return libraryItem(
                from: manifest,
                bundleURL: bundleURL,
                libraryRoot: libraryRoot,
                duration: nil,
                status: .missingEvents,
                statusMessage: "Capture is missing events.json. Edit will recreate derived timeline data if possible."
            )
        }

        let zoomPlanURL = bundleURL.appendingPathComponent("zoomPlan.json")
        guard fileManager.fileExists(atPath: zoomPlanURL.path) else {
            return libraryItem(
                from: manifest,
                bundleURL: bundleURL,
                libraryRoot: libraryRoot,
                duration: nil,
                status: .missingZoomPlan,
                statusMessage: "Capture is missing zoomPlan.json. Edit will regenerate it from events when opened."
            )
        }

        let duration = try? await loadRecordingDuration(for: bundleURL, recordingFileName: manifest.recordingFileName)
        return libraryItem(
            from: manifest,
            bundleURL: bundleURL,
            libraryRoot: libraryRoot,
            duration: duration,
            status: .available,
            statusMessage: nil
        )
    }

    private func libraryItem(
        from manifest: ProjectManifest,
        bundleURL: URL,
        libraryRoot: URL,
        duration: Double?,
        status: CaptureLibraryItemStatus,
        statusMessage: String?
    ) -> CaptureLibraryItem {
        CaptureLibraryItem(
            captureID: manifest.captureID,
            title: manifest.captureTitle,
            captureType: manifest.captureType,
            collectionName: manifest.collectionName,
            projectName: manifest.projectName,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            duration: duration,
            bundleRelativePath: relativeBundlePath(for: bundleURL, libraryRoot: libraryRoot),
            status: status,
            statusMessage: statusMessage
        )
    }

    private func fallbackLibraryItem(
        _ fallbackItem: CaptureLibraryItem?,
        relativePath: String,
        status: CaptureLibraryItemStatus,
        statusMessage: String
    ) -> CaptureLibraryItem {
        if let fallbackItem {
            return CaptureLibraryItem(
                captureID: fallbackItem.captureID,
                title: fallbackItem.title,
                captureType: fallbackItem.captureType,
                collectionName: fallbackItem.collectionName,
                projectName: fallbackItem.projectName,
                createdAt: fallbackItem.createdAt,
                updatedAt: fallbackItem.updatedAt,
                duration: fallbackItem.duration,
                bundleRelativePath: relativePath,
                status: status,
                statusMessage: statusMessage
            )
        }

        return CaptureLibraryItem(
            captureID: UUID(),
            title: URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent,
            captureType: .other,
            collectionName: "Unknown Collection",
            projectName: "Unknown Project",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            duration: nil,
            bundleRelativePath: relativePath,
            status: status,
            statusMessage: statusMessage
        )
    }

    private func loadRecordingDuration(for bundleURL: URL, recordingFileName: String) async throws -> Double? {
        let asset = AVURLAsset(url: bundleURL.appendingPathComponent(recordingFileName))
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : nil
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
        try data.write(to: url, options: .atomic)
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
                    bounceAmount: 0.35,
                    noZoomFallbackMode: .pan
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
        try? defaultLibraryRootURL()
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

    private static let bundleTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
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
