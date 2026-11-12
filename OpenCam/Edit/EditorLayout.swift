import SwiftUI

/// How the editor arranges the picture and the panel.
nonisolated enum EditorLayout: Equatable, Sendable {
    case sideBySide, stacked

    static let panelWidth: CGFloat = 320

    /// Regular width, or compact height (the outer display held horizontally), puts the panel beside the picture.
    static func choose(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> EditorLayout {
        horizontal == .regular || vertical == .compact ? .sideBySide : .stacked
    }

    /// Stacked, the picture never takes so much height that less than this is left for the panel below the info line.
    /// Curve needs room for its square canvas under the group and channel pickers; Mix for its band buttons and the first
    /// slider rows; Grading for its first wheel.
    static func minPanelHeight(for group: EditorGroup) -> CGFloat {
        switch group {
        case .curve, .mix, .grading: 340
        case .light, .colour, .detail, .effects, .looks: 240
        }
    }
}
