import SwiftUI

/// How the editor arranges the picture and the panel.
nonisolated enum EditorLayout: Equatable, Sendable {
    case sideBySide, stacked

    static let panelWidth: CGFloat = 320

    /// Regular width, or compact height (the outer display held horizontally), puts the panel beside the picture.
    static func choose(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> EditorLayout {
        horizontal == .regular || vertical == .compact ? .sideBySide : .stacked
    }
}
