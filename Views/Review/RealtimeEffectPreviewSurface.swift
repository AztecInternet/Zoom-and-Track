import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

struct RealtimeEffectPreviewSurface: NSViewRepresentable {
    let player: AVPlayer
    let summary: RecordingInspectionSummary
    let selectedEffectMarker: EffectPlanItem
    let currentPlaybackTime: Double
    let logicalVideoSize: CGSize
    let isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(
            view: nsView,
            player: player,
            summary: summary,
            selectedEffectMarker: selectedEffectMarker,
            currentPlaybackTime: currentPlaybackTime,
            logicalVideoSize: logicalVideoSize,
            isVisible: isVisible
        )
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let renderService = MarkerPreviewRenderService()
        private let device = MTLCreateSystemDefaultDevice()
        private lazy var commandQueue = device?.makeCommandQueue()
        private lazy var ciContext: CIContext? = {
            guard let device else { return nil }
            return CIContext(mtlDevice: device)
        }()
        private let colorSpace = CGColorSpaceCreateDeviceRGB()
        private let videoOutput = AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        private weak var view: MTKView?
        private weak var player: AVPlayer?
        private weak var attachedItem: AVPlayerItem?
        private var summary: RecordingInspectionSummary?
        private var selectedEffectMarker: EffectPlanItem?
        private var currentPlaybackTime: Double = 0
        private var logicalVideoSize: CGSize = .zero
        private var isVisible = false
        private var preferredTransform: CGAffineTransform = .identity
        private var orientedVideoSize: CGSize = .zero
        private var metadataTask: Task<Void, Never>?

        func makeView() -> MTKView {
            let view = MTKView(frame: .zero, device: device)
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.framebufferOnly = false
            view.autoResizeDrawable = true
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            view.colorPixelFormat = .bgra8Unorm
            view.delegate = self
            self.view = view
            return view
        }

        func update(
            view: MTKView,
            player: AVPlayer,
            summary: RecordingInspectionSummary,
            selectedEffectMarker: EffectPlanItem,
            currentPlaybackTime: Double,
            logicalVideoSize: CGSize,
            isVisible: Bool
        ) {
            self.view = view
            self.player = player
            self.summary = summary
            self.selectedEffectMarker = selectedEffectMarker
            self.currentPlaybackTime = currentPlaybackTime
            self.logicalVideoSize = logicalVideoSize
            self.isVisible = isVisible
            view.isHidden = !isVisible

            attachVideoOutputIfNeeded(to: player.currentItem)
            if orientedVideoSize == .zero {
                loadVideoMetadata(from: summary.recordingURL)
            }

            if isVisible {
                view.setNeedsDisplay(view.bounds)
            }
        }

        func detach() {
            metadataTask?.cancel()
            metadataTask = nil
            if let attachedItem {
                attachedItem.remove(videoOutput)
            }
            attachedItem = nil
            player = nil
            summary = nil
            selectedEffectMarker = nil
        }

        func draw(in view: MTKView) {
            guard isVisible,
                  let summary,
                  let selectedEffectMarker,
                  selectedEffectMarker.style == .distortion,
                  let drawable = view.currentDrawable,
                  let commandQueue,
                  let ciContext,
                  orientedVideoSize.width > 0,
                  orientedVideoSize.height > 0,
                  logicalVideoSize.width > 0,
                  logicalVideoSize.height > 0 else {
                clear(view)
                return
            }

            let targetTime = CMTime(seconds: max(currentPlaybackTime, 0), preferredTimescale: 600)
            var displayTime = targetTime
            guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: targetTime, itemTimeForDisplay: &displayTime)
                    ?? videoOutput.copyPixelBuffer(forItemTime: player?.currentItem?.currentTime() ?? targetTime, itemTimeForDisplay: nil) else {
                clear(view)
                return
            }

            let drawableSize = CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
            let compositionSize = logicalVideoSize
            guard drawableSize.width > 0, drawableSize.height > 0 else {
                clear(view)
                return
            }

            guard let outputImage = renderService.makeRealtimeEffectPreviewImage(
                pixelBuffer: pixelBuffer,
                at: currentPlaybackTime,
                summary: summary,
                effectMarkers: [selectedEffectMarker],
                outputSize: compositionSize,
                preferredTransform: preferredTransform,
                orientedVideoSize: orientedVideoSize
            ) else {
                clear(view)
                return
            }

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                clear(view)
                return
            }

            let scaleX = drawableSize.width / compositionSize.width
            let scaleY = drawableSize.height / compositionSize.height
            let drawableImage = outputImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: CGRect(origin: .zero, size: drawableSize))
            let bounds = CGRect(origin: .zero, size: drawableSize)
            ciContext.render(
                drawableImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: bounds,
                colorSpace: colorSpace
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            guard isVisible else { return }
            view.setNeedsDisplay(view.bounds)
        }

        private func attachVideoOutputIfNeeded(to item: AVPlayerItem?) {
            guard let item else { return }
            guard attachedItem !== item else { return }

            if let attachedItem {
                attachedItem.remove(videoOutput)
            }
            item.add(videoOutput)
            attachedItem = item
        }

        private func loadVideoMetadata(from recordingURL: URL) {
            guard metadataTask == nil else { return }
            metadataTask = Task { [weak self] in
                defer { self?.metadataTask = nil }
                let asset = AVURLAsset(url: recordingURL)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let naturalSize = try? await track.load(.naturalSize),
                      let preferredTransform = try? await track.load(.preferredTransform) else {
                    return
                }

                let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
                let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
                await MainActor.run { [weak self] in
                    self?.preferredTransform = preferredTransform
                    self?.orientedVideoSize = orientedSize
                    if let view = self?.view, self?.isVisible == true {
                        view.setNeedsDisplay(view.bounds)
                    }
                }
            }
        }

        private func clear(_ view: MTKView) {
            guard let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
