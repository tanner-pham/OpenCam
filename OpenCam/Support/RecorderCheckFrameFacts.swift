/// What the first frame the camera delivered looked like, read from the pixel buffer itself.
nonisolated struct RecorderCheckFrameFacts: Codable, Sendable {
    var width = 0
    var height = 0
    /// The pixel buffer's format as a four-character code.
    var pixelFormat = ""
    var bitDepthFromPixelFormat = 0
    /// The buffer's colour attachments; nil when the buffer carries none.
    var colourPrimaries: String?
    var transferFunction: String?
    var yCbCrMatrix: String?
    var note: String?
}
