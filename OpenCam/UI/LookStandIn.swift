import SwiftUI

/// The Simulator's stand-in viewfinder. With no look it is `ViewfinderStandIn` as always; with one, the stand-in picture
/// is rendered once per size and look and drawn filling the area, and the plain stand-in shows until it is ready.
struct LookStandIn: View {
    let look: CameraLook?
    var captionTopInset: CGFloat = 0

    var body: some View {
        if let look {
            LookedStandIn(look: look, captionTopInset: captionTopInset)
        } else {
            ViewfinderStandIn(captionTopInset: captionTopInset)
        }
    }
}

private struct LookedStandIn: View {
    struct Key: Equatable {
        let size: CGSize
        let scale: CGFloat
        let look: CameraLook
    }

    let look: CameraLook
    let captionTopInset: CGFloat

    @Environment(\.displayScale) private var scale
    @State private var size = CGSize.zero
    @State private var picture: CGImage?

    /// The area's size comes from a clear base, so the picture never decides how large the area is.
    var body: some View {
        Color.clear
            .overlay {
                if let picture {
                    Image(decorative: picture, scale: scale)
                        .resizable()
                        .overlay(alignment: .topLeading) { StandInCaption(topInset: captionTopInset) }
                } else {
                    ViewfinderStandIn(captionTopInset: captionTopInset)
                }
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .task(id: Key(size: size, scale: scale, look: look)) {
                guard size.width > 0, size.height > 0, let base = StandInPicture.base(size: size, scale: scale) else { return }
                let looked = await StandInPicture.looked(base, look: look)
                // A newer size or look replaced this task; its picture must not land after the newer one.
                guard !Task.isCancelled else { return }
                picture = looked
            }
    }
}
