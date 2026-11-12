import Foundation

/// One region of colour grading: a hue to push towards, how strongly, and a lift or drop in brightness.
nonisolated struct ColourTint: Sendable, Equatable {
    /// Degrees, 0...360.
    var hue: Float
    /// 0...1.
    var saturation: Float
    /// -1...1.
    var luminance: Float

    init(hue: Float, saturation: Float, luminance: Float = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }

    static let none = ColourTint(hue: 0, saturation: 0)
}
