import SwiftUI

/// Picks the camera layout for the posture and keeps its controls clear of the system's bars. It sits inside the
/// navigation stack, where the toolbar's vertical edge and the bars' safe area are known.
struct CameraLayout: View {
    let model: CameraModel
    let isLandscape: Bool

    /// The side of the system's vertical bar; nil where the system draws its bars across the top and bottom instead.
    @Environment(\.toolbarVerticalEdge) private var stripEdge
    @Environment(\.isFoldedDisplay) private var isFoldedDisplay

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
    /// ignored. On the open phone the controls stay inside the whole top and bottom safe area in both orientations, and the
    /// layouts let the picture give up height for it. Without a vertical bar the toolbar floats at the bottom, and its glass
    /// reaches about 13 pt above the bottom safe area it reports (measured in the Simulator), so the controls keep a further
    /// `Theme.Space.l` from it. The folded phone's layouts were designed for its outer display, corners and home indicator
    /// included, and keep the full height there.
    private func barInsets(_ safeArea: EdgeInsets) -> EdgeInsets {
        guard !isFoldedDisplay else { return EdgeInsets() }
        let floatingBar = stripEdge == nil && safeArea.bottom > 0 ? Theme.Space.l : 0
        return EdgeInsets(top: safeArea.top, leading: 0, bottom: safeArea.bottom + floatingBar, trailing: 0)
    }
}
