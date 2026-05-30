import AppKit
import SwiftUI

extension ContentView {
    private var inspectorAccentRole: FlowTrackAccentRole {
        editorMode == .effects ? .effects : .zoomAndClicks
    }

    func markerInspectorCard(_ summary: RecordingInspectionSummary) -> some View {
        let accentRole = inspectorAccentRole
        return ReviewInspectorCard(
            editorMode: editorMode,
            inspectorMode: $inspectorMode,
            effectMarkerCount: summary.effectMarkers.count,
            accentRole: accentRole
        ) {
            Group {
                switch inspectorMode {
                case .suggestions:
                    SmartSetupReviewPanel(viewModel: viewModel, isEmbeddedInInspector: true)
                case .captureInfo:
                    captureInfoInspector(summary)
                case .markers:
                    markersInspector(summary)
                }
            }
        } effectsContent: {
            effectsInspector(summary)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            inspectorCardBackground(accentRole: accentRole)
        }
        .overlay {
            if isGuidedTourStage(.markerInspector), inspectorMode == .markers {
                FlowTrackOnboardingRegionHighlight()
            } else if isHelpModeEnabled, inspectorMode == .markers {
                HelpModeRegionHighlight()
            }
        }
        .overlay(alignment: .topLeading) {
            HelpModeHintView(
                topic: editorMode == .effects ? .effectsInspector : .zoomInspector,
                isPresented: isHelpModeEnabled && inspectorMode == .markers,
                staggerIndex: 2
            )
            .frame(width: 270, alignment: .leading)
            .padding(12)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func inspectorCardBackground(accentRole: FlowTrackAccentRole?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(flowTrackTheme.inspectorBackground)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(flowTrackTheme.inspectorBorder, lineWidth: 1)

            if let accentRole {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FlowTrackAccent.panelFill(for: accentRole, theme: flowTrackTheme))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(FlowTrackAccent.panelBorder(for: accentRole, theme: flowTrackTheme), lineWidth: 1)
            }
        }
    }

    func effectsInspector(_ summary: RecordingInspectionSummary) -> some View {
        let accentRole = inspectorAccentRole
        let displayedMarkers = displayedEffectMarkerList(summary.effectMarkers)
        let entries = displayedMarkers.enumerated().map { index, marker in
            EffectListEntry(
                marker: marker,
                markerNumber: index + 1,
                isSelected: viewModel.selectedEffectMarkerID == marker.id,
                isPlaybackHighlighted: isEffectPlaybackHighlighted(marker)
            )
        }

        return ResizableInspectorSplitView {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionHeaderView(title: "Effects", accentRole: accentRole)

                if entries.isEmpty {
                    Text("No effect markers")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    EffectListTableView(
                        entries: entries,
                        selectedMarkerID: viewModel.selectedEffectMarkerID,
                        onSelectMarker: { markerID in
                            guard renamingEffectMarkerID == nil else { return }
                            finishEffectFocusRegionDrawing()
                            viewModel.startEffectMarkerPreview(markerID)
                        },
                        onToggleMarkerEnabled: viewModel.toggleEffectMarkerEnabled(_:),
                        onReorderMarkers: viewModel.reorderEffectMarkerList(to:),
                        renamingMarkerID: $renamingEffectMarkerID,
                        markerNameDraft: $effectMarkerNameDraft,
                        onBeginRename: { marker in
                            renamingEffectMarkerID = marker.id
                            effectMarkerNameDraft = marker.resolvedMarkerName
                        },
                        onCommitRename: { markerID, name in
                            viewModel.setEffectMarkerName(name, for: markerID)
                            renamingEffectMarkerID = nil
                        },
                        onCancelRename: {
                            renamingEffectMarkerID = nil
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } bottomContent: {
            effectEditorSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
        let accentRole = inspectorAccentRole
        let displayedMarkers = displayedMarkerList(summary.zoomMarkers)
        let entries = displayedMarkers.enumerated().map { index, marker in
            MarkerListEntry(
                marker: marker,
                markerNumber: index + 1,
                isSelected: viewModel.selectedZoomMarkerID == marker.id,
                isPlaybackHighlighted: isMarkerPlaybackHighlighted(marker)
            )
        }

        return ResizableInspectorSplitView {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionHeaderView(title: "Markers", accentRole: accentRole)

                if entries.isEmpty {
                    Text("No markers")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkerListTableView(
                        entries: entries,
                        selectedMarkerID: viewModel.selectedZoomMarkerID,
                        onSelectMarker: { markerID in
                            guard renamingMarkerID == nil else { return }
                            suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                            viewModel.startMarkerPreview(markerID)
                        },
                        onToggleMarkerEnabled: viewModel.toggleMarkerEnabled(_:),
                        onReorderMarkers: viewModel.reorderMarkerList(to:),
                        accentColor: FlowTrackAccent.color(for: accentRole, theme: flowTrackTheme),
                        renamingMarkerID: $renamingMarkerID,
                        markerNameDraft: $markerNameDraft,
                        onBeginRename: { marker in
                            renamingMarkerID = marker.id
                            markerNameDraft = marker.resolvedMarkerName
                        },
                        onCommitRename: { markerID, name in
                            viewModel.setMarkerName(name, for: markerID)
                            renamingMarkerID = nil
                        },
                        onCancelRename: {
                            renamingMarkerID = nil
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } bottomContent: {
            markerEditorSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    func markerListRow(
        marker: ZoomPlanItem,
        markerNumber: Int,
        isSelected: Bool,
        isPlaybackHighlighted: Bool,
        isGhosted: Bool,
        isLiftedPreview: Bool,
        showsDropTarget: Bool,
        accentRole: FlowTrackAccentRole,
        dragProvider: (() -> NSItemProvider)? = nil
    ) -> AnyView {
        let selectionColor = FlowTrackAccent.color(for: accentRole, theme: flowTrackTheme)
        let backgroundFill: Color = isPlaybackHighlighted
            ? selectionColor.opacity(0.16)
            : isSelected
            ? selectionColor.opacity(0.10)
            : Color.clear
        let strokeColor: Color = isPlaybackHighlighted
            ? selectionColor.opacity(0.42)
            : isSelected
            ? selectionColor.opacity(0.28)
            : Color.secondary.opacity(0.08)

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if let dragProvider {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .onDrag(dragProvider) {
                                markerListDragPreview(
                                    marker: marker,
                                    markerNumber: markerNumber,
                                    isSelected: isSelected,
                                    isPlaybackHighlighted: isPlaybackHighlighted
                                )
                            }
                    } else {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("#\(markerNumber)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(isSelected ? 0.12 : 0.08))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.secondary.opacity(isSelected ? 0.22 : 0.12), lineWidth: 1)
                    )
                Text(timecodeString(for: marker.sourceEventTimestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 88, alignment: .leading)
                Image(systemName: markerTypeSymbol(for: marker.zoomType))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    viewModel.toggleMarkerEnabled(marker.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: marker.enabled ? "checkmark.circle.fill" : "circle")
                        Text(marker.enabled ? "On" : "Off")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(marker.enabled ? selectionColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Label {
                    Text(String(format: "%.1fx", marker.zoomScale))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                } icon: {
                    Image(systemName: "viewfinder.rectangular")
                }
                Label {
                    Text(String(format: "%.2fs", marker.totalSegmentDuration))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                } icon: {
                    Image(systemName: "timer")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if isPlaybackHighlighted {
                Capsule(style: .continuous)
                    .fill(selectionColor)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .overlay(alignment: .top) {
            if showsDropTarget {
                Capsule(style: .continuous)
                    .fill(selectionColor.opacity(0.8))
                    .frame(width: 110, height: 4)
                    .offset(y: -2)
            }
        }
        .opacity(isGhosted ? 0.26 : (marker.enabled ? 1.0 : 0.5))
        .scaleEffect(isLiftedPreview ? 1.03 : 1, anchor: .center)
        .shadow(
            color: isLiftedPreview ? Color.black.opacity(0.18) : Color.clear,
            radius: isLiftedPreview ? 14 : 0,
            x: 0,
            y: isLiftedPreview ? 8 : 0
        ))
    }

    func markerListDragPreview(
        marker: ZoomPlanItem,
        markerNumber: Int,
        isSelected: Bool,
        isPlaybackHighlighted: Bool
    ) -> AnyView {
        let accentRole = inspectorAccentRole
        return AnyView(markerListRow(
            marker: marker,
            markerNumber: markerNumber,
            isSelected: isSelected,
            isPlaybackHighlighted: isPlaybackHighlighted,
            isGhosted: false,
            isLiftedPreview: true,
            showsDropTarget: false,
            accentRole: accentRole,
            dragProvider: nil
        )
        .frame(width: 280))
    }

    @ViewBuilder
    var markerEditorSection: some View {
        let accentRole = inspectorAccentRole
        if let marker = viewModel.selectedZoomMarker {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Marker \(markerDisplayNumber(for: marker))")
                            .font(.headline)
                        Spacer()
                        Text(timecodeString(for: marker.sourceEventTimestamp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if marker.zoomType == .inOut || marker.zoomType == .inOnly {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Zoom Amount")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1fx", marker.zoomScale))
                                .font(.system(size: 12, design: .monospaced))
                        }
                        FlowTrackInspectorSlider(
                            value: marker.zoomScale,
                            in: 1.0...3.0,
                            accentRole: accentRole
                        ) { newValue in
                            viewModel.setSelectedMarkerZoomScale(newValue)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Timing", accentRole: accentRole)

                    switch marker.zoomType {
                    case .inOut:
                        timingSliderRow(
                            title: "Motion to Click Offset",
                            value: marker.leadInTime,
                            range: 0...20,
                            phase: .leadIn,
                            action: viewModel.setSelectedMarkerLeadInTime
                        )
                        timingSliderRow(
                            title: "Zoom In",
                            value: marker.zoomInDuration,
                            range: 0.05...3,
                            phase: .zoomIn,
                            action: viewModel.setSelectedMarkerZoomInDuration
                        )
                        timingSliderRow(
                            title: "Hold",
                            value: marker.holdDuration,
                            range: 0.05...10,
                            phase: .hold,
                            action: viewModel.setSelectedMarkerHoldDuration
                        )
                        timingSliderRow(
                            title: "Zoom Out",
                            value: marker.zoomOutDuration,
                            range: 0.05...3,
                            phase: .zoomOut,
                            action: viewModel.setSelectedMarkerZoomOutDuration
                        )
                    case .inOnly:
                        timingSliderRow(
                            title: "Motion to Click Offset",
                            value: marker.leadInTime,
                            range: 0...20,
                            phase: .leadIn,
                            action: viewModel.setSelectedMarkerLeadInTime
                        )
                        timingSliderRow(
                            title: "Zoom In",
                            value: marker.zoomInDuration,
                            range: 0.05...3,
                            phase: .zoomIn,
                            action: viewModel.setSelectedMarkerZoomInDuration
                        )
                        timingSliderRow(
                            title: "Hold",
                            value: marker.holdDuration,
                            range: 0.05...10,
                            phase: .hold,
                            action: viewModel.setSelectedMarkerHoldDuration
                        )
                    case .outOnly:
                        timingSliderRow(
                            title: "Zoom Out",
                            value: marker.zoomOutDuration,
                            range: 0.05...3,
                            phase: .zoomOut,
                            action: viewModel.setSelectedMarkerZoomOutDuration
                        )
                    case .noZoom:
                        timingSliderRow(
                            title: "Motion to Click Offset",
                            value: marker.leadInTime,
                            range: 0...20,
                            phase: .leadIn,
                            action: viewModel.setSelectedMarkerLeadInTime
                        )
                        timingSliderRow(
                            title: marker.noZoomFallbackMode == .pan ? "Pan Speed" : "Scale Speed",
                            value: marker.zoomInDuration,
                            range: 0.05...3,
                            phase: .zoomIn,
                            action: viewModel.setSelectedMarkerZoomInDuration
                        )
                    }
                }

                if marker.isClickFocus {
                    ClickPulseSelectorControl(
                        accentRole: accentRole,
                        selectedPreset: marker.clickPulse?.preset,
                        onSelectOff: {
                            viewModel.setSelectedMarkerClickPulseEnabled(false)
                        },
                        onSelectPreset: { preset in
                            viewModel.setSelectedMarkerClickPulsePreset(preset)
                        }
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            InspectorSectionHeaderView(title: "Zoom Type", accentRole: accentRole)
                            Picker("Zoom Type", selection: Binding(
                                get: { marker.zoomType },
                                set: { viewModel.setSelectedMarkerZoomType($0) }
                            )) {
                                ForEach(ZoomType.allCases) { zoomType in
                                    Text(zoomType.displayName).tag(zoomType)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ease Style")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Picker("Ease Style", selection: Binding(
                                get: { marker.easeStyle },
                                set: { viewModel.setSelectedMarkerEaseStyle($0) }
                            )) {
                                ForEach(ZoomEaseStyle.allCases) { easeStyle in
                                    Text(easeStyle.displayName).tag(easeStyle)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    if marker.easeStyle == .bounce {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Bounce Amount")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", marker.bounceAmount))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            FlowTrackInspectorSlider(
                                value: marker.bounceAmount,
                                in: 0...1,
                                accentRole: accentRole
                            ) { newValue in
                                viewModel.setSelectedMarkerBounceAmount(newValue)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a marker to edit")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var effectEditorSection: some View {
        let accentRole = inspectorAccentRole
        if let marker = viewModel.selectedEffectMarker {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(marker.resolvedMarkerName)
                            .font(.headline)
                        Spacer()
                        Text(timecodeString(for: marker.sourceEventTimestamp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        InspectorSectionHeaderView(title: "Style", accentRole: accentRole)
                        Spacer()
                        if supportsCreatorDefaults(marker.style) {
                            Menu {
                                Button("Save Current as Default") {
                                    viewModel.saveCurrentEffectStyleAsCreatorDefault()
                                }
                                Button("Reset Effect to Defaults") {
                                    viewModel.applyCreatorDefaultsToSelectedEffectStyle()
                                }
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(FlowTrackAccent.color(for: accentRole, theme: flowTrackTheme))
                                    .frame(width: 28, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .help("Effect default actions")
                        }
                    }
                    Picker("Effect Style", selection: Binding(
                        get: { marker.style },
                        set: { viewModel.setSelectedEffectStyle($0) }
                    )) {
                        ForEach(EffectStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if marker.style == .tint {
                        ColorPicker(
                            "Tint Color",
                            selection: effectTintColorBinding(for: marker),
                            supportsOpacity: false
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                }

                effectAmountEditorSection(for: marker)

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Timing", accentRole: accentRole)
                    let maxTimelineTime = max(viewModel.recordingSummary?.duration ?? marker.endTime, marker.holdEndTime)
                    let maxFadeInDuration = max(min(3.0, marker.holdStartTime), 0)
                    let maxFadeOutDuration = max(min(3.0, maxTimelineTime - marker.holdEndTime), 0)
                    pointTimingRow(
                        title: "Hold Start Point",
                        value: marker.holdStartTime,
                        range: 0...maxTimelineTime,
                        phase: .leadIn,
                        activeHoldPoint: .holdStart,
                        action: setSelectedEffectHoldStartTimeAndFollowPlayback
                    )
                    pointTimingRow(
                        title: "Hold End Point",
                        value: marker.holdEndTime,
                        range: 0...maxTimelineTime,
                        phase: .hold,
                        activeHoldPoint: .holdEnd,
                        action: setSelectedEffectHoldEndTimeAndFollowPlayback
                    )
                    timingSliderRow(
                        title: "Fade In Duration",
                        value: marker.fadeInDuration,
                        range: 0...maxFadeInDuration,
                        phase: .leadIn,
                        action: viewModel.setSelectedEffectFadeInDuration
                    )
                    timingSliderRow(
                        title: "Fade Out Duration",
                        value: marker.fadeOutDuration,
                        range: 0...maxFadeOutDuration,
                        phase: .zoomOut,
                        action: viewModel.setSelectedEffectFadeOutDuration
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Corner Radius")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        FlowTrackInspectorSlider(
                            value: marker.cornerRadius,
                            in: 0...80,
                            accentRole: accentRole
                        ) { newValue in
                            viewModel.setSelectedEffectCornerRadius(newValue)
                        }
                        Text(String(format: "%.0f", marker.cornerRadius))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Feather")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        FlowTrackInspectorSlider(
                            value: marker.feather,
                            in: 0...60,
                            accentRole: accentRole
                        ) { newValue in
                            viewModel.setSelectedEffectFeather(newValue)
                        }
                        Text(String(format: "%.0f", marker.feather))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select an effect marker to edit")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    func supportsCreatorDefaults(_ style: EffectStyle) -> Bool {
        switch style {
        case .blur, .darken, .tint, .distortion:
            return true
        case .blurDarken, .heatHazeEdge:
            return false
        }
    }

    func markerDisplayNumber(for marker: ZoomPlanItem) -> Int {
        guard let summary = viewModel.recordingSummary,
              let index = summary.zoomMarkers.firstIndex(where: { $0.id == marker.id }) else {
            return 0
        }
        return index + 1
    }

    func timingSliderRow(title: String, value: Double, range: ClosedRange<Double>, phase: MarkerTimingPhase, action: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PrecisionTimeField(
                    value: value,
                    range: range,
                    action: action,
                    onBeginEditing: {
                        inspectorFocusedTimingPhase = phase
                    },
                    onEndEditing: {
                        if inspectorFocusedTimingPhase == phase {
                            inspectorFocusedTimingPhase = nil
                        }
                    }
                )
                    .frame(width: 72, height: 22)
            }
            FlowTrackInspectorSlider(
                value: value,
                in: range,
                accentRole: inspectorAccentRole,
                onEditingChanged: { isEditing in
                    inspectorFocusedTimingPhase = isEditing ? phase : (inspectorFocusedTimingPhase == phase ? nil : inspectorFocusedTimingPhase)
                }
            ) { newValue in
                action(newValue)
            }
        }
    }

    func pointTimingRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        phase: MarkerTimingPhase,
        activeHoldPoint: ActiveEffectHoldPoint,
        action: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PrecisionTimeField(
                    value: value,
                    range: range,
                    action: { newValue in
                        beginEffectHoldTimingEdit(activeHoldPoint, phase)
                        action(newValue)
                    },
                    onBeginEditing: {
                        beginEffectHoldTimingEdit(activeHoldPoint, phase)
                    },
                    onEndEditing: {
                        endEffectHoldTimingEdit(activeHoldPoint, phase)
                    }
                )
                .frame(width: 72, height: 22)
            }

            GeometryReader { geometry in
                let lowerBound = range.lowerBound
                let upperBound = range.upperBound
                let span = max(upperBound - lowerBound, 0.0001)
                let clampedValue = min(max(value, lowerBound), upperBound)
                let fraction = min(max((clampedValue - lowerBound) / span, 0), 1)
                let handleInset: CGFloat = 3
                let usableWidth = max(geometry.size.width - (handleInset * 2), 1)
                let handleX = handleInset + (usableWidth * fraction)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)

                    Capsule(style: .continuous)
                        .fill(FlowTrackAccent.color(for: inspectorAccentRole, theme: flowTrackTheme))
                        .frame(width: 4, height: 18)
                        .position(x: handleX, y: geometry.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            beginEffectHoldTimingEdit(activeHoldPoint, phase)
                            let localX = min(max(value.location.x - handleInset, 0), usableWidth)
                            let newFraction = usableWidth <= 0 ? 0 : localX / usableWidth
                            let newValue = lowerBound + (span * newFraction)
                            action(newValue)
                        }
                        .onEnded { _ in
                            endEffectHoldTimingEdit(activeHoldPoint, phase)
                        }
                )
            }
            .frame(height: 18)
        }
    }

    func beginEffectHoldTimingEdit(_ holdPoint: ActiveEffectHoldPoint, _ phase: MarkerTimingPhase) {
        realtimeEffectPreviewResumeTask?.cancel()
        realtimeEffectPreviewResumeTask = nil
        activeEffectHoldPoint = holdPoint
        inspectorFocusedTimingPhase = phase
        suppressRealtimeEffectPreviewDuringTimingEdit = true
    }

    func endEffectHoldTimingEdit(_ holdPoint: ActiveEffectHoldPoint, _ phase: MarkerTimingPhase) {
        if inspectorFocusedTimingPhase == phase {
            inspectorFocusedTimingPhase = nil
        }
        seekPlaybackToActiveEffectHoldPoint(holdPoint)
        scheduleRealtimeEffectPreviewResume(for: holdPoint)
    }

    func seekPlaybackToActiveEffectHoldPoint(_ holdPoint: ActiveEffectHoldPoint) {
        guard let marker = viewModel.selectedEffectMarker else { return }
        switch holdPoint {
        case .holdStart:
            viewModel.seekPlaybackInteractively(to: marker.holdStartTime)
        case .holdEnd:
            viewModel.seekPlaybackInteractively(to: marker.holdEndTime)
        }
    }

    func scheduleRealtimeEffectPreviewResume(for holdPoint: ActiveEffectHoldPoint) {
        realtimeEffectPreviewResumeTask?.cancel()
        realtimeEffectPreviewResumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, activeEffectHoldPoint == holdPoint else { return }
            suppressRealtimeEffectPreviewDuringTimingEdit = false
            realtimeEffectPreviewResumeTask = nil
        }
    }

    func nudgeActiveEffectHoldPoint(by delta: Double) {
        guard let activeEffectHoldPoint else { return }
        beginEffectHoldTimingEdit(
            activeEffectHoldPoint,
            activeEffectHoldPoint == .holdStart ? .leadIn : .hold
        )

        let currentMarker = viewModel.selectedEffectMarker
        switch activeEffectHoldPoint {
        case .holdStart:
            let currentTime = currentMarker?.holdStartTime ?? viewModel.currentPlaybackTime
            setSelectedEffectHoldStartTimeAndFollowPlayback(currentTime + delta)
        case .holdEnd:
            let currentTime = currentMarker?.holdEndTime ?? viewModel.currentPlaybackTime
            setSelectedEffectHoldEndTimeAndFollowPlayback(currentTime + delta)
        }

        seekPlaybackToActiveEffectHoldPoint(activeEffectHoldPoint)
        scheduleRealtimeEffectPreviewResume(for: activeEffectHoldPoint)
    }

    func setSelectedEffectHoldStartTimeAndFollowPlayback(_ time: Double) {
        if viewModel.isPlaybackActive {
            viewModel.togglePlayback()
        }
        viewModel.setSelectedEffectHoldStartTime(time)
        let resolvedTime = viewModel.selectedEffectMarker?.holdStartTime ?? time
        viewModel.seekPlaybackInteractively(to: resolvedTime)
    }

    func setSelectedEffectHoldEndTimeAndFollowPlayback(_ time: Double) {
        if viewModel.isPlaybackActive {
            viewModel.togglePlayback()
        }
        viewModel.setSelectedEffectHoldEndTime(time)
        let resolvedTime = viewModel.selectedEffectMarker?.holdEndTime ?? time
        viewModel.seekPlaybackInteractively(to: resolvedTime)
    }

    @ViewBuilder
    func effectAmountEditorSection(for marker: EffectPlanItem) -> some View {
        switch marker.style {
        case .blur:
            effectAmountSliderRow(
                title: "Blur Amount",
                value: marker.blurAmount,
                action: viewModel.setSelectedEffectBlurAmount
            )
        case .darken:
            effectAmountSliderRow(
                title: "Darken Amount",
                value: marker.darkenAmount,
                action: viewModel.setSelectedEffectDarkenAmount
            )
        case .distortion, .heatHazeEdge:
            distortionEditorSection(for: marker)
        case .tint:
            effectAmountSliderRow(
                title: "Tint Amount",
                value: marker.tintAmount,
                action: viewModel.setSelectedEffectTintAmount
            )
        case .blurDarken:
            VStack(alignment: .leading, spacing: 10) {
                effectAmountSliderRow(
                    title: "Blur Amount",
                    value: marker.blurAmount,
                    action: viewModel.setSelectedEffectBlurAmount
                )
                effectAmountSliderRow(
                    title: "Darken Amount",
                    value: marker.darkenAmount,
                    action: viewModel.setSelectedEffectDarkenAmount
                )
            }
        }
    }

    func distortionEditorSection(for marker: EffectPlanItem) -> some View {
        let distortion = marker.distortion ?? .defaultConfiguration
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preset")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Distortion Preset", selection: Binding(
                    get: { viewModel.distortionPresetSelectionID(for: marker) },
                    set: { viewModel.setSelectedEffectDistortionPresetSelectionID($0) }
                )) {
                    ForEach(viewModel.availableDistortionPresetDescriptors) { descriptor in
                        Text(descriptor.displayName).tag(descriptor.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            effectAmountSliderRow(
                title: "Amount",
                value: marker.amount,
                action: viewModel.setSelectedEffectAmount
            )
            if case .preset = distortion.mapSource {
                effectAmountSliderRow(
                    title: "Turbulence Size",
                    value: distortion.scale,
                    action: viewModel.setSelectedEffectDistortionScale
                )
            }
            effectAmountSliderRow(
                title: "Distortion Blend",
                value: distortion.backgroundBlend,
                action: viewModel.setSelectedEffectDistortionBackgroundBlend
            )
            effectAmountSliderRow(
                title: "Background Blur",
                value: distortion.backgroundBlur,
                action: viewModel.setSelectedEffectDistortionBackgroundBlur
            )

            if case .importedMap = distortion.mapSource {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GLOW EFFECTS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edge Palette")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Picker(
                            "Edge Palette",
                            selection: Binding(
                                get: { distortion.colorEffectPalette },
                                set: viewModel.setSelectedEffectDistortionColorEffectPalette
                            )
                        ) {
                            ForEach(DistortionColorEffectPalette.allCases) { palette in
                                Text(palette.displayName).tag(palette)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    effectAmountSliderRow(
                        title: "Glow Strength",
                        value: distortion.colorEffectGlowStrength,
                        action: viewModel.setSelectedEffectDistortionColorGlowStrength
                    )
                    effectAmountSliderRow(
                        title: "Glow Radius",
                        value: distortion.colorEffectGlowRadius,
                        action: viewModel.setSelectedEffectDistortionColorGlowRadius
                    )
                    effectAmountSliderRow(
                        title: "Intensity",
                        value: distortion.colorEffectAnimationIntensity,
                        action: viewModel.setSelectedEffectDistortionColorAnimationIntensity
                    )
                }
                .padding(.top, 2)
            }
        }
    }

    func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack {
                FlowTrackInspectorSlider(
                    value: value,
                    in: 0...1,
                    accentRole: inspectorAccentRole
                ) { newValue in
                    action(newValue)
                }
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    func markerTypeSymbol(for zoomType: ZoomType) -> String {
        switch zoomType {
        case .inOnly:
            return "arrow.right"
        case .outOnly:
            return "arrow.left"
        case .inOut:
            return "arrow.left.arrow.right"
        case .noZoom:
            return "smallcircle.filled.circle"
        }
    }
}

private struct FlowTrackInspectorSlider: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let value: Double
    let range: ClosedRange<Double>
    let accentRole: FlowTrackAccentRole
    let onEditingChanged: (Bool) -> Void
    let action: (Double) -> Void

    @State private var isDragging = false

    init(
        value: Double,
        in range: ClosedRange<Double>,
        accentRole: FlowTrackAccentRole,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        action: @escaping (Double) -> Void
    ) {
        self.value = value
        self.range = range
        self.accentRole = accentRole
        self.onEditingChanged = onEditingChanged
        self.action = action
    }

    var body: some View {
        GeometryReader { geometry in
            let dimensions = sliderDimensions(in: geometry.size)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: dimensions.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.88))
                    .frame(width: dimensions.filledWidth, height: dimensions.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: dimensions.thumbSize, height: dimensions.thumbSize)
                    .overlay {
                        Circle()
                            .fill(accentColor)
                            .padding(isDragging ? 3 : 4)
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .position(x: dimensions.thumbCenterX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragValue in
                        beginEditingIfNeeded()
                        action(value(for: dragValue.location.x, in: geometry.size))
                    }
                    .onEnded { _ in
                        endEditingIfNeeded()
                    }
            )
            .accessibilityLabel("Inspector slider")
            .accessibilityValue(Text(String(format: "%.2f", clampedValue)))
        }
        .frame(height: 22)
    }

    private var accentColor: Color {
        FlowTrackAccent.color(for: accentRole, theme: flowTrackTheme)
    }

    private var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func sliderDimensions(in size: CGSize) -> (trackHeight: CGFloat, thumbSize: CGFloat, thumbCenterX: CGFloat, filledWidth: CGFloat) {
        let trackHeight: CGFloat = 4
        let thumbSize: CGFloat = 14
        let thumbInset = thumbSize / 2
        let usableWidth = max(size.width - (thumbInset * 2), 1)
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        let fraction = min(max((clampedValue - range.lowerBound) / span, 0), 1)
        let thumbCenterX = thumbInset + (usableWidth * fraction)
        return (trackHeight, thumbSize, thumbCenterX, max(thumbCenterX, 0))
    }

    private func value(for locationX: CGFloat, in size: CGSize) -> Double {
        let thumbInset: CGFloat = 7
        let usableWidth = max(size.width - (thumbInset * 2), 1)
        let localX = min(max(locationX - thumbInset, 0), usableWidth)
        let fraction = usableWidth <= 0 ? 0 : localX / usableWidth
        return range.lowerBound + ((range.upperBound - range.lowerBound) * Double(fraction))
    }

    private func beginEditingIfNeeded() {
        guard !isDragging else { return }
        isDragging = true
        onEditingChanged(true)
    }

    private func endEditingIfNeeded() {
        guard isDragging else { return }
        isDragging = false
        onEditingChanged(false)
    }
}

private struct ClickPulseSelectorControl: View {
    @Environment(\.flowTrackTheme) private var flowTrackTheme

    let accentRole: FlowTrackAccentRole
    let selectedPreset: ClickPulsePreset?
    let onSelectOff: () -> Void
    let onSelectPreset: (ClickPulsePreset) -> Void

    @State private var isPopoverPresented = false

    private var currentSelectionLabel: String {
        if let selectedPreset {
            return selectedPreset.displayName
        }
        return "Off"
    }

    private var selectionColor: Color {
        FlowTrackAccent.color(for: accentRole, theme: flowTrackTheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeaderView(title: "Click Pulse", accentRole: accentRole)

            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(currentSelectionLabel)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    clickPulseRow(title: "Off", isSelected: selectedPreset == nil) {
                        onSelectOff()
                        isPopoverPresented = false
                    }

                    ForEach(ClickPulsePreset.allCases) { preset in
                        clickPulseRow(title: preset.displayName, isSelected: selectedPreset == preset) {
                            onSelectPreset(preset)
                            isPopoverPresented = false
                        }
                    }
                }
                .padding(8)
                .frame(width: 220)
            }
        }
    }

    @ViewBuilder
    private func clickPulseRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? selectionColor : Color.secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? selectionColor.opacity(0.12) : Color.clear)
        )
    }
}
