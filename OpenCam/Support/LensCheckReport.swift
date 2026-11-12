import Foundation

/// Everything the lens check found. Written to `Documents/lens-check.json` before and after every step, so after a crash
/// `breadcrumb` names the step that never finished and everything before it is on disk.
nonisolated struct LensCheckReport: Codable, Sendable {
    var schemaVersion = 1
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
    var completedSections: [String] = []
    var notes: [String]
    /// What the combined camera and its two cameras say about themselves before any session runs.
    var facts: [String: String] = [:]
    /// Lens changes on the combined camera, one run per video format.
    var switching: [LensCheckRun] = []
    /// Manual exposure, white balance and focus across a lens change.
    var manual: [LensCheckReading] = []
    /// Lens changes while the system movie output records.
    var movie: [LensCheckRun] = []
    /// What the photo output offers on the photo preset.
    var photoPreset: [LensCheckReading] = []
    /// Today's lens change: one camera input removed and another added.
    var baseline: [LensCheckRun] = []
    /// Which lens the combined camera uses for 1x with a subject a few centimetres away.
    var closeSubject: [LensCheckReading] = []
    var errors: [String] = []
}

/// One session and the lens changes measured on it.
nonisolated struct LensCheckRun: Codable, Sendable {
    var label: String
    var setup: [String: String] = [:]
    var transitions: [LensCheckTransition] = []
    /// The recorded file read back, for the movie runs.
    var file: [String: String]?
    var failure: String?
}

/// The camera's state at one named moment.
nonisolated struct LensCheckReading: Codable, Sendable {
    var label: String
    var values: [String: String]
}

/// One lens or zoom change. Every time is in milliseconds from the moment just before the call that asked for it.
nonisolated struct LensCheckTransition: Codable, Sendable {
    /// "auto jump", "auto ramp 4", "restricted jump", "locked", "input swap".
    var method: String
    var from: String
    var to: String
    var lensBefore: String
    var lensAfter: String
    var zoomAfter: Double
    /// How long the call itself took to return.
    var callMs: Double
    /// When a zoom had to wait for the camera's zoom range to change after a lock, how long it waited.
    var zoomWaitMs: Double?
    /// When the combined camera reported another active lens (key-value observation), and which.
    var lensChangeReportedMs: Double?
    var lensChangeReportedTo: String?
    /// The first frame whose aperture differs from the frames before the call: when it was captured and when it arrived.
    var firstOtherLensFrameCapturedMs: Double?
    var firstOtherLensFrameArrivedMs: Double?
    /// When a zoom ramp reported it had ended.
    var rampEndedMs: Double?
    var apertureBefore: Double?
    var apertureAfter: Double?
    var nominalFrameMs: Double
    /// The longest time between two frames in a row, from the last frame before the call onward.
    var longestFrameGapMs: Double
    var framesAfterCall: Int
    var framesDropped: Int
    var dropReasons: [String] = []
    var failure: String?
    /// Every frame of the window: [captured ms, arrived ms, aperture, exposure ms, ISO, digital zoom]; -1 where the frame did not say.
    var frames: [[Double]] = []
}
