//
//  MediaWriterService.swift
//  Zoom and Track
//

import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class MediaWriterService {
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var didStartSession = false
    private(set) var didWriteFrame = false
    var onSessionStart: ((CMTime, TimeInterval) -> Void)?

    func startWriting(to url: URL, width: Int, height: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "MediaWriterService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to configure video writer input."])
        }

        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "MediaWriterService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to start movie writer."])
        }

        self.writer = writer
        self.writerInput = writerInput
        self.adaptor = adaptor
        didStartSession = false
        didWriteFrame = false
    }

    func append(sampleBuffer: CMSampleBuffer) throws {
        guard sampleBuffer.isValid else { return }
        guard let writer, let writerInput, let adaptor else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        guard isCompleteFrame(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !didStartSession {
            writer.startSession(atSourceTime: presentationTime)
            didStartSession = true
            onSessionStart?(presentationTime, ProcessInfo.processInfo.systemUptime)
        }

        guard writerInput.isReadyForMoreMediaData else { return }

        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw writer.error ?? NSError(domain: "MediaWriterService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to append video frame."])
        }

        didWriteFrame = true
    }

    func finishWriting() async throws {
        guard let writer, let writerInput else { return }
        writerInput.markAsFinished()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func cancelWriting() {
        writerInput?.markAsFinished()
        writer?.cancelWriting()
        writer = nil
        writerInput = nil
        adaptor = nil
        didStartSession = false
        didWriteFrame = false
        onSessionStart = nil
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue) else {
            return false
        }

        return status == .complete
    }
}
