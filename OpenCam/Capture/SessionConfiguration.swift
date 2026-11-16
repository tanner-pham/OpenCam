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
    /// Set when the combined back camera records this configuration; nil is the lens's own camera, as always.
    var combined: CombinedLens?

    /// The camera the session attaches.
    var cameraUniqueID: String { combined?.deviceUniqueID ?? lens.deviceUniqueID }
    /// The zoom on that camera.
    var zoomFactor: Double { combined?.zoomFactor ?? lens.zoomFactor }

    /// True when both are video on the same combined camera with the same codec, size, rate, colour, sound, frame feed and
    /// recorder, so at most the lens differs. `photo` and each option's `lensID` are not compared: video ignores the first and
    /// the second only says which lens lists the option.
    func changesOnlyLens(from previous: SessionConfiguration) -> Bool {
        guard let combined, let before = previous.combined, combined.deviceUniqueID == before.deviceUniqueID,
              mode == .video, previous.mode == .video, let video, let previousVideo = previous.video else { return false }
        return video.codec == previousVideo.codec
            && video.resolution == previousVideo.resolution
            && video.frameRate == previousVideo.frameRate
            && video.colour == previousVideo.colour
            && includesAudio == previous.includesAudio
            && needsFrames == previous.needsFrames
            && recorder == previous.recorder
    }

    /// A saved start written before recorder paths has no `recorder` and decodes as `.system`; one written before the combined
    /// camera has no `combined` and decodes as nil.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lens = try container.decode(Lens.self, forKey: .lens)
        mode = try container.decode(CaptureMode.self, forKey: .mode)
        video = try container.decodeIfPresent(VideoOption.self, forKey: .video)
        photo = try container.decodeIfPresent(PhotoOption.self, forKey: .photo)
        includesAudio = try container.decode(Bool.self, forKey: .includesAudio)
        needsFrames = try container.decodeIfPresent(Bool.self, forKey: .needsFrames) ?? false
        recorder = try container.decodeIfPresent(RecorderPath.self, forKey: .recorder) ?? .system
        combined = try container.decodeIfPresent(CombinedLens.self, forKey: .combined)
    }

    init(lens: Lens, mode: CaptureMode, video: VideoOption?, photo: PhotoOption?, includesAudio: Bool, needsFrames: Bool = false,
         recorder: RecorderPath = .system, combined: CombinedLens? = nil) {
        self.lens = lens
        self.mode = mode
        self.video = video
        self.photo = photo
        self.includesAudio = includesAudio
        self.needsFrames = needsFrames
        self.recorder = recorder
        self.combined = combined
    }
}

nonisolated extension SessionConfiguration {
    /// Sound is recorded only with microphone access; without it video still records.
    static func make(lens: Lens, mode: CaptureMode, video: VideoOption?, photo: PhotoOption?, access: CaptureAccess,
                     needsFrames: Bool = false, recorder: RecorderPath = .system,
                     combined: CombinedLens? = nil) -> SessionConfiguration {
        SessionConfiguration(lens: lens, mode: mode, video: video, photo: photo, includesAudio: access.recordsSound, needsFrames: needsFrames,
                             recorder: recorder, combined: combined)
    }
}
