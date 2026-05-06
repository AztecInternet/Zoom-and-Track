//
//  CaptureTargetManager.swift
//  Zoom and Track
//

import Foundation

struct CaptureTargetRefreshResult {
    let displays: [ShareableCaptureTarget]
    let windows: [ShareableCaptureTarget]
    let selectedTargetID: String?
    let hasScreenRecordingPermission: Bool
    let statusMessage: String?
}

struct CapturePermissionResult {
    let hasScreenRecordingPermission: Bool
    let statusMessage: String
}

struct CaptureTargetManager {
    private let permissionsService: PermissionsService
    private let screenCaptureService: ScreenCaptureService

    init(
        permissionsService: PermissionsService = PermissionsService(),
        screenCaptureService: ScreenCaptureService = ScreenCaptureService()
    ) {
        self.permissionsService = permissionsService
        self.screenCaptureService = screenCaptureService
    }

    func loadTargets(selectedTargetID: String?, silent: Bool) async throws -> CaptureTargetRefreshResult {
        let hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
        let targets = try await screenCaptureService.fetchTargets()
        let allTargets = targets.displays + targets.windows
        let validatedSelectedTargetID: String?
        if let selectedTargetID, allTargets.contains(where: { $0.id == selectedTargetID }) {
            validatedSelectedTargetID = selectedTargetID
        } else {
            validatedSelectedTargetID = nil
        }

        return CaptureTargetRefreshResult(
            displays: targets.displays,
            windows: targets.windows,
            selectedTargetID: validatedSelectedTargetID,
            hasScreenRecordingPermission: hasScreenRecordingPermission,
            statusMessage: silent ? nil : defaultTargetStatusMessage(hasScreenRecordingPermission: hasScreenRecordingPermission)
        )
    }

    func requestScreenRecordingPermission() -> CapturePermissionResult {
        _ = permissionsService.requestScreenRecordingPermission()
        let hasScreenRecordingPermission = permissionsService.hasScreenRecordingPermission()
        return CapturePermissionResult(
            hasScreenRecordingPermission: hasScreenRecordingPermission,
            statusMessage: hasScreenRecordingPermission
                ? "Permission granted. Reload targets if needed."
                : "Grant Screen Recording permission in System Settings, then relaunch the app if capture still fails."
        )
    }

    private func defaultTargetStatusMessage(hasScreenRecordingPermission: Bool) -> String {
        hasScreenRecordingPermission
            ? "Choose one display or one window."
            : "Screen Recording permission is required."
    }
}
