import CoreImage
import CoreVideo
import OSLog

/// Draws one frame through a colour table into a pooled buffer of the frame's own format: the baked Log profile.
///
/// Used on the video data output's queue only; the object is not `Sendable`. The pass is `LookRenderer.applyTable` in HLG, run on
/// `LookRenderer.shared`'s one `CIContext`, rendered into a `CIRenderDestination` and waited for, so a frame is finished before the
/// next one is looked at and nothing queues behind it. HLG is only the carrier on both sides: the frame is read as HLG and written
/// as HLG, so the values in the file are the table's own output, with no gamut or transfer conversion in between.
///
/// The output is tagged BT.2020 primaries with the Rec. 709 transfer function, so a player does not take the flat picture for HDR.
/// Every step that can fail gives nil and is logged once per object (a render that fails at 60 fps would otherwise fill the log).
nonisolated final class RecordingRender {
    /// The only format the render writes: 10-bit 4:2:0, the camera's HLG format.
    static let pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    /// Buffers the pool keeps ready.
    private static let minimumBuffers = 3
    /// Buffers that may be out at once. The writer's HEVC encoder (Log with HEVC) may reorder frames and hold six or more, so a
    /// lower number would fail every frame past it; ProRes holds few. About 25 MB a buffer at 4K. A request past it fails instead
    /// of growing memory when the writer stalls, and `admitVideo`'s readiness check already refuses frames for a stalled writer.
    private static let allocationThreshold = 12

    private static let logger = Logger(subsystem: "local.opencam.app", category: "RecordingRender")

    private struct Shape: Equatable {
        let width: Int
        let height: Int
        let format: OSType
    }

    private let cube: ColourCube
    private let renderer: LookRenderer
    private var pool: CVPixelBufferPool?
    private var poolShape: Shape?
    private var loggedStages: Set<String> = []

    init(cube: ColourCube, renderer: LookRenderer = .shared) {
        self.cube = cube
        self.renderer = renderer
    }

    /// Makes the pool for frames of this size ahead of the first frame, so a clip that cannot be rendered fails when it starts.
    /// False when the colour space or the pool is unavailable.
    func prepare(width: Int, height: Int) -> Bool {
        guard hasHLGSpace else { return false }
        return makePool(Shape(width: width, height: height, format: Self.pixelFormat)) != nil
    }

    /// A new buffer in the source's format holding the frame through the table; nil when the pool, the buffer or the render failed.
    func render(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        guard hasHLGSpace else { return nil }
        let shape = Shape(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source), format: CVPixelBufferGetPixelFormatType(source))
        guard shape.format == Self.pixelFormat else {
            note("format", "The frame is not 10-bit 4:2:0 — {format: \(shape.format)}")
            return nil
        }
        guard let pool = poolShape == shape ? pool : makePool(shape) else { return nil }
        // A threshold, so a writer that is slow to give buffers back shows as nil here instead of growing memory.
        let auxiliary = [kCVPixelBufferPoolAllocationThresholdKey as String: Self.allocationThreshold] as CFDictionary
        var destination: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, auxiliary, &destination)
        guard status == kCVReturnSuccess, let destination else {
            note("buffer", "The pool gave no buffer — {status: \(status), size: \(shape.width)x\(shape.height)}")
            return nil
        }
        CVBufferSetAttachment(destination, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
        let image = renderer.applyTable(CIImage(cvPixelBuffer: source, options: [.colorSpace: renderer.hlg]), cube: cube, in: renderer.hlg)
        let target = CIRenderDestination(pixelBuffer: destination)
        target.colorSpace = renderer.hlg
        do {
            _ = try renderer.context.startTask(toRender: image, to: target).waitUntilCompleted()
        } catch {
            note("render", "The render failed — {error: \(error.localizedDescription), size: \(shape.width)x\(shape.height)}")
            return nil
        }
        CVBufferSetAttachment(destination, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(destination, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        return destination
    }

    /// The renderer falls back to a device colour space when the system has no HLG one; the table would then be read in the wrong
    /// space, so the render refuses.
    private var hasHLGSpace: Bool {
        guard (renderer.hlg.name as String?) == (CGColorSpace.itur_2100_HLG as String) else {
            note("colour space", "HLG is not available as a colour space — {name: \(String(describing: renderer.hlg.name))}")
            return false
        }
        return true
    }

    private func makePool(_ shape: Shape) -> CVPixelBufferPool? {
        pool = nil
        poolShape = nil
        guard shape.width > 0, shape.height > 0 else {
            note("pool", "The frame has no size — {size: \(shape.width)x\(shape.height)}")
            return nil
        }
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: Self.minimumBuffers] as CFDictionary
        let bufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: shape.format,
            kCVPixelBufferWidthKey as String: shape.width,
            kCVPixelBufferHeightKey as String: shape.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ] as CFDictionary
        var made: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, poolAttributes, bufferAttributes, &made)
        guard status == kCVReturnSuccess, let made else {
            note("pool", "The pool could not be made — {status: \(status), size: \(shape.width)x\(shape.height)}")
            return nil
        }
        pool = made
        poolShape = shape
        return made
    }

    private func note(_ stage: String, _ text: String) {
        guard loggedStages.insert(stage).inserted else { return }
        Self.logger.error("[RecordingRender:\(stage, privacy: .public)] \(text, privacy: .public)")
    }
}
