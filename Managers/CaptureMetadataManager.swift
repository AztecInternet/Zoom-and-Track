//
//  CaptureMetadataManager.swift
//  Zoom and Track
//

import Foundation

final class CaptureMetadataManager {
    private let projectBundleService: ProjectBundleService
    private var metadataSaveTask: Task<Void, Never>?

    init(projectBundleService: ProjectBundleService) {
        self.projectBundleService = projectBundleService
    }

    func scheduleSave(
        bundleURL: URL,
        metadata: CaptureMetadata,
        onSaved: @escaping @MainActor (ProjectManifest) async -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        metadataSaveTask?.cancel()
        metadataSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            do {
                let updatedManifest = try projectBundleService.updateCaptureMetadata(
                    in: bundleURL,
                    captureMetadata: metadata
                )
                await onSaved(updatedManifest)
            } catch {
                await onError(error)
            }
        }
    }

    func cancelPendingSave() {
        metadataSaveTask?.cancel()
        metadataSaveTask = nil
    }
}
