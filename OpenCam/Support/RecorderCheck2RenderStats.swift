/// The colour table pass of one trial. Times are milliseconds from before the pixel buffer is wrapped until Core Image reports
/// the render finished (`CIRenderTask.waitUntilCompleted`).
nonisolated struct RecorderCheck2RenderStats: Codable, Sendable {
    var framesRendered = 0
    var meanMilliseconds: Double?
    var p95Milliseconds: Double?
    var worstMilliseconds: Double?
    var poolAllocationFailures = 0
    var renderErrors = 0
    /// Frames not rendered because the capture was already more than one frame behind real time.
    var framesDroppedRenderBusy = 0
    var cubeDimension = 0
    var note = ""
}
