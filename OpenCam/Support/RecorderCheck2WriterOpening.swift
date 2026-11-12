import CoreVideo
import Foundation

/// Lets the trial open a sink's writer without naming a deprecated method (the sink's witness is deprecated, the requirement is not).
nonisolated protocol RecorderCheck2WriterOpening {
    /// `audioSettings` nil means no sound input. With `pixelFormat` set, video goes through a pixel buffer adaptor.
    /// Returns a note about the audio input when it could not be made (the video input is still opened).
    func open(url: URL, videoSettings: [String: Any], audioSettings: [String: Any]?, adaptorFormat: (width: Int, height: Int, pixelFormat: OSType)?) throws -> String?
}
