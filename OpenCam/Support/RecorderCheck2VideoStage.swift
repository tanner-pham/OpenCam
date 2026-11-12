import AVFoundation
import CoreImage

/// The video side of one trial that belongs to the video queue: luma samples, the "more than one frame behind" test, and the
/// colour table pass. Every method is called on the video data output's queue (and the readers through `queue.sync`).
///
/// The pass uses the app's own `LookRenderer`: its shared `CIContext` and `applyCube` with a 33-point table compiled by
/// `LookCompiler` from a mild contrast adjustment. `LookRenderer` cannot render to a pixel buffer itself (it only makes
/// `CIImage`s and `CGImage`s), so the image is rendered with `LookRenderer.shared.context.startTask(toRender:to:)` into a buffer
/// from a pool, and the call waits until the render has finished so the time measured is the real one.
nonisolated final class RecorderCheck2VideoStage {
    let usesColourPass: Bool
    private let frameDuration: Double
    private let cube: ColourCube
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)

    private var pool: CVPixelBufferPool?
    private var renderMilliseconds: [Double] = []
    private var stats = RecorderCheck2RenderStats()
    private var firstClock: ContinuousClock.Instant?
    private var firstPTS: Double?
    private(set) var meanLumaFirstFrame: Double?
    private(set) var meanLumaLastFrame: Double?

    init(usesColourPass: Bool, framesPerSecond: Int) {
        self.usesColourPass = usesColourPass
        frameDuration = 1 / Double(framesPerSecond)
        var adjustments = Adjustments()
        adjustments[.contrast] = 25
        cube = LookCompiler.cube(for: adjustments)
        stats.cubeDimension = cube.dimension
    }

    func noteLuma(of buffer: CVPixelBuffer) {
        guard let luma = RecorderCheck2Luma.mean(of: buffer) else { return }
        if meanLumaFirstFrame == nil { meanLumaFirstFrame = luma }
        meanLumaLastFrame = luma
    }

    /// True when the capture is more than one frame behind real time: the wall clock since the first frame has run ahead of the
    /// frames' presentation times by more than a frame. Such a frame is dropped and counted, so the backlog never grows.
    func isBehind(presentationTime: CMTime) -> Bool {
        let now = ContinuousClock.now
        guard let firstClock, let firstPTS else {
            firstClock = now
            firstPTS = presentationTime.seconds
            return false
        }
        let lag = (now - firstClock).recorderCheckMilliseconds / 1000 - (presentationTime.seconds - firstPTS)
        if lag > frameDuration {
            stats.framesDroppedRenderBusy += 1
            return true
        }
        return false
    }

    /// A new buffer in the source's format holding the frame through the colour table, with the source's colour tags; nil when
    /// the pool or the render failed (counted).
    func render(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        if pool == nil { pool = Self.makePool(like: source) }
        guard let pool else {
            stats.poolAllocationFailures += 1
            return nil
        }
        // A threshold, so a writer that is slow to give buffers back shows as failures here instead of growing memory.
        let aux: [String: Any] = [kCVPixelBufferPoolAllocationThresholdKey as String: 6]
        var destination: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, aux as CFDictionary, &destination)
        guard status == kCVReturnSuccess, let destination else {
            stats.poolAllocationFailures += 1
            return nil
        }
        let started = ContinuousClock.now
        let renderer = LookRenderer.shared
        let image = renderer.applyCube(CIImage(cvPixelBuffer: source), cube: cube)
        let target = CIRenderDestination(pixelBuffer: destination)
        target.colorSpace = colorSpace
        do {
            _ = try renderer.context.startTask(toRender: image, to: target).waitUntilCompleted()
        } catch {
            stats.renderErrors += 1
            return nil
        }
        renderMilliseconds.append((ContinuousClock.now - started).recorderCheckMilliseconds)
        if let tags = CVBufferCopyAttachments(source, .shouldPropagate) {
            CVBufferSetAttachments(destination, tags, .shouldPropagate)
        }
        return destination
    }

    func renderStats() -> RecorderCheck2RenderStats {
        var result = stats
        result.framesRendered = renderMilliseconds.count
        if !renderMilliseconds.isEmpty {
            let sorted = renderMilliseconds.sorted()
            result.meanMilliseconds = renderMilliseconds.reduce(0, +) / Double(renderMilliseconds.count)
            result.p95Milliseconds = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
            result.worstMilliseconds = sorted.last
        }
        result.note = "Render time covers the colour table lookup into a new pixel buffer, waited to completion; it excludes the append."
        return result
    }

    private static func makePool(like source: CVPixelBuffer) -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: CVPixelBufferGetPixelFormatType(source),
            kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(source),
            kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(source),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pool) == kCVReturnSuccess else { return nil }
        return pool
    }
}
