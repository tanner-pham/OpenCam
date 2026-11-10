import Foundation

/// What the session should capture. `video == nil` keeps the device's default format.
nonisolated struct SessionConfiguration: Sendable, Equatable {
    var lens: Lens
    var mode: CaptureMode
    var video: VideoOption?
    var photo: PhotoOption?
    var includesAudio: Bool
}

nonisolated extension SessionConfiguration {
    /// Sound is recorded only with microphone access; without it video still records.
    static func make(lens: Lens, mode: CaptureMode, video: VideoOption?, photo: PhotoOption?, access: CaptureAccess) -> SessionConfiguration {
        SessionConfiguration(lens: lens, mode: mode, video: video, photo: photo, includesAudio: access.recordsSound)
    }
}
