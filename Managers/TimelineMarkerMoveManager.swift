import Foundation

struct TimelineMarkerMoveBeginPlan {
    let shouldResetPreviewPresentation: Bool
    let shouldStopPreviewPlayback: Bool
    let stopPreviewSeekTime: Double
    let retainSlate: Bool
    let shouldCancelPreviewMode: Bool
    let wasPlayingBeforeMarkerTimelineMove: Bool
    let shouldPause: Bool
    let shouldSetPlaybackInactive: Bool
    let selectedZoomMarkerID: String
    let suppressionInterval: TimeInterval
}

struct TimelineMarkerMovePreviewPlan {
    let markerID: String
    let targetTime: Double
    let shouldPersist: Bool
    let shouldSeekPlaybackHead: Bool
}

struct TimelineMarkerMoveCommitPlan {
    let markerID: String
    let targetTime: Double
    let shouldPersist: Bool
    let shouldSeekPlaybackHead: Bool
    let suppressionInterval: TimeInterval
    let shouldResumePlayback: Bool
    let nextWasPlayingBeforeMarkerTimelineMove: Bool
}

struct TimelineMarkerMoveManager {
    func beginMovePlan(
        canEditClickFocusMarkers: Bool,
        hasMainPlayer: Bool,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        currentPlaybackTime: Double,
        markerID: String,
        isMainPlayerPlaying: Bool
    ) -> TimelineMarkerMoveBeginPlan? {
        guard canEditClickFocusMarkers, hasMainPlayer else {
            return nil
        }

        return TimelineMarkerMoveBeginPlan(
            shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
            shouldStopPreviewPlayback: true,
            stopPreviewSeekTime: currentPlaybackTime,
            retainSlate: false,
            shouldCancelPreviewMode: true,
            wasPlayingBeforeMarkerTimelineMove: isMainPlayerPlaying,
            shouldPause: true,
            shouldSetPlaybackInactive: true,
            selectedZoomMarkerID: markerID,
            suppressionInterval: 0.5
        )
    }

    func previewMovePlan(markerID: String, targetTime: Double) -> TimelineMarkerMovePreviewPlan {
        TimelineMarkerMovePreviewPlan(
            markerID: markerID,
            targetTime: targetTime,
            shouldPersist: false,
            shouldSeekPlaybackHead: false
        )
    }

    func commitMovePlan(
        markerID: String,
        targetTime: Double,
        wasPlayingBeforeMarkerTimelineMove: Bool
    ) -> TimelineMarkerMoveCommitPlan {
        let _ = wasPlayingBeforeMarkerTimelineMove
        return TimelineMarkerMoveCommitPlan(
            markerID: markerID,
            targetTime: targetTime,
            shouldPersist: true,
            shouldSeekPlaybackHead: true,
            suppressionInterval: 0.2,
            shouldResumePlayback: false,
            nextWasPlayingBeforeMarkerTimelineMove: false
        )
    }
}
