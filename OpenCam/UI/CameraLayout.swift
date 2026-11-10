import SwiftUI

/// Picks the camera layout for the posture and keeps its controls clear of the system's bars. It sits inside the
/// navigation stack, where the toolbar's vertical edge and the bars' safe area are known.
struct CameraLayout: View {
    let model: CameraModel
    let isLandscape: Bool

    /// The side of the system's vertical bar; nil where the system draws its bars across the top and bottom instead.
    @Environment(\.toolbarVerticalEdge) private var stripEdge

    var body: some View {
        // The outer reader stays inside the safe area, so it reports the bars' insets; the layout itself spans the full
        // height and keeps its controls clear of them.
        GeometryReader { safe in
            let insets = barInsets(safe.safeAreaInsets)
            GeometryReader { geo in
                if isLandscape {
                    FoldedHorizontalView(model: model, size: geo.size, insets: insets, stripEdge: stripEdge)
                } else if model.mode == .video {
                    FoldedVerticalVideoView(model: model, size: geo.size, insets: insets)
                } else {
                    FoldedVerticalView(model: model, size: geo.size, insets: insets)
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
        }
    }

    /// What the controls keep clear of at the top and bottom; the leading and trailing safe area (the side bar) is never
    /// ignored. With the system's bar on the side (the folded phone, and the open phone in landscape) the top and bottom
    /// insets are only the screen's corners and home indicator, which the layouts already allow for, so they use the full
    /// height. Without one (the open phone in portrait) the status sits at the top and the toolbar floats at the bottom,
    /// and the controls stay clear of both. The floating toolbar's glass reaches about 13 pt above the bottom safe area it
    /// reports (measured on the open phone in the Simulator), so the controls keep a further `Theme.Space.l` from it.
    private func barInsets(_ safeArea: EdgeInsets) -> EdgeInsets {
        guard stripEdge == nil else { return EdgeInsets() }
        let bottom = safeArea.bottom > 0 ? safeArea.bottom + Theme.Space.l : 0
        return EdgeInsets(top: safeArea.top, leading: 0, bottom: bottom, trailing: 0)
    }
}
