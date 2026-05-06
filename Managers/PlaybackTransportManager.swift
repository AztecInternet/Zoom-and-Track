import Foundation

struct PlaybackTransportPlan {
    enum PlayerCommand {
        case play
        case pause
    }

    let shouldResetPreviewPresentation: Bool
    let shouldStopPreviewPlayback: Bool
    let stopPreviewSeekTime: Double
    let retainSlate: Bool
    let shouldCancelPreviewMode: Bool
    let seekTime: Double?
    let playerCommand: PlayerCommand?
}

struct PlaybackTransportManager {
    func togglePlan(
        canUsePlaybackTransport: Bool,
        isRenderedPreviewActive: Bool,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        isMainPlayerPlaying: Bool,
        currentPlaybackTime: Double
    ) -> PlaybackTransportPlan? {
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return nil
        }

        if isRenderedPreviewActive {
            return PlaybackTransportPlan(
                shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
                shouldStopPreviewPlayback: true,
                stopPreviewSeekTime: currentPlaybackTime,
                retainSlate: false,
                shouldCancelPreviewMode: true,
                seekTime: nil,
                playerCommand: .play
            )
        }

        return PlaybackTransportPlan(
            shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
            shouldStopPreviewPlayback: false,
            stopPreviewSeekTime: currentPlaybackTime,
            retainSlate: false,
            shouldCancelPreviewMode: true,
            seekTime: nil,
            playerCommand: isMainPlayerPlaying ? .pause : .play
        )
    }

    func interactiveSeekPlan(
        canUsePlaybackTransport: Bool,
        isRenderedPreviewActive: Bool,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        currentPlaybackTime: Double,
        targetTime: Double
    ) -> PlaybackTransportPlan? {
        guard canUsePlaybackTransport || isRenderedPreviewActive || playbackPresentationMode == .previewCompletedSlate else {
            return nil
        }

        return PlaybackTransportPlan(
            shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
            shouldStopPreviewPlayback: true,
            stopPreviewSeekTime: currentPlaybackTime,
            retainSlate: false,
            shouldCancelPreviewMode: true,
            seekTime: targetTime,
            playerCommand: nil
        )
    }

    func jumpToStartPlan(
        canUsePlaybackTransport: Bool,
        isRenderedPreviewActive: Bool,
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        currentPlaybackTime: Double
    ) -> PlaybackTransportPlan? {
        interactiveSeekPlan(
            canUsePlaybackTransport: canUsePlaybackTransport,
            isRenderedPreviewActive: isRenderedPreviewActive,
            playbackPresentationMode: playbackPresentationMode,
            currentPlaybackTime: currentPlaybackTime,
            targetTime: 0
        )
    }

    func cancelPreviewPlan(
        playbackPresentationMode: CaptureSetupViewModel.PlaybackPresentationMode,
        currentPlaybackTime: Double
    ) -> PlaybackTransportPlan {
        PlaybackTransportPlan(
            shouldResetPreviewPresentation: playbackPresentationMode == .previewCompletedSlate || playbackPresentationMode == .renderingPreview,
            shouldStopPreviewPlayback: true,
            stopPreviewSeekTime: currentPlaybackTime,
            retainSlate: false,
            shouldCancelPreviewMode: true,
            seekTime: nil,
            playerCommand: nil
        )
    }
}
