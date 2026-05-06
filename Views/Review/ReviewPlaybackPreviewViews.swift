import AppKit
import AVKit
import SwiftUI

extension ContentView {
    func playbackTransitionPlateOpacity(
        for state: CaptureSetupViewModel.PlaybackTransitionPlateState
    ) -> Double {
        switch state {
        case .hidden:
            return 0
        case .fadingIn, .visible:
            return 1
        case .fadingOut:
            return 0
        }
    }

    func playbackTransitionPlateAnimationDuration(
        for state: CaptureSetupViewModel.PlaybackTransitionPlateState
    ) -> Double {
        switch state {
        case .hidden:
            return 0
        case .fadingIn:
            return 0.12
        case .visible:
            return 0
        case .fadingOut:
            return 0.16
        }
    }

    func activeZoomPreviewState(
        at currentTime: Double,
        zoomMarkers: [ZoomPlanItem],
        contentCoordinateSize: CGSize
    ) -> ZoomPreviewState? {
        guard let state = SharedMotionEngine.activeZoomState(
            at: currentTime,
            zoomMarkers: zoomMarkers,
            contentCoordinateSize: contentCoordinateSize,
            coordinateSpace: .topLeft
        ) else {
            return nil
        }
        return ZoomPreviewState(scale: state.scale, normalizedPoint: state.normalizedPoint)
    }

    func activeEffectPreviewState(
        at currentTime: Double,
        effectMarkers: [EffectPlanItem]
    ) -> EffectPreviewState? {
        let eligibleMarkers = effectMarkers
            .filter { $0.enabled && $0.focusRegion != nil && currentTime >= $0.startTime && currentTime <= $0.endTime }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.sourceEventTimestamp < rhs.sourceEventTimestamp
                }
                return lhs.startTime < rhs.startTime
            }

        guard let marker = eligibleMarkers.last,
              let region = marker.focusRegion else {
            return nil
        }

        let fadeInDuration = max(marker.fadeInDuration, 0)
        let fadeOutDuration = max(marker.fadeOutDuration, 0)
        let fadeInProgress: Double
        if fadeInDuration <= 0.0001 {
            fadeInProgress = 1
        } else {
            fadeInProgress = min(max((currentTime - marker.startTime) / fadeInDuration, 0), 1)
        }

        let fadeOutProgress: Double
        if fadeOutDuration <= 0.0001 {
            fadeOutProgress = 1
        } else {
            fadeOutProgress = min(max((marker.endTime - currentTime) / fadeOutDuration, 0), 1)
        }

        let timingIntensity = min(fadeInProgress, fadeOutProgress)
        let blurIntensity = timingIntensity * min(max(marker.blurAmount, 0), 1)
        let darkenIntensity = timingIntensity * min(max(marker.darkenAmount, 0), 1)
        let tintIntensity = timingIntensity * min(max(marker.tintAmount, 0), 1)
        guard max(blurIntensity, darkenIntensity, tintIntensity) > 0 else { return nil }

        return EffectPreviewState(
            style: marker.style,
            region: region,
            blurIntensity: blurIntensity,
            darkenIntensity: darkenIntensity,
            tintIntensity: tintIntensity,
            cornerRadius: CGFloat(max(marker.cornerRadius, 0)),
            feather: CGFloat(max(marker.feather, 0)),
            tintColor: color(for: marker.tintColor)
        )
    }

    func effectPreviewOverlay(
        effectState: EffectPreviewState,
        overlayRect: CGRect,
        fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> some View {
        let overlayColor = effectPreviewOverlayColor(for: effectState)
        guard overlayColor != .clear else {
            return AnyView(EmptyView())
        }
        let transformedRect = transformedOverlayRect(
            overlayRect,
            in: fittedRect,
            previewState: previewState
        )
        let cornerRadii = overflowRegionCornerRadii(
            for: transformedRect,
            within: fittedRect,
            baseRadius: effectState.cornerRadius
        )
        let localOverlayRect = CGRect(
            x: transformedRect.minX - fittedRect.minX,
            y: transformedRect.minY - fittedRect.minY,
            width: transformedRect.width,
            height: transformedRect.height
        )
        return AnyView(
            Rectangle()
                .fill(overlayColor)
                .mask {
                    effectOutsideMask(
                        localOverlayRect: localOverlayRect,
                        cornerRadii: cornerRadii,
                        canvasSize: fittedRect.size,
                        feather: effectState.feather
                    )
                }
                .frame(width: fittedRect.width, height: fittedRect.height)
        )
    }

    func effectBlurLayer(
        mainPlayer: AVPlayer,
        effectState: EffectPreviewState,
        overlayRect: CGRect,
        fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> some View {
        let transformedRect = transformedOverlayRect(
            overlayRect,
            in: fittedRect,
            previewState: previewState
        )
        let cornerRadii = overflowRegionCornerRadii(
            for: transformedRect,
            within: fittedRect,
            baseRadius: effectState.cornerRadius
        )
        let localOverlayRect = CGRect(
            x: transformedRect.minX - fittedRect.minX,
            y: transformedRect.minY - fittedRect.minY,
            width: transformedRect.width,
            height: transformedRect.height
        )

        return AnyView(PlaybackVideoLayerSurface(player: mainPlayer)
            .frame(width: fittedRect.width, height: fittedRect.height)
            .scaleEffect(previewState?.scale ?? 1, anchor: .topLeading)
            .offset(zoomPreviewOffset(for: previewState, in: fittedRect))
            .blur(radius: 28 * effectState.blurIntensity)
            .mask {
                effectOutsideMask(
                    localOverlayRect: localOverlayRect,
                    cornerRadii: cornerRadii,
                    canvasSize: fittedRect.size,
                    feather: effectState.feather
                )
            })
    }

    func effectOutsideMask(
        localOverlayRect: CGRect,
        cornerRadii: RectangleCornerRadii,
        canvasSize: CGSize,
        feather: CGFloat
    ) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay {
                UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                    .fill(Color.white)
                    .frame(width: localOverlayRect.width, height: localOverlayRect.height)
                    .position(x: localOverlayRect.midX, y: localOverlayRect.midY)
                    .blur(radius: max(feather, 0))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
    }

    func effectPreviewOverlayColor(for effectState: EffectPreviewState) -> Color {
        switch effectState.style {
        case .darken:
            return Color.black.opacity(effectState.darkenIntensity)
        case .blurDarken:
            return Color.black.opacity(effectState.darkenIntensity)
        case .tint:
            return effectState.tintColor.opacity(0.42 * effectState.tintIntensity)
        case .blur:
            return .clear
        }
    }

    func color(for tintColor: EffectTintColor) -> Color {
        Color(
            .sRGB,
            red: min(max(tintColor.red, 0), 1),
            green: min(max(tintColor.green, 0), 1),
            blue: min(max(tintColor.blue, 0), 1),
            opacity: min(max(tintColor.alpha, 0), 1)
        )
    }

    func transformedOverlayRect(
        _ rect: CGRect,
        in fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> CGRect {
        guard let previewState else { return rect }

        let topLeft = transformedOverlayPoint(
            CGPoint(x: rect.minX, y: rect.minY),
            in: fittedRect,
            previewState: previewState
        )
        let bottomRight = transformedOverlayPoint(
            CGPoint(x: rect.maxX, y: rect.maxY),
            in: fittedRect,
            previewState: previewState
        )

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).standardized
    }

    func zoomPreviewOffset(for previewState: ZoomPreviewState?, in fittedRect: CGRect) -> CGSize {
        guard let previewState, fittedRect.width > 0, fittedRect.height > 0 else {
            return .zero
        }
        return SharedMotionEngine.previewOffset(
            for: SharedMotionEngine.PreviewState(
                scale: previewState.scale,
                normalizedPoint: previewState.normalizedPoint
            ),
            outputSize: fittedRect.size
        )
    }

    func zoomTimeline(for marker: ZoomPlanItem) -> (startTime: Double, peakTime: Double, holdUntil: Double, endTime: Double) {
        let timeline = SharedMotionEngine.zoomTimeline(for: marker)
        return (timeline.startTime, timeline.peakTime, timeline.holdUntil, timeline.endTime)
    }

    func overlayPoint(
        for sourcePoint: CGPoint,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGPoint? {
        guard contentCoordinateSize.width > 0,
              contentCoordinateSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return nil
        }

        let fittedRect = fittedVideoRect(in: containerSize, aspectRatio: videoAspectRatio)
        guard fittedRect.width > 0, fittedRect.height > 0 else {
            return nil
        }

        let normalizedX = min(max(sourcePoint.x / contentCoordinateSize.width, 0), 1)
        let normalizedY = min(max(sourcePoint.y / contentCoordinateSize.height, 0), 1)
        let x = fittedRect.minX + (normalizedX * fittedRect.width)
        let y = fittedRect.minY + (normalizedY * fittedRect.height)
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    func sourcePoint(
        for overlayPoint: CGPoint,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGPoint? {
        guard contentCoordinateSize.width > 0,
              contentCoordinateSize.height > 0 else {
            return nil
        }

        let fittedRect = fittedVideoRect(in: containerSize, aspectRatio: videoAspectRatio)
        guard fittedRect.contains(overlayPoint),
              fittedRect.width > 0,
              fittedRect.height > 0 else {
            return nil
        }

        let normalizedX = (overlayPoint.x - fittedRect.minX) / fittedRect.width
        let normalizedY = (overlayPoint.y - fittedRect.minY) / fittedRect.height
        return CGPoint(
            x: min(max(normalizedX, 0), 1) * contentCoordinateSize.width,
            y: min(max(normalizedY, 0), 1) * contentCoordinateSize.height
        )
    }

    func noZoomOverflowRegion(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> NoZoomOverflowRegion? {
        guard let rect = aspectLockedSourceRect(
            from: startPoint,
            to: endPoint,
            contentCoordinateSize: contentCoordinateSize
        ) else {
            return nil
        }

        return NoZoomOverflowRegion(
            centerX: rect.midX / contentCoordinateSize.width,
            centerY: rect.midY / contentCoordinateSize.height,
            width: rect.width / contentCoordinateSize.width,
            height: rect.height / contentCoordinateSize.height
        )
    }

    func effectFocusRegion(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion? {
        guard let rect = freeformSourceRect(
            from: startPoint,
            to: endPoint,
            contentCoordinateSize: contentCoordinateSize
        ) else {
            return nil
        }

        return effectFocusRegion(for: rect, contentCoordinateSize: contentCoordinateSize)
    }

    func aspectLockedSourceRect(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let aspectRatio = contentCoordinateSize.width / contentCoordinateSize.height
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let horizontalLimit = deltaX >= 0 ? contentCoordinateSize.width - startPoint.x : startPoint.x
        let verticalLimit = deltaY >= 0 ? contentCoordinateSize.height - startPoint.y : startPoint.y
        let maxWidth = min(horizontalLimit, verticalLimit * aspectRatio)
        guard maxWidth.isFinite, maxWidth > 1 else {
            return nil
        }

        let desiredWidth = max(abs(deltaX), abs(deltaY) * aspectRatio)
        let width = min(max(desiredWidth, 1), maxWidth)
        let height = width / aspectRatio
        let originX = deltaX >= 0 ? startPoint.x : startPoint.x - width
        let originY = deltaY >= 0 ? startPoint.y : startPoint.y - height

        let rect = CGRect(x: originX, y: originY, width: width, height: height)
        return rect.standardized
    }

    func freeformSourceRect(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentCoordinateSize: CGSize
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let clampedStart = CGPoint(
            x: min(max(startPoint.x, 0), contentCoordinateSize.width),
            y: min(max(startPoint.y, 0), contentCoordinateSize.height)
        )
        let clampedEnd = CGPoint(
            x: min(max(endPoint.x, 0), contentCoordinateSize.width),
            y: min(max(endPoint.y, 0), contentCoordinateSize.height)
        )
        let rect = CGRect(
            x: min(clampedStart.x, clampedEnd.x),
            y: min(clampedStart.y, clampedEnd.y),
            width: abs(clampedEnd.x - clampedStart.x),
            height: abs(clampedEnd.y - clampedStart.y)
        ).standardized
        guard rect.width > 1, rect.height > 1 else {
            return nil
        }
        return rect
    }

    func effectFocusSourceRect(
        for region: EffectFocusRegion,
        contentCoordinateSize: CGSize
    ) -> CGRect {
        CGRect(
            x: (region.centerX - (region.width / 2)) * contentCoordinateSize.width,
            y: (region.centerY - (region.height / 2)) * contentCoordinateSize.height,
            width: region.width * contentCoordinateSize.width,
            height: region.height * contentCoordinateSize.height
        )
    }

    func effectFocusRegion(
        for sourceRect: CGRect,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion {
        EffectFocusRegion(
            centerX: sourceRect.midX / contentCoordinateSize.width,
            centerY: sourceRect.midY / contentCoordinateSize.height,
            width: sourceRect.width / contentCoordinateSize.width,
            height: sourceRect.height / contentCoordinateSize.height
        )
    }

    func overlayRect(
        for region: NoZoomOverflowRegion,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let sourceRect = CGRect(
            x: (region.centerX - (region.width / 2)) * contentCoordinateSize.width,
            y: (region.centerY - (region.height / 2)) * contentCoordinateSize.height,
            width: region.width * contentCoordinateSize.width,
            height: region.height * contentCoordinateSize.height
        )

        guard let topLeft = overlayPoint(
            for: sourceRect.origin,
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ), let bottomRight = overlayPoint(
            for: CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ) else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).standardized
    }

    func overlayRect(
        for region: EffectFocusRegion,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGRect? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let sourceRect = effectFocusSourceRect(for: region, contentCoordinateSize: contentCoordinateSize)

        guard let topLeft = overlayPoint(
            for: sourceRect.origin,
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ), let bottomRight = overlayPoint(
            for: CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ) else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).standardized
    }

    func overflowRegionCornerRadii(
        for overlayRect: CGRect,
        within fittedRect: CGRect,
        baseRadius: CGFloat = 10
    ) -> RectangleCornerRadii {
        let canvasCornerRadius: CGFloat = 18
        let edgeTolerance: CGFloat = 0.5

        let touchesLeft = abs(overlayRect.minX - fittedRect.minX) <= edgeTolerance
        let touchesRight = abs(overlayRect.maxX - fittedRect.maxX) <= edgeTolerance
        let touchesTop = abs(overlayRect.minY - fittedRect.minY) <= edgeTolerance
        let touchesBottom = abs(overlayRect.maxY - fittedRect.maxY) <= edgeTolerance

        return RectangleCornerRadii(
            topLeading: touchesTop && touchesLeft ? canvasCornerRadius : baseRadius,
            bottomLeading: touchesBottom && touchesLeft ? canvasCornerRadius : baseRadius,
            bottomTrailing: touchesBottom && touchesRight ? canvasCornerRadius : baseRadius,
            topTrailing: touchesTop && touchesRight ? canvasCornerRadius : baseRadius
        )
    }

    func nudgedNoZoomOverflowRegion(
        _ region: NoZoomOverflowRegion,
        deltaX: Double,
        deltaY: Double,
        contentCoordinateSize: CGSize
    ) -> NoZoomOverflowRegion? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let normalizedDeltaX = deltaX / contentCoordinateSize.width
        let normalizedDeltaY = deltaY / contentCoordinateSize.height
        let halfWidth = region.width / 2
        let halfHeight = region.height / 2
        let minCenterX = halfWidth
        let maxCenterX = 1 - halfWidth
        let minCenterY = halfHeight
        let maxCenterY = 1 - halfHeight

        return NoZoomOverflowRegion(
            centerX: min(max(region.centerX + normalizedDeltaX, minCenterX), maxCenterX),
            centerY: min(max(region.centerY + normalizedDeltaY, minCenterY), maxCenterY),
            width: region.width,
            height: region.height
        )
    }

    func nudgedEffectFocusRegion(
        _ region: EffectFocusRegion,
        deltaX: Double,
        deltaY: Double,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion? {
        guard contentCoordinateSize.width > 0, contentCoordinateSize.height > 0 else {
            return nil
        }

        let normalizedDeltaX = deltaX / contentCoordinateSize.width
        let normalizedDeltaY = deltaY / contentCoordinateSize.height
        let halfWidth = region.width / 2
        let halfHeight = region.height / 2
        let minCenterX = halfWidth
        let maxCenterX = 1 - halfWidth
        let minCenterY = halfHeight
        let maxCenterY = 1 - halfHeight

        return EffectFocusRegion(
            centerX: min(max(region.centerX + normalizedDeltaX, minCenterX), maxCenterX),
            centerY: min(max(region.centerY + normalizedDeltaY, minCenterY), maxCenterY),
            width: region.width,
            height: region.height
        )
    }

    func movedEffectFocusRegion(
        _ region: EffectFocusRegion,
        deltaX: Double,
        deltaY: Double,
        contentCoordinateSize: CGSize
    ) -> EffectFocusRegion? {
        nudgedEffectFocusRegion(region, deltaX: deltaX, deltaY: deltaY, contentCoordinateSize: contentCoordinateSize)
    }

    func effectRegionHandlePoint(for handle: EffectRegionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topCenter:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topTrailing:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .centerLeading:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .centerTrailing:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeading:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomCenter:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomTrailing:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    func resizedEffectFocusRegion(
        _ region: EffectFocusRegion,
        dragging handle: EffectRegionHandle,
        to overlayPoint: CGPoint,
        contentCoordinateSize: CGSize,
        in containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> EffectFocusRegion? {
        guard let currentPoint = sourcePoint(
            for: overlayPoint,
            contentCoordinateSize: contentCoordinateSize,
            in: containerSize,
            videoAspectRatio: videoAspectRatio
        ) else {
            return nil
        }

        let sourceRect = effectFocusSourceRect(for: region, contentCoordinateSize: contentCoordinateSize)
        let anchorPoint: CGPoint
        let resizedRect: CGRect?
        switch handle {
        case .topLeading:
            anchorPoint = CGPoint(x: sourceRect.maxX, y: sourceRect.maxY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        case .topCenter:
            anchorPoint = CGPoint(x: sourceRect.midX, y: sourceRect.maxY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: sourceRect.minX, y: currentPoint.y),
                to: CGPoint(x: sourceRect.maxX, y: anchorPoint.y),
                contentCoordinateSize: contentCoordinateSize
            )
        case .topTrailing:
            anchorPoint = CGPoint(x: sourceRect.minX, y: sourceRect.maxY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        case .centerLeading:
            anchorPoint = CGPoint(x: sourceRect.maxX, y: sourceRect.midY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: currentPoint.x, y: sourceRect.minY),
                to: CGPoint(x: anchorPoint.x, y: sourceRect.maxY),
                contentCoordinateSize: contentCoordinateSize
            )
        case .centerTrailing:
            anchorPoint = CGPoint(x: sourceRect.minX, y: sourceRect.midY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: anchorPoint.x, y: sourceRect.minY),
                to: CGPoint(x: currentPoint.x, y: sourceRect.maxY),
                contentCoordinateSize: contentCoordinateSize
            )
        case .bottomLeading:
            anchorPoint = CGPoint(x: sourceRect.maxX, y: sourceRect.minY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        case .bottomCenter:
            anchorPoint = CGPoint(x: sourceRect.midX, y: sourceRect.minY)
            resizedRect = freeformSourceRect(
                from: CGPoint(x: sourceRect.minX, y: anchorPoint.y),
                to: CGPoint(x: sourceRect.maxX, y: currentPoint.y),
                contentCoordinateSize: contentCoordinateSize
            )
        case .bottomTrailing:
            anchorPoint = CGPoint(x: sourceRect.minX, y: sourceRect.minY)
            resizedRect = freeformSourceRect(
                from: anchorPoint,
                to: currentPoint,
                contentCoordinateSize: contentCoordinateSize
            )
        }

        guard let resizedRect else {
            return nil
        }

        return effectFocusRegion(for: resizedRect, contentCoordinateSize: contentCoordinateSize)
    }

    func fittedVideoRect(in containerSize: CGSize, aspectRatio: CGFloat) -> CGRect {
        let safeAspectRatio = max(aspectRatio, 0.1)
        let containerAspectRatio = containerSize.width / max(containerSize.height, 1)

        if containerAspectRatio > safeAspectRatio {
            let height = containerSize.height
            let width = height * safeAspectRatio
            let originX = (containerSize.width - width) / 2
            return CGRect(x: originX, y: 0, width: width, height: height)
        } else {
            let width = containerSize.width
            let height = width / safeAspectRatio
            let originY = (containerSize.height - height) / 2
            return CGRect(x: 0, y: originY, width: width, height: height)
        }
    }

    func effectRegionPrecisionLoupe(
        player: AVPlayer,
        fittedRect: CGRect,
        focusPoint: CGPoint
    ) -> some View {
        let loupeSize = CGSize(width: 190, height: 132)
        let loupeScale: CGFloat = 2.8
        let clampedX = min(max(focusPoint.x, fittedRect.minX), fittedRect.maxX)
        let clampedY = min(max(focusPoint.y, fittedRect.minY), fittedRect.maxY)
        let localX = clampedX - fittedRect.minX
        let localY = clampedY - fittedRect.minY

        return VStack(alignment: .leading, spacing: 6) {
            Text("Precision")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            PlaybackVideoLayerSurface(player: player)
                .frame(width: fittedRect.width, height: fittedRect.height)
                .scaleEffect(loupeScale, anchor: .topLeading)
                .offset(
                    x: (-localX * loupeScale) + (loupeSize.width / 2),
                    y: (-localY * loupeScale) + (loupeSize.height / 2)
                )
                .frame(width: loupeSize.width, height: loupeSize.height, alignment: .topLeading)
                .clipped()
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1, height: loupeSize.height)
                }
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: loupeSize.width, height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.orange, lineWidth: 2)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.64))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    func transformedOverlayPoint(
        _ point: CGPoint,
        in fittedRect: CGRect,
        previewState: ZoomPreviewState?
    ) -> CGPoint {
        guard let previewState else { return point }
        let localX = point.x - fittedRect.minX
        let localY = point.y - fittedRect.minY
        let offset = zoomPreviewOffset(for: previewState, in: fittedRect)
        return CGPoint(
            x: fittedRect.minX + (localX * previewState.scale) + offset.width,
            y: fittedRect.minY + (localY * previewState.scale) + offset.height
        )
    }
}
