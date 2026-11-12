import Foundation

/// What the session should capture. `video == nil` keeps the device's default format. `needsFrames` attaches the data
/// output that draws a look on the viewfinder; false (no look) leaves the session's outputs as they always were.
/// `recorder` says which recorder the video outputs are for: the system movie output, or the writer's data outputs.
nonisolated struct SessionConfiguration: Codable, Sendable, Equatable {
    var lens: Lens
    var mode: CaptureMode
    var video: VideoOption?
    var photo: PhotoOption?
    var includesAudio: Bool
    var needsFrames = false
    var recorder: RecorderPath = .system

    /// A saved start written before recorder paths has no `recorder` and decodes as `.system`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lens = try container.decode(Lens.self, forKey: .lens)
        mode = try container.decode(CaptureMode.self, forKey: .mode)
        video = try container.decodeIfPresent(VideoOption.self, forKey: .video)
        photo = try container.decodeIfPresent(PhotoOption.self, forKey: .photo)
        includesAudio = try container.decode(Bool.self, forKey: .includesAudio)
        needsFrames = try container.decodeIfPresent(Bool.self, forKey: .needsFrames) ?? false
        recorder = try container.decodeIfPresent(RecorderPath.self, forKey: .recorder) ?? .system
    }

    init(lens: Lens, mode: CaptureMode, video: VideoOption?, photo: PhotoOption?, includesAudio: Bool, needsFrames: Bool = false,
         recorder: RecorderPath = .system) {
        self.lens = lens
        self.mode = mode
        self.video = video
        self.photo = photo
        self.includesAudio = includesAudio
        self.needsFrames = needsFrames
        self.recorder = recorder
    }
}

nonisolated extension SessionConfiguration {
    /// Sound is recorded only with microphone access; without it video still records.
    static func make(lens: Lens, mode: CaptureMode, video: VideoOption?, photo: PhotoOption?, access: CaptureAccess,
                     needsFrames: Bool = false, recorder: RecorderPath = .system) -> SessionConfiguration {
        SessionConfiguration(lens: lens, mode: mode, video: video, photo: photo, includesAudio: access.recordsSound, needsFrames: needsFrames,
                             recorder: recorder)
    }
}
