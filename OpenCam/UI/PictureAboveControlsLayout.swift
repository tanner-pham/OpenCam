import SwiftUI

/// A picture of a fixed aspect ratio above a column of controls. The controls always get at least the height they need;
/// the picture takes the rest, up to the full width, and gives up height first when the space is short, keeping its
/// ratio and centred. Any height the picture does not use goes to the controls. Exactly two subviews: picture, controls.
struct PictureAboveControlsLayout: Layout {
    /// Width over height.
    let pictureAspect: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let picture = subviews[0], controls = subviews[1]
        let controlsNeed = controls.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        let pictureHeight = max(0, min(bounds.width / pictureAspect, bounds.height - controlsNeed))
        let pictureWidth = pictureHeight * pictureAspect
        picture.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                      proposal: ProposedViewSize(width: pictureWidth, height: pictureHeight))
        controls.place(at: CGPoint(x: bounds.minX, y: bounds.minY + pictureHeight), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: bounds.height - pictureHeight))
    }
}
