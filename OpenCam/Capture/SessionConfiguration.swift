import Foundation

/// What the session should capture. `video == nil` keeps the device's default format.
nonisolated struct SessionConfiguration: Sendable, Equatable {
    var lens: Lens
    var mode: CaptureMode
    var video: VideoOption?
    var photo: PhotoOption?
    var includesAudio: Bool
}
