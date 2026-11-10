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
        /// The view that last set the look; only it can clear it.
        var owner: UUID?
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

    /// The look to draw, set by the view `owner`, which becomes the only one that can clear it.
    func setLook(_ adjustments: Adjustments, owner: UUID) {
        state.withLock { state in
            state.owner = owner
            state.adjustments = adjustments
        }
    }

    /// A changed look from the view that set it; nothing from a view another one has replaced as owner.
    func changeLook(_ adjustments: Adjustments, owner: UUID) {
        state.withLock { state in
            guard state.owner == owner else { return }
            state.adjustments = adjustments
        }
    }

    /// Stops keeping frames and empties the slot, unless another view has set the look since `owner` did: a view swapped out
    /// by a layout change is taken down after its replacement was made, and must not switch the replacement's look off.
    func clearLook(owner: UUID) {
        state.withLock { state in
            guard state.owner == owner else { return }
            state.owner = nil
            state.adjustments = nil
            state.slot.empty()
        }
    }

    /// The look frames are drawn with now; nil when none.
    var look: Adjustments? {
        state.withLock { $0.adjustments }
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
        state.withLock { $0.deliveredCount += 1 }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        receive(CIImage(cvPixelBuffer: pixelBuffer))
    }

    /// One camera frame, already a `CIImage`: turned upright, drawn through the look and put in the slot. Nothing is kept
    /// without a look. Internal so tests can deliver a picture without a sample buffer.
    func receive(_ frame: CIImage) {
        let (adjustments, orientation) = state.withLock { ($0.adjustments, $0.orientation) }
        guard let adjustments else { return }
        let image = orientation.apply(to: frame)
        let looked = renderer.renderColourAndVignette(image, cube: cubes.cube(for: adjustments), vignette: adjustments.vignette)
        state.withLock { state in
            // The look changed or was turned off while this frame was rendered; it must not land after that.
            guard state.adjustments == adjustments else { return }
            state.slot.put(looked)
        }
    }
}
