import AppKit
import SwiftUI

extension ContentView {
    func markerInspectorCard(_ summary: RecordingInspectionSummary) -> some View {
        ReviewInspectorCard(
            editorMode: editorMode,
            inspectorMode: $inspectorMode,
            effectMarkerCount: summary.effectMarkers.count
        ) {
            Group {
                switch inspectorMode {
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
        .background(cardBackground)
    }

    func effectsInspector(_ summary: RecordingInspectionSummary) -> some View {
        let displayedMarkers = displayedEffectMarkerList(summary.effectMarkers)
        let entries = displayedMarkers.enumerated().map { index, marker in
            EffectListEntry(
                marker: marker,
                markerNumber: index + 1,
                isSelected: viewModel.selectedEffectMarkerID == marker.id,
                isPlaybackHighlighted: isEffectPlaybackHighlighted(marker)
            )
        }

        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionHeaderView(title: "Effects")

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
                            viewModel.startEffectMarkerPreview(markerID)
                        },
                        onToggleMarkerEnabled: viewModel.toggleEffectMarkerEnabled(_:),
                        onReorderMarkers: viewModel.reorderEffectMarkerList(to:),
                        renamingMarkerID: $renamingEffectMarkerID,
                        markerNameDraft: $effectMarkerNameDraft,
                        onBeginRename: { marker in
                            renamingEffectMarkerID = marker.id
                            effectMarkerNameDraft = marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? marker.markerName ?? ""
                                : "Unnamed Effect"
                        },
                        onCommitRename: { markerID, name in
                            viewModel.setEffectMarkerName(name, for: markerID)
                            renamingEffectMarkerID = nil
                        },
                        onCancelRename: {
                            renamingEffectMarkerID = nil
                        }
                    )
                    .frame(minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            effectEditorSection
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
        }
    }

    func markersInspector(_ summary: RecordingInspectionSummary) -> some View {
        let displayedMarkers = displayedMarkerList(summary.zoomMarkers)
        let entries = displayedMarkers.enumerated().map { index, marker in
            MarkerListEntry(
                marker: marker,
                markerNumber: index + 1,
                isSelected: viewModel.selectedZoomMarkerID == marker.id,
                isPlaybackHighlighted: isMarkerPlaybackHighlighted(marker)
            )
        }

        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionHeaderView(title: "Markers")

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
                        renamingMarkerID: $renamingMarkerID,
                        markerNameDraft: $markerNameDraft,
                        onBeginRename: { marker in
                            renamingMarkerID = marker.id
                            markerNameDraft = marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? marker.markerName ?? ""
                                : "Unnamed Marker"
                        },
                        onCommitRename: { markerID, name in
                            viewModel.setMarkerName(name, for: markerID)
                            renamingMarkerID = nil
                        },
                        onCancelRename: {
                            renamingMarkerID = nil
                        }
                    )
                    .frame(minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            markerEditorSection
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
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
        dragProvider: (() -> NSItemProvider)? = nil
    ) -> AnyView {
        let backgroundFill: Color = isPlaybackHighlighted
            ? Color.accentColor.opacity(0.20)
            : isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.clear
        let strokeColor: Color = isPlaybackHighlighted
            ? Color.accentColor.opacity(0.55)
            : isSelected
            ? Color.accentColor.opacity(0.35)
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
                    .frame(width: 26, alignment: .leading)
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
                    .foregroundStyle(marker.enabled ? Color.accentColor : Color.secondary)
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
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .overlay(alignment: .top) {
            if showsDropTarget {
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.8))
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
        AnyView(markerListRow(
            marker: marker,
            markerNumber: markerNumber,
            isSelected: isSelected,
            isPlaybackHighlighted: isPlaybackHighlighted,
            isGhosted: false,
            isLiftedPreview: true,
            showsDropTarget: false,
            dragProvider: nil
        )
        .frame(width: 280))
    }

    @ViewBuilder
    var markerEditorSection: some View {
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
                        Slider(
                            value: Binding(
                                get: { marker.zoomScale },
                                set: { viewModel.setSelectedMarkerZoomScale($0) }
                            ),
                            in: 1.0...3.0
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Timing")

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
                            InspectorSectionHeaderView(title: "Zoom Type")
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
                            Slider(
                                value: Binding(
                                    get: { marker.bounceAmount },
                                    set: { viewModel.setSelectedMarkerBounceAmount($0) }
                                ),
                                in: 0...1
                            )
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
        if let marker = viewModel.selectedEffectMarker {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(marker.markerName?.isEmpty == false ? (marker.markerName ?? "Unnamed Effect") : "Unnamed Effect")
                            .font(.headline)
                        Spacer()
                        Text(timecodeString(for: marker.sourceEventTimestamp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                effectAmountEditorSection(for: marker)

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Timing")
                    timingSliderRow(
                        title: "Hold",
                        value: max(marker.endTime - marker.sourceEventTimestamp, 0.05),
                        range: 0.05...10,
                        phase: .hold,
                        action: viewModel.setSelectedEffectHoldDuration
                    )
                    timingSliderRow(
                        title: "Fade In",
                        value: marker.fadeInDuration,
                        range: 0.05...3,
                        phase: .leadIn,
                        action: viewModel.setSelectedEffectFadeInDuration
                    )
                    timingSliderRow(
                        title: "Fade Out",
                        value: marker.fadeOutDuration,
                        range: 0.05...3,
                        phase: .zoomOut,
                        action: viewModel.setSelectedEffectFadeOutDuration
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    InspectorSectionHeaderView(title: "Style")
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Corner Radius")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { marker.cornerRadius },
                                set: { viewModel.setSelectedEffectCornerRadius($0) }
                            ),
                            in: 0...80
                        )
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
                        Slider(
                            value: Binding(
                                get: { marker.feather },
                                set: { viewModel.setSelectedEffectFeather($0) }
                            ),
                            in: 0...60
                        )
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
            Slider(
                value: Binding(
                    get: { value },
                    set: action
                ),
                in: range,
                onEditingChanged: { isEditing in
                    inspectorFocusedTimingPhase = isEditing ? phase : (inspectorFocusedTimingPhase == phase ? nil : inspectorFocusedTimingPhase)
                }
            )
        }
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

    func effectAmountSliderRow(title: String, value: Double, action: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack {
                Slider(
                    value: Binding(
                        get: { value },
                        set: action
                    ),
                    in: 0...1
                )
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

private struct ClickPulseSelectorControl: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeaderView(title: "Click Pulse")

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
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
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
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}
