import Foundation

/// What the open slider needs to draw and to speak, as plain values.
nonisolated struct OpenSlider: Sendable, Equatable {
    var control: ManualControl
    var stepCount: Int
    /// The thumb's step; nil when the camera reports no value.
    var step: Int?
    /// Steps per VoiceOver increment.
    var adjustStride: Int
    var text: String
    var spoken: String
    /// Not set by hand (EV, which has no Auto, is always so).
    var isAutomatic: Bool
}
