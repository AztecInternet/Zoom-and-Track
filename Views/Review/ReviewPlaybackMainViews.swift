import AVFoundation
import SwiftUI

extension ContentView {
    func playbackVideoCard(
        mainPlayer: AVPlayer,
        previewPlayer: AVPlayer?,
        aspectRatio: CGFloat,
        selectedMarker: ZoomPlanItem?,
        selectedEffectMarker: EffectPlanItem?,
        contentCoordinateSize: CGSize,
        zoomMarkers: [ZoomPlanItem],
        effectMarkers: [EffectPlanItem],
        currentTime: Double,
        isRenderedPreviewActive: Bool,
        renderingStatusMessage: String?,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        playbackTransitionPlateState: CaptureSetupViewModel.PlaybackTransitionPlateState,
        isPlacingClickFocus: Bool,
        draggedMarkerSourcePoint: CGPoint?,
        isDrawingNoZoomOverflowRegion: Bool,
        pendingNoZoomOverflowRegion: NoZoomOverflowRegion?,
        isDrawingEffectFocusRegion: Bool,
        pendingEffectFocusRegion: EffectFocusRegion?,
        placeClickFocusAction: @escaping (CGPoint) -> Void,
        dragSelectedMarkerAction: @escaping (CGPoint) -> Void,
        commitDraggedMarkerAction: @escaping (CGPoint) -> Void,
        updateNoZoomOverflowRegionAction: @escaping (NoZoomOverflowRegion?) -> Void,
        updateEffectFocusRegionAction: @escaping (EffectFocusRegion?) -> Void
    ) -> some View {
        let safeAspectRatio = max(aspectRatio, 0.1)

        return ZStack {
            cardBackground

            GeometryReader { geometry in
                let fittedRect = fittedVideoRect(in: geometry.size, aspectRatio: safeAspectRatio)
                let isMarkerDragActive = draggedMarkerSourcePoint != nil
                let isOverflowRegionDrawActive = isDrawingNoZoomOverflowRegion
                let isEffectRegionDrawActive = isDrawingEffectFocusRegion
                let previewState = isRenderedPreviewActive
                    ? nil
                    : isMarkerDragActive
                    ? nil
                    : isOverflowRegionDrawActive
                    ? nil
                    : isEffectRegionDrawActive
                    ? nil
                    : activeZoomPreviewState(
                        at: currentTime,
                        zoomMarkers: zoomMarkers,
                        contentCoordinateSize: contentCoordinateSize
                    )
                let activeEffectState = isRenderedPreviewActive
                    ? nil
                    : isEffectRegionDrawActive
                    ? nil
                    : activeEffectPreviewState(
                        at: currentTime,
                        effectMarkers: effectMarkers
                    )

                ZStack {
                    PlaybackVideoSurface(player: mainPlayer)
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .scaleEffect(previewState?.scale ?? 1, anchor: .topLeading)
                        .offset(zoomPreviewOffset(for: previewState, in: fittedRect))
                        .blur(radius: playbackVideoHeightDragOrigin == nil ? 0 : 4)

                    if let activeEffectState,
                       activeEffectState.style == .blur || activeEffectState.style == .blurDarken,
                       let overlayRect = overlayRect(
                        for: activeEffectState.region,
                        contentCoordinateSize: contentCoordinateSize,
                        in: geometry.size,
                        videoAspectRatio: safeAspectRatio
                    ) {
                        effectBlurLayer(
                            mainPlayer: mainPlayer,
                            effectState: activeEffectState,
                            overlayRect: overlayRect,
                            fittedRect: fittedRect,
                            previewState: previewState
                        )
                    }

                    if let previewPlayer {
                        PlaybackVideoSurface(player: previewPlayer)
                            .frame(width: fittedRect.width, height: fittedRect.height)
                            .opacity(playbackPresentationMode == .playingRenderedPreview ? 1 : 0)
                            .animation(.easeInOut(duration: 0.16), value: playbackPresentationMode == .playingRenderedPreview)
                    }

                    if let activeEffectState,
                       let overlayRect = overlayRect(
                        for: activeEffectState.region,
                        contentCoordinateSize: contentCoordinateSize,
                        in: geometry.size,
                        videoAspectRatio: safeAspectRatio
                    ) {
                        effectPreviewOverlay(
                            effectState: activeEffectState,
                            overlayRect: overlayRect,
                            fittedRect: fittedRect,
                            previewState: previewState
                        )
                    }
                }
                .frame(width: fittedRect.width, height: fittedRect.height)
                .clipped()
                .position(x: fittedRect.midX, y: fittedRect.midY)
                .coordinateSpace(name: "videoOverlay")

                if !isRenderedPreviewActive,
                   !isOverflowRegionDrawActive,
                   let mapping = mappedOverlayPoint(
                    for: selectedMarker,
                    contentCoordinateSize: contentCoordinateSize,
                    in: geometry.size,
                    videoAspectRatio: safeAspectRatio
                ) {
                    let ringSize = 22 + max((selectedMarker?.zoomScale ?? 1.0) - 1.0, 0) * 10
                    let baseHandlePoint = draggedMarkerSourcePoint.flatMap {
                        overlayPoint(
                            for: $0,
                            contentCoordinateSize: contentCoordinateSize,
                            in: geometry.size,
                            videoAspectRatio: safeAspectRatio
                        )
                    } ?? mapping.point
                    let handlePoint = transformedOverlayPoint(
                        baseHandlePoint,
                        in: fittedRect,
                        previewState: previewState
                    )
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 3)
                            .frame(width: ringSize, height: ringSize)
                        Circle()
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 16, height: 16)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 18, height: 2)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 18)
                    }
                    .position(handlePoint)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                            .onChanged { value in
                                guard let sourcePoint = sourcePoint(
                                    for: value.location,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) else {
                                    return
                                }
                                dragSelectedMarkerAction(sourcePoint)
                            }
                            .onEnded { value in
                                guard let sourcePoint = sourcePoint(
                                    for: value.location,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) else {
                                    pendingMarkerDragSourcePoint = nil
                                    return
                                }
                                commitDraggedMarkerAction(sourcePoint)
                            }
                    )
                }

                if isPlacingClickFocus {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.viewfinder")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Click the video to place a Click Focus marker")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.62))
                            )
                        }
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                .onEnded { value in
                                    guard let sourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    placeClickFocusAction(sourcePoint)
                                }
                        )
                }

                if isOverflowRegionDrawActive {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.06))
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .overlay {
                            ZStack {
                                if let region = pendingNoZoomOverflowRegion ?? selectedMarker?.noZoomOverflowRegion,
                                   let overlayRect = overlayRect(
                                    for: region,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) {
                                    let cornerRadii = overflowRegionCornerRadii(
                                        for: overlayRect,
                                        within: fittedRect,
                                        baseRadius: CGFloat(max(selectedEffectMarker?.cornerRadius ?? 18, 0))
                                    )

                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.10))
                                        .frame(width: overlayRect.width, height: overlayRect.height)
                                        .overlay(
                                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                        )
                                        .position(x: overlayRect.midX - fittedRect.minX, y: overlayRect.midY - fittedRect.minY)
                                }

                                VStack(spacing: 8) {
                                    Image(systemName: "viewfinder.rectangular")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Drag to draw the Scale overflow region")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.62))
                                )
                                .padding(.top, 18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                .onChanged { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let currentSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateNoZoomOverflowRegionAction(
                                        noZoomOverflowRegion(
                                            from: startSourcePoint,
                                            to: currentSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                }
                                .onEnded { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let endSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateNoZoomOverflowRegionAction(
                                        noZoomOverflowRegion(
                                            from: startSourcePoint,
                                            to: endSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                }
                        )
                }

                if isEffectRegionDrawActive {
                    Rectangle()
                        .fill(Color.orange.opacity(0.06))
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .overlay {
                            ZStack {
                                if let region = pendingEffectFocusRegion ?? selectedEffectMarker?.focusRegion,
                                   let overlayRect = overlayRect(
                                    for: region,
                                    contentCoordinateSize: contentCoordinateSize,
                                    in: geometry.size,
                                    videoAspectRatio: safeAspectRatio
                                ) {
                                    let cornerRadii = overflowRegionCornerRadii(
                                        for: overlayRect,
                                        within: fittedRect,
                                        baseRadius: CGFloat(max(selectedEffectMarker?.cornerRadius ?? 18, 0))
                                    )

                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .fill(Color.orange.opacity(0.10))
                                        .frame(width: overlayRect.width, height: overlayRect.height)
                                        .overlay(
                                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                                .strokeBorder(Color.orange, lineWidth: 2)
                                        )
                                        .position(x: overlayRect.midX - fittedRect.minX, y: overlayRect.midY - fittedRect.minY)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                                .onChanged { value in
                                                    let baseRegion = effectFocusRegionInteractionBase ?? region
                                                    if effectFocusRegionInteractionBase == nil {
                                                        effectFocusRegionInteractionBase = baseRegion
                                                    }
                                                    activeEffectRegionHandle = nil
                                                    activeEffectRegionPrecisionPoint = CGPoint(
                                                        x: overlayRect.midX + value.translation.width,
                                                        y: overlayRect.midY + value.translation.height
                                                    )
                                                    let deltaX = (value.translation.width / max(fittedRect.width, 1)) * contentCoordinateSize.width
                                                    let deltaY = (value.translation.height / max(fittedRect.height, 1)) * contentCoordinateSize.height
                                                    updateEffectFocusRegionAction(
                                                        movedEffectFocusRegion(
                                                            baseRegion,
                                                            deltaX: deltaX,
                                                            deltaY: deltaY,
                                                            contentCoordinateSize: contentCoordinateSize
                                                        )
                                                    )
                                                }
                                                .onEnded { value in
                                                    let baseRegion = effectFocusRegionInteractionBase ?? region
                                                    activeEffectRegionHandle = nil
                                                    activeEffectRegionPrecisionPoint = CGPoint(
                                                        x: overlayRect.midX + value.translation.width,
                                                        y: overlayRect.midY + value.translation.height
                                                    )
                                                    let deltaX = (value.translation.width / max(fittedRect.width, 1)) * contentCoordinateSize.width
                                                    let deltaY = (value.translation.height / max(fittedRect.height, 1)) * contentCoordinateSize.height
                                                    updateEffectFocusRegionAction(
                                                        movedEffectFocusRegion(
                                                            baseRegion,
                                                            deltaX: deltaX,
                                                            deltaY: deltaY,
                                                            contentCoordinateSize: contentCoordinateSize
                                                        )
                                                    )
                                                    effectFocusRegionInteractionBase = nil
                                                    activeEffectRegionPrecisionPoint = nil
                                                }
                                        )

                                    ForEach(
                                        [
                                            EffectRegionHandle.topLeading,
                                            .topCenter,
                                            .topTrailing,
                                            .centerLeading,
                                            .centerTrailing,
                                            .bottomLeading,
                                            .bottomCenter,
                                            .bottomTrailing
                                        ],
                                        id: \.self
                                    ) { handle in
                                        let handlePoint = effectRegionHandlePoint(for: handle, in: overlayRect)

                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                                            )
                                            .position(x: handlePoint.x - fittedRect.minX, y: handlePoint.y - fittedRect.minY)
                                            .gesture(
                                                DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                                    .onChanged { value in
                                                        let baseRegion = effectFocusRegionInteractionBase ?? region
                                                        if effectFocusRegionInteractionBase == nil {
                                                            effectFocusRegionInteractionBase = baseRegion
                                                        }
                                                        activeEffectRegionHandle = handle
                                                        activeEffectRegionPrecisionPoint = nil
                                                        let resizePoint = CGPoint(
                                                            x: value.location.x + fittedRect.minX,
                                                            y: value.location.y + fittedRect.minY
                                                        )
                                                        updateEffectFocusRegionAction(
                                                            resizedEffectFocusRegion(
                                                                baseRegion,
                                                                dragging: handle,
                                                                to: resizePoint,
                                                                contentCoordinateSize: contentCoordinateSize,
                                                                in: geometry.size,
                                                                videoAspectRatio: safeAspectRatio
                                                            )
                                                        )
                                                    }
                                                    .onEnded { value in
                                                        let baseRegion = effectFocusRegionInteractionBase ?? region
                                                        activeEffectRegionHandle = nil
                                                        activeEffectRegionPrecisionPoint = nil
                                                        let resizePoint = CGPoint(
                                                            x: value.location.x + fittedRect.minX,
                                                            y: value.location.y + fittedRect.minY
                                                        )
                                                        updateEffectFocusRegionAction(
                                                            resizedEffectFocusRegion(
                                                                baseRegion,
                                                                dragging: handle,
                                                                to: resizePoint,
                                                                contentCoordinateSize: contentCoordinateSize,
                                                                in: geometry.size,
                                                                videoAspectRatio: safeAspectRatio
                                                            )
                                                        )
                                                        effectFocusRegionInteractionBase = nil
                                                        activeEffectRegionPrecisionPoint = nil
                                                    }
                                            )
                                    }
                                }

                                VStack(spacing: 8) {
                                    Image(systemName: "viewfinder.rectangular")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Drag to draw, move, or resize the Effect focus region")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.62))
                                )
                                .padding(.top, 18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoOverlay"))
                                .onChanged { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let currentSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateEffectFocusRegionAction(
                                        effectFocusRegion(
                                            from: startSourcePoint,
                                            to: currentSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                    activeEffectRegionHandle = nil
                                    activeEffectRegionPrecisionPoint = value.location
                                }
                                .onEnded { value in
                                    guard let startSourcePoint = sourcePoint(
                                        for: value.startLocation,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ), let endSourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        return
                                    }
                                    updateEffectFocusRegionAction(
                                        effectFocusRegion(
                                            from: startSourcePoint,
                                            to: endSourcePoint,
                                            contentCoordinateSize: contentCoordinateSize
                                        )
                                    )
                                    effectFocusRegionInteractionBase = nil
                                    activeEffectRegionHandle = nil
                                    activeEffectRegionPrecisionPoint = nil
                                }
                        )
                }

                let focusPoint: CGPoint? = {
                       if let region = pendingEffectFocusRegion ?? selectedEffectMarker?.focusRegion,
                          let overlayRect = overlayRect(
                            for: region,
                            contentCoordinateSize: contentCoordinateSize,
                            in: geometry.size,
                            videoAspectRatio: safeAspectRatio
                          ),
                          let activeEffectRegionHandle {
                           return effectRegionHandlePoint(for: activeEffectRegionHandle, in: overlayRect)
                       }
                       return activeEffectRegionPrecisionPoint
                   }()

                if isEffectRegionDrawActive,
                   let focusPoint {
                    effectRegionPrecisionLoupe(
                        player: mainPlayer,
                        fittedRect: fittedRect,
                        focusPoint: focusPoint
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 22)
                    .padding(.trailing, 22)
                    .allowsHitTesting(false)
                }
            }

            if let renderingStatusMessage {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(renderingStatusMessage)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.62))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }

            if playbackTransitionPlateState != .hidden {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    Rectangle()
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16))
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.18),
                            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.plusLighter)

                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 330)
                        .opacity(0.96)

                    if playbackPresentationMode == .previewCompletedSlate {
                        VStack {
                            Spacer()
                            Text("Choose another Zoom Marker from the list or use the transport controls below to play the entire timeline.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.bottom, 20)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .opacity(playbackTransitionPlateOpacity(for: playbackTransitionPlateState))
                .animation(
                    .easeInOut(duration: playbackTransitionPlateAnimationDuration(for: playbackTransitionPlateState)),
                    value: playbackTransitionPlateState
                )
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
        let duration = max(summary.duration ?? 0, 0.001)
        let segmentLayouts = timelineSegmentLayouts(for: summary.zoomMarkers, duration: duration)
        let effectLayouts = effectTimelineSegmentLayouts(for: summary.effectMarkers, duration: duration)
        let trackCenterY: CGFloat = 34
        let segmentOriginY: CGFloat = 16
        let hoveredTooltipEntry = hoveredTimelineTooltipEntry(in: summary)
        let hoveredEffectTooltipEntry = hoveredEffectTimelineTooltipEntry(in: summary)
        let timelineInteractionSuppressed = activeTimelineMarkerDragID != nil || NSEvent.modifierFlags.contains(.option)
        let selectedMarker = editorMode == .zoomAndClicks ? viewModel.selectedZoomMarker : nil
        let showsPulseControls = selectedMarker?.isClickFocus == true
        let showsNoZoomFallbackControls = selectedMarker?.zoomType == .noZoom

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ReviewEditorModeControlStrip(editorMode: editorMode) { mode in
                    editorMode = mode
                }
                Spacer()
                if editorMode == .zoomAndClicks {
                    timelineToolbar(
                        summary: summary,
                        selectedMarker: selectedMarker,
                        showsPulseControls: showsPulseControls,
                        showsNoZoomFallbackControls: showsNoZoomFallbackControls,
                        hasSelectedMarker: viewModel.selectedZoomMarkerID != nil,
                        canEditClickFocusMarkers: viewModel.canEditClickFocusMarkers,
                        isPlacingClickFocus: isPlacingClickFocus,
                        isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion,
                        onToggleAddClickFocus: {
                            if isPlacingClickFocus {
                                isPlacingClickFocus = false
                            } else {
                                viewModel.cancelPlaybackPreview()
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                pendingMarkerDragSourcePoint = nil
                                isPlacingClickFocus = true
                            }
                        },
                        onDeleteSelectedMarker: {
                            viewModel.deleteSelectedMarker()
                        },
                        onToggleClickPulse: {
                            guard let selectedMarker else { return }
                            viewModel.setSelectedMarkerClickPulseEnabled(!selectedMarker.isClickPulseEnabled)
                        },
                        onSelectClickPulsePreset: { preset in
                            viewModel.setSelectedMarkerClickPulsePreset(preset)
                        },
                        onSelectNoZoomFallbackMode: { mode in
                            if mode != .scale {
                                isDrawingNoZoomOverflowRegion = false
                            }
                            viewModel.setSelectedMarkerNoZoomFallbackMode(mode)
                        },
                        onToggleOverflowRegion: {
                            guard let selectedMarker else { return }
                            if isDrawingNoZoomOverflowRegion {
                                viewModel.setSelectedMarkerNoZoomOverflowRegion(
                                    pendingNoZoomOverflowRegion ?? selectedMarker.noZoomOverflowRegion
                                )
                                isDrawingNoZoomOverflowRegion = false
                            } else {
                                viewModel.cancelPlaybackPreview()
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                isPlacingClickFocus = false
                                pendingMarkerDragSourcePoint = nil
                                pendingNoZoomOverflowRegion = selectedMarker.noZoomOverflowRegion
                                isDrawingNoZoomOverflowRegion = true
                                isTimelineKeyboardFocused = true
                            }
                        }
                    )
                        .padding(.trailing, 18)
                } else {
                    EffectsTimelineToolbarView(
                        hasSelectedMarker: viewModel.selectedEffectMarkerID != nil,
                        selectedMarker: viewModel.selectedEffectMarker,
                        isDrawingFocusRegion: isDrawingEffectFocusRegion,
                        onAddMarker: {
                            viewModel.cancelPlaybackPreview()
                            inspectorMode = .markers
                            isPlaybackInspectorVisible = true
                            viewModel.addEffectMarker()
                        },
                        onDeleteSelectedMarker: {
                            viewModel.deleteSelectedEffectMarker()
                        },
                        onToggleFocusRegion: {
                            guard let selectedMarker = viewModel.selectedEffectMarker else { return }
                            if isDrawingEffectFocusRegion {
                                viewModel.setSelectedEffectFocusRegion(
                                    pendingEffectFocusRegion ?? selectedMarker.focusRegion
                                )
                                isDrawingEffectFocusRegion = false
                                effectFocusRegionInteractionBase = nil
                                activeEffectRegionPrecisionPoint = nil
                                activeEffectRegionHandle = nil
                            } else {
                                viewModel.cancelPlaybackPreview()
                                isPlacingClickFocus = false
                                pendingMarkerDragSourcePoint = nil
                                isDrawingNoZoomOverflowRegion = false
                                pendingNoZoomOverflowRegion = nil
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                pendingEffectFocusRegion = selectedMarker.focusRegion
                                effectFocusRegionInteractionBase = nil
                                activeEffectRegionPrecisionPoint = nil
                                activeEffectRegionHandle = nil
                                isDrawingEffectFocusRegion = true
                                isTimelineKeyboardFocused = true
                            }
                        }
                    )
                    .padding(.trailing, 18)
                }
                Text(timecodeString(for: viewModel.currentPlaybackTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 28)

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let playheadX = timelineX(for: viewModel.currentPlaybackTime, duration: duration, width: width)

                timelineCanvasView(
                    width: width,
                    duration: duration,
                    trackCenterY: trackCenterY,
                    segmentOriginY: segmentOriginY,
                    editorMode: editorMode,
                    segmentLayouts: segmentLayouts,
                    effectLayouts: effectLayouts,
                    timelineInteractionSuppressed: timelineInteractionSuppressed,
                    selectedZoomMarkerID: viewModel.selectedZoomMarkerID,
                    hoveredTimelineMarkerID: hoveredTimelineMarkerID,
                    hoveredTimelinePhase: hoveredTimelinePhase,
                    activeTimelineMarkerDragID: activeTimelineMarkerDragID,
                    isOptionModifierActive: NSEvent.modifierFlags.contains(.option),
                    hoveredTooltipMarker: hoveredTooltipEntry?.marker,
                    hoveredTooltipMarkerNumber: hoveredTooltipEntry?.markerNumber,
                    hoveredTooltipAnchor: hoveredTimelineTooltipAnchor,
                    hoveredEffectTimelineMarkerID: hoveredEffectTimelineMarkerID,
                    selectedEffectMarkerID: viewModel.selectedEffectMarkerID,
                    hoveredEffectTooltipMarker: hoveredEffectTooltipEntry?.marker,
                    hoveredEffectTooltipMarkerNumber: hoveredEffectTooltipEntry?.markerNumber,
                    hoveredEffectTooltipAnchor: hoveredEffectTimelineTooltipAnchor,
                    playheadX: playheadX,
                    isDraggingTimeline: isDraggingTimeline,
                    displayedPhaseProvider: { marker in
                        displayedTimelinePhase(for: marker)
                    },
                    zoomPlaybackHighlightProvider: { marker in
                        isMarkerPlaybackHighlighted(marker)
                    },
                    effectPlaybackHighlightProvider: { marker in
                        isEffectPlaybackHighlighted(marker)
                    },
                    onTimelineHoverChanged: { markerID, isHovering, phase, anchor in
                        if isHovering {
                            setTimelineHover(markerID: markerID, phase: phase, anchor: anchor)
                        } else if hoveredTimelineMarkerID == markerID {
                            clearTimelineHover()
                        }
                    },
                    onTimelineTap: { markerID in
                        isTimelineKeyboardFocused = true
                        suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                        viewModel.startMarkerPreview(markerID)
                    },
                    onTimelineOptionDragChanged: { markerID, translationX in
                        isTimelineKeyboardFocused = true
                        guard let layout = segmentLayouts.first(where: { $0.marker.id == markerID }) else { return }
                        if activeTimelineMarkerDragID == nil {
                            activeTimelineMarkerDragID = markerID
                            activeTimelineMarkerDragStartTime = layout.marker.sourceEventTimestamp
                            viewModel.beginTimelineMarkerMove(markerID)
                        }
                        guard activeTimelineMarkerDragID == markerID else { return }
                        let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                        let targetTime = startTime + (Double(translationX / width) * duration)
                        viewModel.previewTimelineMarkerMove(markerID, to: targetTime)
                    },
                    onTimelineOptionDragEnded: { markerID, translationX in
                        isTimelineKeyboardFocused = true
                        guard let layout = segmentLayouts.first(where: { $0.marker.id == markerID }) else { return }
                        guard activeTimelineMarkerDragID == markerID else { return }
                        let startTime = activeTimelineMarkerDragStartTime ?? layout.marker.sourceEventTimestamp
                        let targetTime = startTime + (Double(translationX / width) * duration)
                        viewModel.commitTimelineMarkerMove(markerID, to: targetTime)
                        activeTimelineMarkerDragID = nil
                        activeTimelineMarkerDragStartTime = nil
                    },
                    onEffectHoverChanged: { markerID, isHovering, anchor in
                        guard editorMode == .effects else { return }
                        guard !timelineInteractionSuppressed else {
                            clearEffectTimelineHover()
                            return
                        }
                        if isHovering, let anchor {
                            setEffectTimelineHover(markerID: markerID, anchor: anchor)
                        } else if hoveredEffectTimelineMarkerID == markerID {
                            clearEffectTimelineHover()
                        }
                    },
                    onEffectSelect: { markerID in
                        viewModel.selectEffectMarker(markerID, seekPlaybackHead: true)
                    }
                )
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard activeTimelineMarkerDragID == nil else { return }
                            let currentX = min(max(value.location.x, 0), width)
                            let hasMovedEnough = abs(value.translation.width) > 3

                            if !isDraggingTimeline && hasMovedEnough {
                                isDraggingTimeline = true
                                viewModel.beginTimelineScrub()
                            }

                            if isDraggingTimeline {
                                let zoomSnap = editorMode == .zoomAndClicks
                                    ? timelineSnapTarget(at: currentX, width: width, duration: duration, markers: summary.zoomMarkers)
                                    : nil
                                let effectSnap = editorMode == .effects
                                    ? effectTimelineSnapTarget(at: currentX, width: width, duration: duration, markers: summary.effectMarkers)
                                    : nil
                                viewModel.updateTimelineScrub(
                                    to: zoomSnap?.time ?? effectSnap?.time ?? timelineTime(for: currentX, width: width, duration: duration),
                                    snappedMarkerID: zoomSnap?.marker.id,
                                    snappedEffectMarkerID: effectSnap?.marker.id
                                )
                            }
                        }
                        .onEnded { value in
                            guard activeTimelineMarkerDragID == nil else { return }
                            let endX = min(max(value.location.x, 0), width)
                            let zoomSnap = editorMode == .zoomAndClicks
                                ? timelineSnapTarget(at: endX, width: width, duration: duration, markers: summary.zoomMarkers)
                                : nil
                            let effectSnap = editorMode == .effects
                                ? effectTimelineSnapTarget(at: endX, width: width, duration: duration, markers: summary.effectMarkers)
                                : nil
                            let targetTime = zoomSnap?.time ?? effectSnap?.time ?? timelineTime(for: endX, width: width, duration: duration)

                            if isDraggingTimeline {
                                viewModel.endTimelineScrub(
                                    at: targetTime,
                                    snappedMarkerID: zoomSnap?.marker.id,
                                    snappedEffectMarkerID: effectSnap?.marker.id
                                )
                                isDraggingTimeline = false
                            } else if let zoomSnap {
                                isTimelineKeyboardFocused = true
                                suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                                viewModel.startMarkerPreview(zoomSnap.marker.id)
                            } else if let effectSnap {
                                isTimelineKeyboardFocused = true
                                viewModel.seekTimelineDirectly(
                                    to: targetTime,
                                    snappedMarkerID: nil,
                                    snappedEffectMarkerID: effectSnap.marker.id
                                )
                            } else {
                                viewModel.seekTimelineDirectly(
                                    to: targetTime,
                                    snappedMarkerID: nil,
                                    snappedEffectMarkerID: nil
                                )
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.12), value: isDraggingTimeline)
                .onHover { isHovering in
                    if !isHovering || timelineInteractionSuppressed {
                        clearTimelineHover()
                    }
                }
            }
            .frame(height: 60)

            timelineFooterView(
                duration: duration,
                editorMode: editorMode,
                isDrawingEffectFocusRegion: isDrawingEffectFocusRegion,
                isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion
            )
        }
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($isTimelineKeyboardFocused)
        .onKeyPress(.space) {
            guard viewModel.canUsePlaybackTransport || viewModel.isRenderedPreviewActive || viewModel.playbackPresentationMode == .previewCompletedSlate else {
                return .ignored
            }
            viewModel.togglePlayback()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { keyPress in
            if editorMode == .effects,
               let selectedMarker = viewModel.selectedEffectMarker,
               isDrawingEffectFocusRegion,
               let region = pendingEffectFocusRegion ?? selectedMarker.focusRegion {
                let nudgeDistance = keyPress.modifiers.contains(.option) ? 10.0 : 1.0
                let nudgedRegion: EffectFocusRegion?
                switch keyPress.key {
                case .leftArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: -nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .rightArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .upArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: 0, deltaY: -nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                case .downArrow:
                    nudgedRegion = nudgedEffectFocusRegion(region, deltaX: 0, deltaY: nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                default:
                    nudgedRegion = nil
                }
                if let nudgedRegion {
                    pendingEffectFocusRegion = nudgedRegion
                    return .handled
                }
                return .ignored
            }

            if editorMode == .effects {
                guard viewModel.selectedEffectMarkerID != nil else { return .ignored }
                switch keyPress.key {
                case .leftArrow:
                    viewModel.nudgeSelectedEffectTimelineMarker(by: -1)
                    return .handled
                case .rightArrow:
                    viewModel.nudgeSelectedEffectTimelineMarker(by: 1)
                    return .handled
                default:
                    return .ignored
                }
            }

            guard editorMode == .zoomAndClicks else { return .ignored }
            guard viewModel.selectedZoomMarkerID != nil else { return .ignored }
            if isDrawingNoZoomOverflowRegion,
               let selectedMarker = viewModel.selectedZoomMarker,
               let region = pendingNoZoomOverflowRegion ?? selectedMarker.noZoomOverflowRegion {
                let nudgeDistance = keyPress.modifiers.contains(.option) ? 10.0 : 1.0
                let nudgedRegion: NoZoomOverflowRegion?
                switch keyPress.key {
                case .leftArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: -nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .rightArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: nudgeDistance, deltaY: 0, contentCoordinateSize: summary.contentCoordinateSize)
                case .upArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: 0, deltaY: -nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                case .downArrow:
                    nudgedRegion = nudgedNoZoomOverflowRegion(region, deltaX: 0, deltaY: nudgeDistance, contentCoordinateSize: summary.contentCoordinateSize)
                default:
                    nudgedRegion = nil
                }
                if let nudgedRegion {
                    pendingNoZoomOverflowRegion = nudgedRegion
                    return .handled
                }
                return .ignored
            }
            switch keyPress.key {
            case .leftArrow:
                viewModel.nudgeSelectedTimelineMarker(by: -1)
                return .handled
            case .rightArrow:
                viewModel.nudgeSelectedTimelineMarker(by: 1)
                return .handled
            default:
                return .ignored
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    func playbackInfoPopover(_ summary: RecordingInspectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.bundleName)
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), alignment: .leading),
                    GridItem(.flexible(minimum: 120), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                metadataItem("Bundle", summary.bundleName)
                metadataItem("Duration", summary.duration.map { String(format: "%.3f s", $0) } ?? "n/a")
                metadataItem("Events", "\(summary.totalEventCount)")
                metadataItem("Clicks", "\(summary.leftMouseDownCount + summary.rightMouseDownCount)")
                metadataItem("First Event", summary.firstEventTimestamp.map { String(format: "%.6f", $0) } ?? "n/a")
                metadataItem("Last Event", summary.lastEventTimestamp.map { String(format: "%.6f", $0) } ?? "n/a")
            }

            metadataItem("Path", summary.bundleURL.path, multiline: true)

            Button("Reveal in Finder") {
                viewModel.revealInFinder()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
