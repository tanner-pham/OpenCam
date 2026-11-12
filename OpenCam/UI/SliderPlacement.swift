import SwiftUI

/// Where the open control's slider is drawn: in the side strip, or inside the picture.
nonisolated enum SliderPlacement: Sendable, Equatable {
    case strip
    case picture(edge: HorizontalEdge)

    /// The folded display with a strip swaps the strip's items. Anywhere else the slider goes in the picture, beside the
    /// strip when there is one and at the trailing edge when there is not.
    static func resolve(isFoldedDisplay: Bool, stripEdge: HorizontalEdge?) -> SliderPlacement {
        isFoldedDisplay && stripEdge != nil ? .strip : .picture(edge: stripEdge ?? .trailing)
    }
}

extension EnvironmentValues {
    /// The folded phone's outer display is compact in one direction in either orientation; the open phone's inner display
    /// is regular in both.
    var isFoldedDisplay: Bool { horizontalSizeClass == .compact || verticalSizeClass == .compact }

    var sliderPlacement: SliderPlacement {
        SliderPlacement.resolve(isFoldedDisplay: isFoldedDisplay, stripEdge: toolbarVerticalEdge)
    }
}
