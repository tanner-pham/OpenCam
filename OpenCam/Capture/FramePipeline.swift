import AVFoundation
import CoreImage
import Synchronization

/// Turns the data output's frames into the selected look for the viewfinder, on its own serial queue. Each frame becomes a
/// `CIImage` inside the callback, is turned upright, goes through the shared renderer's colour table and vignette, and
/// replaces any frame not yet drawn. Without a look nothing is kept. The colour table comes from a cache of its own, so the
/// editor's one-entry cache is never pushed out by the viewfinder.
nonisolated final class FramePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    private struct State {
        var adjustments: Adjustments?
        var angle: CGFloat = 0
        var isFront = false
        var slot = FrameSlot<CIImage>()
        var deliveredCount = 0

        var orientation: FrameOrientation {
            FrameOrientation.plan(angle: angle, isFront: isFront)
        }
    }

    let queue = DispatchSerialQueue(label: "opencam.frames")
    private let renderer: LookRenderer
    private let cubes = ColourCubeCache()
    private let state = Mutex(State())

    init(renderer: LookRenderer = .shared) {
        self.renderer = renderer
    }

    /// The look to draw; nil stops keeping frames and empties the slot.
    func setLook(_ adjustments: Adjustments?) {
        state.withLock { state in
            guard state.adjustments != adjustments else { return }
            state.adjustments = adjustments
            if adjustments == nil { state.slot.empty() }
        }
    }

    /// The preview's horizon-level angle, from `PreviewUIView`'s rotation coordinator.
    func setAngle(_ angle: CGFloat) {
        state.withLock { $0.angle = angle }
    }

    /// Whether the camera now attached faces the user; from `CameraSession.apply`.
    func setCamera(isFront: Bool) {
        state.withLock { $0.isFront = isFront }
    }

    /// The newest drawn-ready frame, once.
    func takeLatest() -> CIImage? {
        state.withLock { $0.slot.take() }
    }

    /// Every frame the output has delivered, with or without a look.
    var deliveredCount: Int {
        state.withLock { $0.deliveredCount }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let (adjustments, orientation) = state.withLock { state in
            state.deliveredCount += 1
            return (state.adjustments, state.orientation)
        }
        guard let adjustments, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = orientation.apply(to: CIImage(cvPixelBuffer: pixelBuffer))
        let looked = renderer.renderColourAndVignette(image, cube: cubes.cube(for: adjustments), vignette: adjustments.vignette)
        state.withLock { state in
            // The look changed or was turned off while this frame was rendered; it must not land after that.
            guard state.adjustments == adjustments else { return }
            state.slot.put(looked)
        }
    }
}
