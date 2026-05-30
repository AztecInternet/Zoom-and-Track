# Export Map

Generated: 2026-05-30 14:12:34

## Files

### Managers/ExportManager.swift
- Lines: 88
- Imports:
- import AppKit
- import Foundation
- import UniformTypeIdentifiers
- Types:
- Line 7:    enum Outcome {
- Functions / Vars:
- Line 13:    private let exportRenderService = ExportRenderService()
- Line 14:    private var exportTask: Task<Void, Never>?
- Line 15:    private var activeExportOperationID = UUID()
- Line 17:    var hasActiveExport: Bool {
- Line 21:    func chooseExportDestination(defaultName: String) -> URL? {
- Line 22:        let panel = NSSavePanel()
- Line 32:    func exportRecording(
- Line 39:        let exportOperationID = UUID()
- Line 45:                let result = try await exportRenderService.exportRecording(
- Line 52:                    let clampedProgress = max(0, min(progress, 1))
- Line 77:    func cancelExport() {
- Line 82:    func reset() {

### Views/Shared/ExportProgressSheetViews.swift
- Lines: 100
- Imports:
- import AppKit
- import SwiftUI
- Types:
- Line 4:extension ContentView {
- Functions / Vars:
- Line 5:    var exportProgressSheet: some View {
- Line 56:    var exportSheetTitle: String {
- Line 75:    var progressValueForDisplay: Double {
- Line 76:        let progress = max(0, min(viewModel.exportProgress, 1))
- Line 87:    func presentExportSharePicker() {
- Line 89:              let exportShareAnchorView else {
- Line 93:        let picker = NSSharingServicePicker(items: [exportedRecordingURL])

