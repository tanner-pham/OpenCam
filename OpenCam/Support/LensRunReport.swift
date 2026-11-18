import Foundation

/// What the scripted lens run saw. Written to `Documents/lens-run.json` before and after every step, so after a crash
/// `breadcrumb` names the step that never finished.
nonisolated struct LensRunReport: Codable, Sendable {
    var takenAt: Date
    var isComplete = false
    /// "Debug" or "Release".
    var buildConfiguration: String
    var modelIdentifier: String
    var osBuild: String
    var thermalAtStart: String
    var thermalAtEnd: String?
    /// The step running now.
    var breadcrumb = ""
    /// What the model read at launch: the combined camera's id, base zooms and format count, or "none".
    var combinedCamera = ""
    var steps: [LensRunStep] = []
    var passed = 0
    var failed = 0
    var errors: [String] = []
}

/// One scripted action and what the model and the session showed after it.
nonisolated struct LensRunStep: Codable, Sendable {
    var label: String
    /// "fast": no blur, the combined camera, the lens the button names. "blur to combined", "blur to own": a configure behind
    /// the blur that ends on that camera. "check": only `passed` and `why` say what was expected.
    var expects: String
    /// Whether the model raised the viewfinder blur at the call.
    var blurRaised: Bool
    /// From the call until the model's queued configures had finished.
    var configureWaitMs: Double
    /// From the call until the session's camera reported the expected camera, lens and zoom; nil when it never did.
    var lensActiveMs: Double?
    var modelLens: String
    /// The zoom on the combined camera in the configuration the session last applied; nil on a lens's own camera.
    var combinedZoom: Double?
    /// Read off the camera after the step settled.
    var session: [String: String]
    var notice: String?
    var passed: Bool
    var why: String?
}
