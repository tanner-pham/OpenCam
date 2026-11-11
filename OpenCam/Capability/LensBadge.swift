import Foundation

/// How a lens is shown in the strip and in its menu.
/// Back lenses keep their zoom text, because a symbol alone cannot tell 0.5x, 1x and 2x apart. The front cameras show a
/// symbol of the phone: folded for the outer display's camera, open for the inner display's. A lens the table has no row
/// for (`LensKind` is closed, so that is a kind and zoom pair such as a 3x wide crop) shows its own label.
nonisolated struct LensBadge: Sendable, Equatable {
    /// The menu's symbol for a back lens, which has none in the strip.
    static let backLensSymbol = "camera.aperture"

    var shortText: String?        // "0.5x", "1x", "2x" for back lenses; nil when the strip shows only a symbol
    var symbol: String?           // an SF Symbol name for the front cameras; nil for back lenses
    var menuTitle: String         // "Ultra wide", "Wide", "Wide, 2x crop", "Front, outer display", "Front, inner display"

    /// The menu row's title: the zoom text before the name for back lenses, the name alone for the front cameras.
    var rowTitle: String {
        guard let shortText, shortText != menuTitle else { return menuTitle }
        return "\(shortText) \(menuTitle)"
    }

    static func make(for lens: Lens) -> LensBadge {
        switch (lens.kind, lens.zoomFactor) {
        case (.ultraWide, 1): LensBadge(shortText: "0.5x", symbol: nil, menuTitle: "Ultra wide")
        case (.wide, 1): LensBadge(shortText: "1x", symbol: nil, menuTitle: "Wide")
        case (.wide, 2): LensBadge(shortText: "2x", symbol: nil, menuTitle: "Wide, 2x crop")
        // Both symbols are in this SDK (checked with `UIImage(systemName:)` in `LensBadgeTests`): `iphone.duo` is the folded
        // phone with its outer camera, `iphone.duo.open.landscape` the open phone.
        case (.outerUltraWide, _): LensBadge(shortText: nil, symbol: "iphone.duo", menuTitle: "Front, outer display")
        case (.innerUltraWide, _): LensBadge(shortText: nil, symbol: "iphone.duo.open.landscape", menuTitle: "Front, inner display")
        default: LensBadge(shortText: lens.label, symbol: nil, menuTitle: lens.label)
        }
    }
}
