import Foundation

/// The five values a record selection and a video option share, so an option is found by lookup instead of a walk.
/// The resolution is compared by its size, as `Resolution.id` is, never by its label.
nonisolated struct RecordOptionKey: Hashable, Sendable {
    let family: CodecFamily
    let quality: String
    let width: Int
    let height: Int
    let frameRate: Int
    let colour: ColourMode

    init(_ option: VideoOption) {
        family = option.codec.family
        quality = option.codec.quality
        width = option.resolution.width
        height = option.resolution.height
        frameRate = option.frameRate
        colour = option.colour
    }

    init(_ selection: RecordSelection) {
        family = selection.family
        quality = selection.quality
        width = selection.resolution.width
        height = selection.resolution.height
        frameRate = selection.frameRate
        colour = selection.colour
    }
}
