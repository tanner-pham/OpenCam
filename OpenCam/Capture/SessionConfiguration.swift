import Foundation

/// What the session should capture. `video == nil` keeps the device's default format. `needsFrames` attaches the data
/// output that draws a look on the viewfinder; false (no look) leaves the session's outputs as they always were.
nonisolated struct SessionConfiguration: Codable, Sendable, Equatable {
    var lens: Lens
    var mode: CaptureMode
    var video: VideoOption?
    var photo: PhotoOption?
    var includesAudio: Bool
    var needsFrames = false
}

nonisolated extension SessionConfiguration {
    /// Sound is recorded only with microphone access; without it video still records.
    static func make(lens: Lens, mode: CaptureMode, video: VideoOption?, photo: PhotoOption?, access: CaptureAccess,
                     needsFrames: Bool = false) -> SessionConfiguration {
        SessionConfiguration(lens: lens, mode: mode, video: video, photo: photo, includesAudio: access.recordsSound, needsFrames: needsFrames)
    }
}
