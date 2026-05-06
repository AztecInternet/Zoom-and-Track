import Foundation

struct TimelineScrubBeginPlan {
    let shouldResetPreviewPresentation: Bool
    let shouldStopPreviewPlayback: Bool
    let stopPreviewSeekTime: Double
    let retainSlate: Bool
    let shouldCancelPreviewMode: Bool
    let wasPlayingBeforeTimelineScrub: Bool
    let shouldPause: Bool
    let shouldSetPlaybackInactive: Bool
    let isTimelineScrubbing: Bool
    let suppressionInterval: TimeInterval
}

struct TimelineScrubUpdatePlan {
    let selectedZoomMarkerID: String?
    let selectedEffectMarkerID: String?
    let targetTime: Double
}

struct TimelineScrubEndPlan {
    let selectedZoomMarkerID: String?
    let selectedEffectMarkerID: String?
    let targetTime: Double
    let isTimelineScrubbing: Bool
    let suppressionInterval: TimeInterval
    let shouldResumePlayback: Bool
}

struct TimelineDirectSeekPlan {
    let shouldResetPreviewPresentation: Bool
    let shouldStopPreviewPlayback: Bool
    let stopPreviewSeekTime: Double
    let retainSlate: Bool
    let shouldCancelPreviewMode: Bool
    let selectedZoomMarkerID: String?
    let selectedEffectMarkerID: String?
    let suppressionInterval: TimeInterval?
    let targetTime: Double
}

struct TimelineScrubManager {
    func beginScrubPlan(
        canUsePlaybackTransport: Bool,
        hasMainPlayer: Bool,
        isTimelineScrubbing: Bool,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        currentPlaybackTime: Double,
        isMainPlayerPlaying: Bool
    ) -> TimelineScrubBeginPlan? {
        guard canUsePlaybackTransport, hasMainPlayer, !isTimelineScrubbing else {
            return nil
        }

        return TimelineScrubBeginPlan(
            shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
            shouldStopPreviewPlayback: true,
            stopPreviewSeekTime: currentPlaybackTime,
            retainSlate: false,
            shouldCancelPreviewMode: true,
            wasPlayingBeforeTimelineScrub: isMainPlayerPlaying,
            shouldPause: true,
            shouldSetPlaybackInactive: true,
            isTimelineScrubbing: true,
            suppressionInterval: 0.5
        )
    }

    func updateScrubPlan(
        isTimelineScrubbing: Bool,
        targetTime: Double,
        snappedMarkerID: String?,
        snappedEffectMarkerID: String?
    ) -> TimelineScrubUpdatePlan? {
        guard isTimelineScrubbing else {
            return nil
        }

        return TimelineScrubUpdatePlan(
            selectedZoomMarkerID: snappedMarkerID,
            selectedEffectMarkerID: snappedEffectMarkerID,
            targetTime: targetTime
        )
    }

    func endScrubPlan(
        isTimelineScrubbing: Bool,
        targetTime: Double,
        snappedMarkerID: String?,
        snappedEffectMarkerID: String?,
        wasPlayingBeforeTimelineScrub: Bool
    ) -> TimelineScrubEndPlan? {
        guard isTimelineScrubbing else {
            return nil
        }

        return TimelineScrubEndPlan(
            selectedZoomMarkerID: snappedMarkerID,
            selectedEffectMarkerID: snappedEffectMarkerID,
            targetTime: targetTime,
            isTimelineScrubbing: false,
            suppressionInterval: 0.2,
            shouldResumePlayback: wasPlayingBeforeTimelineScrub
        )
    }

    func directSeekPlan(
        canUsePlaybackTransport: Bool,
        isRenderedPreviewActive: Bool,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        currentPlaybackTime: Double,
        targetTime: Double,
        snappedMarkerID: String?,
        snappedEffectMarkerID: String?
    ) -> TimelineDirectSeekPlan? {
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return nil
        }

        let suppressionInterval: TimeInterval? =
            snappedMarkerID != nil || snappedEffectMarkerID != nil ? 0.35 : nil

        return TimelineDirectSeekPlan(
            shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
            shouldStopPreviewPlayback: true,
            stopPreviewSeekTime: currentPlaybackTime,
            retainSlate: false,
            shouldCancelPreviewMode: true,
            selectedZoomMarkerID: snappedMarkerID,
            selectedEffectMarkerID: snappedEffectMarkerID,
            suppressionInterval: suppressionInterval,
            targetTime: targetTime
        )
    }
}
