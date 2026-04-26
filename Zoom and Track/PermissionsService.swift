//
//  PermissionsService.swift
//  Zoom and Track
//

import CoreGraphics
import Foundation

struct PermissionsService {
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
