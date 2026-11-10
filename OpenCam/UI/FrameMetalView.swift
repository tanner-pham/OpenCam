import CoreImage
import MetalKit
import OSLog

/// Draws the newest looked frame, aspect-fit over black, through the shared renderer's context. Display P3, 8 bits per
/// channel, the same depth as the editor's proxy preview. A draw with no new frame leaves the last one on screen.
final class FrameMetalView: MTKView {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "FrameMetalView")

    let frames: FramePipeline
    private let onFirstFrame: () -> Void
    private let commandQueue: (any MTLCommandQueue)?
    private var hasDrawn = false

    init(frames: FramePipeline, onFirstFrame: @escaping () -> Void) {
        self.frames = frames
        self.onFirstFrame = onFirstFrame
        let device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        super.init(frame: .zero, device: device)
        // Core Image writes into the drawable's texture, so it must not be framebuffer-only.
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        (layer as? CAMetalLayer)?.colorspace = LookRenderer.shared.displayP3
        backgroundColor = .black
        isOpaque = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("[FrameMetalView:init] Not used from a storyboard — {coder: \(type(of: coder))}")
    }

    override func draw(_ rect: CGRect) {
        // Without a Metal device nothing can draw, so the frame is left in the slot rather than thrown away.
        guard let commandQueue else { return }
        guard let image = frames.takeLatest() else { return }
        guard let drawable = currentDrawable, let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let renderer = LookRenderer.shared
        let bounds = CGRect(origin: .zero, size: drawableSize)
        let fitted = image.transformed(by: FrameFit.aspectFit(image.extent, in: drawableSize))
        let picture = fitted.composited(over: CIImage.black.cropped(to: bounds))
        let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commandBuffer)
        destination.colorSpace = renderer.displayP3
        // Core Image's origin is the lower left; a Metal texture's first row is its top (CIRenderDestination.h, `flipped`).
        destination.isFlipped = true
        do {
            try renderer.context.startTask(toRender: picture, from: bounds, to: destination, at: .zero)
        } catch {
            Self.logger.error("[FrameMetalView:draw] Frame not drawn — {size: \(Int(bounds.width)) x \(Int(bounds.height)), error: \(String(describing: error), privacy: .public)}")
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        guard !hasDrawn else { return }
        hasDrawn = true
        onFirstFrame()
    }
}
