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
        autoCommitsEffectFocusRegionOnRelease: Bool,
        pendingEffectFocusRegion: EffectFocusRegion?,
        placeClickFocusAction: @escaping (CGPoint) -> Void,
        dragSelectedMarkerAction: @escaping (CGPoint) -> Void,
        commitDraggedMarkerAction: @escaping (CGPoint) -> Void,
        updateNoZoomOverflowRegionAction: @escaping (NoZoomOverflowRegion?) -> Void,
        updateEffectFocusRegionAction: @escaping (EffectFocusRegion?) -> Void,
        commitEffectFocusRegionAction: @escaping (EffectFocusRegion?) -> Void
    ) -> some View {
        let safeAspectRatio = max(aspectRatio, 0.1)

        return ZStack {
            cardBackground

            GeometryReader { geometry in
                let fittedRect = fittedVideoRect(in: geometry.size, aspectRatio: safeAspectRatio)
                let isMarkerDragActive = draggedMarkerSourcePoint != nil
                let isOverflowRegionDrawActive = isDrawingNoZoomOverflowRegion
                let isEffectRegionDrawActive = isDrawingEffectFocusRegion
                let isDistortionMapOverlayVisible = viewModel.isShowingDistortionMapOverlay &&
                    editorMode == .effects &&
                    viewModel.selectedEffectDistortionOverlayImage != nil
                let shouldSuppressRealtimeEffectPreview = suppressRealtimeEffectPreviewDuringTimingEdit
                let previewState = isRenderedPreviewActive
                    ? nil
                    : isMarkerDragActive
                    ? nil
                    : isOverflowRegionDrawActive
                    ? nil
                    : isEffectRegionDrawActive
                    ? nil
                    : isDistortionMapOverlayVisible
                    ? nil
                    : activeZoomPreviewState(
                        at: currentTime,
                        zoomMarkers: zoomMarkers,
                        contentCoordinateSize: contentCoordinateSize
                    )
                let activeEffectState = isRenderedPreviewActive
                    ? nil
                    : shouldSuppressRealtimeEffectPreview
                    ? nil
                    : isEffectRegionDrawActive
                    ? nil
                    : isDistortionMapOverlayVisible
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

                    if let summary = viewModel.recordingSummary,
                       let selectedEffectMarker,
                       selectedEffectMarker.style == .distortion,
                       !shouldSuppressRealtimeEffectPreview,
                       !isDistortionMapOverlayVisible,
                       !isEffectRegionDrawActive,
                       !isRenderedPreviewActive {
                        RealtimeEffectPreviewSurface(
                            player: mainPlayer,
                            summary: summary,
                            selectedEffectMarker: selectedEffectMarker,
                            currentPlaybackTime: currentTime,
                            logicalVideoSize: fittedRect.size,
                            isVisible: true
                        )
                        .frame(width: fittedRect.width, height: fittedRect.height)
                    }

                    if isDistortionMapOverlayVisible,
                       let overlayImage = viewModel.selectedEffectDistortionOverlayImage {
                        Image(nsImage: overlayImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: fittedRect.width, height: fittedRect.height)
                            .opacity(0.72)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                            }
                    }

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

                if playbackPresentationMode != .playingRenderedPreview,
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
                                    resetClickPointPrecisionLoupe()
                                    return
                                }
                                updateClickPointPrecisionLoupe(at: value.location, fittedRect: fittedRect)
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
                                    resetClickPointPrecisionLoupe()
                                    return
                                }
                                commitDraggedMarkerAction(sourcePoint)
                                resetClickPointPrecisionLoupe()
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
                                .onChanged { value in
                                    guard sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) != nil else {
                                        resetClickPointPrecisionLoupe()
                                        return
                                    }
                                    updateClickPointPrecisionLoupe(at: value.location, fittedRect: fittedRect)
                                }
                                .onEnded { value in
                                    guard let sourcePoint = sourcePoint(
                                        for: value.location,
                                        contentCoordinateSize: contentCoordinateSize,
                                        in: geometry.size,
                                        videoAspectRatio: safeAspectRatio
                                    ) else {
                                        resetClickPointPrecisionLoupe()
                                        return
                                    }
                                    placeClickFocusAction(sourcePoint)
                                    resetClickPointPrecisionLoupe()
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
                                                    updateEffectRegionPrecisionLoupe(at: CGPoint(
                                                        x: overlayRect.midX + value.translation.width,
                                                        y: overlayRect.midY + value.translation.height
                                                    ), fittedRect: fittedRect)
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
                                                    updateEffectRegionPrecisionLoupe(at: CGPoint(
                                                        x: overlayRect.midX + value.translation.width,
                                                        y: overlayRect.midY + value.translation.height
                                                    ), fittedRect: fittedRect)
                                                    let deltaX = (value.translation.width / max(fittedRect.width, 1)) * contentCoordinateSize.width
                                                    let deltaY = (value.translation.height / max(fittedRect.height, 1)) * contentCoordinateSize.height
                                                    let movedRegion = movedEffectFocusRegion(
                                                        baseRegion,
                                                        deltaX: deltaX,
                                                        deltaY: deltaY,
                                                        contentCoordinateSize: contentCoordinateSize
                                                    )
                                                    updateEffectFocusRegionAction(movedRegion)
                                                    if autoCommitsEffectFocusRegionOnRelease {
                                                        commitEffectFocusRegionAction(movedRegion)
                                                    }
                                                    effectFocusRegionInteractionBase = nil
                                                    resetEffectRegionPrecisionLoupe()
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
                                                        updateEffectRegionPrecisionLoupeOffset(
                                                            for: handlePoint,
                                                            fittedRect: fittedRect
                                                        )
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
                                                        let resizePoint = CGPoint(
                                                            x: value.location.x + fittedRect.minX,
                                                            y: value.location.y + fittedRect.minY
                                                        )
                                                        let resizedRegion = resizedEffectFocusRegion(
                                                            baseRegion,
                                                            dragging: handle,
                                                            to: resizePoint,
                                                            contentCoordinateSize: contentCoordinateSize,
                                                            in: geometry.size,
                                                            videoAspectRatio: safeAspectRatio
                                                        )
                                                        updateEffectFocusRegionAction(resizedRegion)
                                                        if autoCommitsEffectFocusRegionOnRelease {
                                                            commitEffectFocusRegionAction(resizedRegion)
                                                        }
                                                        effectFocusRegionInteractionBase = nil
                                                        resetEffectRegionPrecisionLoupe()
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
                                    updateEffectRegionPrecisionLoupe(at: value.location, fittedRect: fittedRect)
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
                                    let drawnRegion = effectFocusRegion(
                                        from: startSourcePoint,
                                        to: endSourcePoint,
                                        contentCoordinateSize: contentCoordinateSize
                                    )
                                    updateEffectFocusRegionAction(drawnRegion)
                                    if autoCommitsEffectFocusRegionOnRelease {
                                        commitEffectFocusRegionAction(drawnRegion)
                                    }
                                    effectFocusRegionInteractionBase = nil
                                    resetEffectRegionPrecisionLoupe()
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
                    positionedPrecisionLoupe(
                        player: mainPlayer,
                        fittedRect: fittedRect,
                        focusPoint: focusPoint,
                        offset: activeEffectRegionLoupeOffset
                    )
                    .allowsHitTesting(false)
                }

                if let focusPoint = activeClickPointPrecisionPoint {
                    positionedPrecisionLoupe(
                        player: mainPlayer,
                        fittedRect: fittedRect,
                        focusPoint: focusPoint,
                        offset: activeClickPointLoupeOffset
                    )
                    .allowsHitTesting(false)
                }
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

                    VStack(spacing: 18) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 330)
                            .opacity(0.96)

                        if let renderingStatusMessage {
                            RenderPreviewActivityView(statusMessage: renderingStatusMessage)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: renderingStatusMessage != nil)

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
        .overlay {
            if isGuidedTourStage(.reviewBasics) {
                FlowTrackOnboardingRegionHighlight()
            } else if isHelpModeEnabled {
                HelpModeRegionHighlight()
            }
        }
        .overlay(alignment: .topLeading) {
            HelpModeHintView(topic: .playbackPreview, isPresented: isHelpModeEnabled, staggerIndex: 0)
                .frame(width: 300, alignment: .leading)
                .padding(14)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func playbackTimelineStrip(_ summary: RecordingInspectionSummary) -> some View {
        let duration = max(summary.duration ?? 0, 0.001)
        let visibleRange = timelineVisibleRange(for: duration)
        let segmentLayouts = timelineSegmentLayouts(for: summary.zoomMarkers, duration: duration, visibleRange: visibleRange)
        let effectLayouts = effectTimelineSegmentLayouts(for: summary.effectMarkers, duration: duration, visibleRange: visibleRange)
        let trackCenterY: CGFloat = 38
        let segmentOriginY = trackCenterY
        let hoveredTooltipEntry = hoveredTimelineTooltipEntry(in: summary)
        let hoveredEffectTooltipEntry = hoveredEffectTimelineTooltipEntry(in: summary)
        let timelineInteractionSuppressed = activeTimelineMarkerDragID != nil
        let selectedMarker = editorMode == .zoomAndClicks ? viewModel.selectedZoomMarker : nil
        let showsNoZoomFallbackControls = selectedMarker?.zoomType == .noZoom
        let timelineHorizontalInset: CGFloat = 14

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                ReviewEditorModeControlStrip(editorMode: editorMode) { mode in
                    editorMode = mode
                }
                Spacer()
                if editorMode == .zoomAndClicks {
                    timelineToolbar(
                        summary: summary,
                        selectedMarker: selectedMarker,
                        showsNoZoomFallbackControls: showsNoZoomFallbackControls,
                        hasSelectedMarker: viewModel.selectedZoomMarkerID != nil,
                        canEditClickFocusMarkers: viewModel.canEditClickFocusMarkers,
                        isPlacingClickFocus: isPlacingClickFocus,
                        isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion,
                        isTimelineScrubSnappingEnabled: isTimelineScrubSnappingEnabled,
                        onToggleAddClickFocus: {
                            if isPlacingClickFocus {
                                isPlacingClickFocus = false
                                resetClickPointPrecisionLoupe()
                            } else {
                                guard viewModel.selectedZoomMarkerID == nil else { return }
                                viewModel.cancelPlaybackPreview()
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                pendingMarkerDragSourcePoint = nil
                                resetClickPointPrecisionLoupe()
                                isPlacingClickFocus = true
                            }
                        },
                        onDeleteSelectedMarker: {
                            viewModel.deleteSelectedMarker()
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
                                resetClickPointPrecisionLoupe()
                                pendingNoZoomOverflowRegion = selectedMarker.noZoomOverflowRegion
                                isDrawingNoZoomOverflowRegion = true
                                isTimelineKeyboardFocused = true
                            }
                        },
                        onToggleTimelineScrubSnapping: {
                            isTimelineScrubSnappingEnabled.toggle()
                        }
                    )
                        .padding(.trailing, 18)
                } else {
                    EffectsTimelineToolbarView(
                        hasSelectedMarker: viewModel.selectedEffectMarkerID != nil,
                        selectedMarker: viewModel.selectedEffectMarker,
                        isDrawingFocusRegion: isDrawingEffectFocusRegion,
                        showsOverlayToggle: viewModel.canShowSelectedDistortionMapOverlay,
                        isShowingOverlay: viewModel.isShowingDistortionMapOverlay,
                        isTimelineScrubSnappingEnabled: isTimelineScrubSnappingEnabled,
                        onAddMarker: {
                            guard viewModel.selectedEffectMarkerID == nil else { return }
                            viewModel.cancelPlaybackPreview()
                            inspectorMode = .markers
                            isPlaybackInspectorVisible = true
                            viewModel.addEffectMarker()
                            pendingEffectFocusRegion = nil
                            effectFocusRegionInteractionBase = nil
                            resetEffectRegionPrecisionLoupe()
                            isDrawingEffectFocusRegion = true
                            autoCommitsEffectFocusRegionOnRelease = true
                            isTimelineKeyboardFocused = true
                        },
                        onDeleteSelectedMarker: {
                            viewModel.deleteSelectedEffectMarker()
                        },
                        onToggleFocusRegion: {
                            guard let selectedMarker = viewModel.selectedEffectMarker else { return }
                            if isDrawingEffectFocusRegion {
                                finishEffectFocusRegionDrawing(with: pendingEffectFocusRegion ?? selectedMarker.focusRegion)
                            } else {
                                viewModel.cancelPlaybackPreview()
                                isPlacingClickFocus = false
                                pendingMarkerDragSourcePoint = nil
                                resetClickPointPrecisionLoupe()
                                isDrawingNoZoomOverflowRegion = false
                                pendingNoZoomOverflowRegion = nil
                                inspectorMode = .markers
                                isPlaybackInspectorVisible = true
                                pendingEffectFocusRegion = selectedMarker.focusRegion
                                effectFocusRegionInteractionBase = nil
                                resetEffectRegionPrecisionLoupe()
                                isDrawingEffectFocusRegion = true
                                autoCommitsEffectFocusRegionOnRelease = selectedMarker.focusRegion == nil
                                isTimelineKeyboardFocused = true
                            }
                        },
                        onToggleOverlay: {
                            viewModel.toggleDistortionMapOverlay()
                        },
                        onToggleTimelineScrubSnapping: {
                            isTimelineScrubSnappingEnabled.toggle()
                        }
                    )
                        .padding(.trailing, 18)
                }
                Text(timecodeString(for: viewModel.currentPlaybackTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geometry in
                let fullWidth = max(geometry.size.width, 1)
                let timelineWidth = max(fullWidth - (timelineHorizontalInset * 2), 1)

                timelineRulerView(
                    visibleRange: visibleRange,
                    width: timelineWidth,
                    topY: 0
                )
                .frame(width: timelineWidth, alignment: .leading)
                .offset(x: timelineHorizontalInset)
            }
            .frame(height: 24)

            GeometryReader { geometry in
                let fullWidth = max(geometry.size.width, 1)
                let timelineWidth = max(fullWidth - (timelineHorizontalInset * 2), 1)
                let playheadX = visibleRange.contains(viewModel.currentPlaybackTime)
                    ? timelineX(for: viewModel.currentPlaybackTime, visibleRange: visibleRange, width: timelineWidth)
                    : nil

                ZStack(alignment: .leading) {
                    timelineCanvasView(
                        width: timelineWidth,
                        duration: duration,
                        visibleRange: visibleRange,
                        trackCenterY: trackCenterY,
                        segmentOriginY: segmentOriginY,
                        editorMode: editorMode,
                        segmentLayouts: segmentLayouts,
                        effectLayouts: effectLayouts,
                        smartSetupHighlightRange: selectedSmartSetupTimelineRange(),
                        smartSetupHighlightPulseToken: viewModel.smartSetupSelectionPulseToken,
                        timelineInteractionSuppressed: timelineInteractionSuppressed,
                        selectedZoomMarkerID: viewModel.selectedZoomMarkerID,
                        hoveredTimelineMarkerID: hoveredTimelineMarkerID,
                        hoveredTimelinePhase: hoveredTimelinePhase,
                        hoveredTooltipMarker: hoveredTooltipEntry?.marker,
                        hoveredTooltipMarkerNumber: hoveredTooltipEntry?.markerNumber,
                        hoveredTooltipAnchor: hoveredTimelineTooltipAnchor,
                        hoveredEffectTimelineMarkerID: hoveredEffectTimelineMarkerID,
                        selectedEffectMarkerID: viewModel.selectedEffectMarkerID,
                        activeEffectHoldPoint: activeEffectHoldPoint,
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
                            let adjustedAnchor = CGPoint(x: anchor.x + timelineHorizontalInset, y: anchor.y)
                            if isHovering {
                                setTimelineHover(markerID: markerID, phase: phase, anchor: adjustedAnchor)
                            } else if hoveredTimelineMarkerID == markerID {
                                clearTimelineHover()
                            }
                        },
                        onTimelineTap: { markerID in
                            isTimelineKeyboardFocused = true
                            suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                            viewModel.selectZoomMarker(markerID, seekPlaybackHead: true)
                        },
                        onEffectHoverChanged: { markerID, isHovering, anchor in
                            guard editorMode == .effects else { return }
                            guard !timelineInteractionSuppressed else {
                                clearEffectTimelineHover()
                                return
                            }
                            if isHovering, let anchor {
                                setEffectTimelineHover(markerID: markerID, anchor: CGPoint(x: anchor.x + timelineHorizontalInset, y: anchor.y))
                            } else if hoveredEffectTimelineMarkerID == markerID {
                                clearEffectTimelineHover()
                            }
                        },
                        onEffectSelect: { markerID in
                            finishEffectFocusRegionDrawing()
                            viewModel.selectEffectMarker(markerID, seekPlaybackHead: true)
                        }
                    )
                    .frame(width: timelineWidth, alignment: .leading)
                    .offset(x: timelineHorizontalInset)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let currentX = min(max(value.location.x - timelineHorizontalInset, 0), timelineWidth)
                            let startX = min(max(value.startLocation.x - timelineHorizontalInset, 0), timelineWidth)
                            let startPoint = CGPoint(x: startX, y: value.startLocation.y)
                            let hasMovedEnough = abs(value.translation.width) > 3

                            if activeTimelineMarkerDragID != nil {
                                updateTimelineMarkerDrag(
                                    cursorX: currentX,
                                    width: timelineWidth,
                                    duration: duration
                                )
                                return
                            }

                            let zoomMarkerDragTarget = editorMode == .zoomAndClicks
                                ? zoomTimelineMarkerHitTarget(
                                    at: startPoint,
                                    width: timelineWidth,
                                    verticalOrigin: segmentOriginY,
                                    layouts: segmentLayouts
                                )
                                : nil

                            if !isDraggingTimeline && hasMovedEnough {
                                if let zoomMarkerDragTarget {
                                    beginTimelineMarkerDrag(
                                        marker: zoomMarkerDragTarget.marker,
                                        startX: startX,
                                        width: timelineWidth,
                                        duration: duration,
                                        visibleRange: visibleRange
                                    )
                                    updateTimelineMarkerDrag(
                                        cursorX: currentX,
                                        width: timelineWidth,
                                        duration: duration
                                    )
                                    return
                                } else {
                                    finishEffectFocusRegionDrawing()
                                    isDraggingTimeline = true
                                    viewModel.beginTimelineScrub()
                                }
                            }

                            if isDraggingTimeline {
                                let zoomSnap = isTimelineScrubSnappingEnabled && editorMode == .zoomAndClicks
                                    ? timelineSnapTarget(at: currentX, width: timelineWidth, visibleRange: visibleRange, markers: summary.zoomMarkers)
                                    : nil
                                let effectSnap = isTimelineScrubSnappingEnabled && editorMode == .effects
                                    ? effectTimelineSnapTarget(at: currentX, width: timelineWidth, visibleRange: visibleRange, markers: summary.effectMarkers)
                                    : nil
                                viewModel.updateTimelineScrub(
                                    to: zoomSnap?.time ?? effectSnap?.time ?? timelineTime(for: currentX, width: timelineWidth, visibleRange: visibleRange),
                                    snappedMarkerID: zoomSnap?.marker.id,
                                    snappedEffectMarkerID: effectSnap?.marker.id
                                )
                                updateTimelineScrubAutoScroll(
                                    cursorX: currentX,
                                    width: timelineWidth,
                                    duration: duration
                                )
                            }
                        }
                        .onEnded { value in
                            let endX = min(max(value.location.x - timelineHorizontalInset, 0), timelineWidth)
                            let endPoint = CGPoint(x: endX, y: value.location.y)

                            if activeTimelineMarkerDragID != nil {
                                finishTimelineMarkerDrag(
                                    cursorX: endX,
                                    width: timelineWidth,
                                    duration: duration
                                )
                                return
                            }

                            let zoomSnap = isTimelineScrubSnappingEnabled && editorMode == .zoomAndClicks
                                ? timelineSnapTarget(at: endX, width: timelineWidth, visibleRange: visibleRange, markers: summary.zoomMarkers)
                                : nil
                            let effectSnap = isTimelineScrubSnappingEnabled && editorMode == .effects
                                ? effectTimelineSnapTarget(at: endX, width: timelineWidth, visibleRange: visibleRange, markers: summary.effectMarkers)
                                : nil
                            let effectHit = editorMode == .effects
                                ? effectTimelineHitTarget(
                                    at: endPoint,
                                    width: timelineWidth,
                                    verticalOrigin: segmentOriginY,
                                    layouts: effectLayouts
                                )
                                : nil
                            let targetTime = zoomSnap?.time ?? effectSnap?.time ?? timelineTime(for: endX, width: timelineWidth, visibleRange: visibleRange)

                            if isDraggingTimeline {
                                cancelTimelineScrubAutoScroll()
                                viewModel.endTimelineScrub(
                                    at: targetTime,
                                    snappedMarkerID: zoomSnap?.marker.id,
                                    snappedEffectMarkerID: effectSnap?.marker.id
                                )
                                isDraggingTimeline = false
                            } else if let zoomSnap {
                                finishEffectFocusRegionDrawing()
                                isTimelineKeyboardFocused = true
                                suppressMarkerListAutoScrollUntil = Date().addingTimeInterval(0.4)
                                viewModel.selectZoomMarker(zoomSnap.marker.id, seekPlaybackHead: true)
                            } else if let effectHit {
                                finishEffectFocusRegionDrawing()
                                isTimelineKeyboardFocused = true
                                viewModel.selectEffectMarker(effectHit.id, seekPlaybackHead: true)
                            } else if let effectSnap {
                                finishEffectFocusRegionDrawing()
                                isTimelineKeyboardFocused = true
                                viewModel.seekTimelineDirectly(
                                    to: targetTime,
                                    snappedMarkerID: nil,
                                    snappedEffectMarkerID: effectSnap.marker.id
                                )
                            } else {
                                finishEffectFocusRegionDrawing()
                                viewModel.seekTimelineDirectly(
                                    to: targetTime,
                                    snappedMarkerID: nil,
                                    snappedEffectMarkerID: nil,
                                    suppressAutoSelectionWhenUnsnapped: true
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
                .overlay {
                    TimelineTrackpadGestureCaptureView(
                        onMagnify: { magnification, locationX, gestureWidth in
                            guard !isDraggingTimeline, activeTimelineMarkerDragID == nil else { return false }
                            return zoomTimelineVisibleRange(
                                magnification: magnification,
                                anchorX: locationX,
                                width: gestureWidth,
                                duration: duration
                            )
                        },
                        onHorizontalScroll: { deltaX, _, gestureWidth in
                            guard !isDraggingTimeline, activeTimelineMarkerDragID == nil else { return false }
                            return panTimelineVisibleRange(
                                deltaX: deltaX,
                                width: gestureWidth,
                                duration: duration
                            )
                        }
                    )
                    .frame(width: timelineWidth)
                    .offset(x: timelineHorizontalInset)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 78)

            timelineFooterView(
                visibleRange: visibleRange,
                editorMode: editorMode,
                isDrawingEffectFocusRegion: isDrawingEffectFocusRegion,
                isDrawingNoZoomOverflowRegion: isDrawingNoZoomOverflowRegion
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if isGuidedTourStage(.timelineMarkers) {
                FlowTrackOnboardingRegionHighlight()
            } else if isHelpModeEnabled {
                HelpModeRegionHighlight()
            }
        }
        .overlay(alignment: .topLeading) {
            HelpModeHintView(topic: .reviewTimeline, isPresented: isHelpModeEnabled, staggerIndex: 1)
                .frame(width: 300, alignment: .leading)
                .padding(.top, 36)
                .padding(.leading, 12)
                .allowsHitTesting(false)
        }
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($isTimelineKeyboardFocused)
        .onKeyPress(.space) {
            viewModel.togglePlayback()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { keyPress in
            if keyPress.modifiers.contains(.option) {
                switch keyPress.key {
                case .leftArrow:
                    navigateToPreviousMarkerFromMenu()
                    return .handled
                case .rightArrow:
                    navigateToNextMarkerFromMenu()
                    return .handled
                default:
                    break
                }
            }

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
                if activeEffectHoldPoint != nil {
                    let nudgeAmount = keyPress.modifiers.contains(.command)
                        ? 0.01
                        : keyPress.modifiers.contains(.option)
                        ? 1.0
                        : 0.1
                    switch keyPress.key {
                    case .leftArrow:
                        nudgeActiveEffectHoldPoint(by: -nudgeAmount)
                        return .handled
                    case .rightArrow:
                        nudgeActiveEffectHoldPoint(by: nudgeAmount)
                        return .handled
                    default:
                        return .ignored
                    }
                }
                switch keyPress.key {
                case .leftArrow:
                    viewModel.nudgeSelectedEffectTimelineMarker(by: -1, stepDuration: timelineFrameDuration)
                    return .handled
                case .rightArrow:
                    viewModel.nudgeSelectedEffectTimelineMarker(by: 1, stepDuration: timelineFrameDuration)
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
                viewModel.nudgeSelectedTimelineMarker(by: -1, stepDuration: timelineFrameDuration)
                return .handled
            case .rightArrow:
                viewModel.nudgeSelectedTimelineMarker(by: 1, stepDuration: timelineFrameDuration)
                return .handled
            default:
                return .ignored
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    func finishEffectFocusRegionDrawing(with region: EffectFocusRegion? = nil) {
        guard isDrawingEffectFocusRegion else { return }

        let resolvedRegion = region ?? pendingEffectFocusRegion ?? viewModel.selectedEffectMarker?.focusRegion
        viewModel.setSelectedEffectFocusRegion(resolvedRegion)
        pendingEffectFocusRegion = nil
        isDrawingEffectFocusRegion = false
        autoCommitsEffectFocusRegionOnRelease = false
        effectFocusRegionInteractionBase = nil
        resetEffectRegionPrecisionLoupe()
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

private struct RenderPreviewActivityView: View {
    let statusMessage: String

    private let messages: [RenderPreviewMessage] = [
        RenderPreviewMessage(symbolName: "sparkles", text: "Polishing the preview"),
        RenderPreviewMessage(symbolName: "rectangle.dashed", text: "Protecting the important bits"),
        RenderPreviewMessage(symbolName: "wand.and.stars", text: "Applying the effect pass"),
        RenderPreviewMessage(symbolName: "slider.horizontal.3", text: "Tuning the visual treatment"),
        RenderPreviewMessage(symbolName: "hourglass", text: "Compositing the frame")
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let message = messages[Int(elapsed / 2.4) % messages.count]
            let phase = elapsed.truncatingRemainder(dividingBy: 1.6) / 1.6

            VStack(spacing: 10) {
                RenderPreviewActivityDots(phase: phase)
                    .frame(width: 184, height: 14)

                HStack(spacing: 7) {
                    Image(systemName: message.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)

                    Text(message.text.isEmpty ? statusMessage : message.text)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.88))
                .id(message.text)
                .transition(.opacity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
        }
    }
}

private struct RenderPreviewActivityDots: View {
    let phase: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            let dotCount = 9
            let dotSize: CGFloat = 6
            let spacing = width / CGFloat(max(dotCount - 1, 1))
            let cyclePosition = phase * Double(dotCount + 4)

            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))

                ForEach(0..<dotCount, id: \.self) { index in
                    let reveal = min(max(cyclePosition - Double(index), 0), 1)
                    let retreat = min(max(cyclePosition - Double(index + 4), 0), 1)
                    let brightness = max(0, reveal - retreat)
                    let pop = sin(brightness * .pi)
                    let dotX = CGFloat(index) * spacing

                    Circle()
                        .fill(Color.accentColor.opacity(0.18 + 0.76 * brightness))
                        .frame(
                            width: dotSize + CGFloat(pop) * 2,
                            height: dotSize + CGFloat(pop) * 2
                        )
                        .position(x: dotX, y: height / 2)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

private struct RenderPreviewMessage {
    let symbolName: String
    let text: String
}
