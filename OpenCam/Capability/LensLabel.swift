import Foundation

/// The lens menu label. The SDK does not say which ultra wide is the outer front camera, so those use the device name.
nonisolated enum LensLabel {
    static func text(kind: LensKind, zoomFactor: Double, localizedName: String) -> String {
        switch kind {
        case .ultraWide: "0.5x"
        case .wide: zoomFactor == 2 ? "2x" : "1x"
        case .outerUltraWide, .innerUltraWide: localizedName
        }
    }
}
