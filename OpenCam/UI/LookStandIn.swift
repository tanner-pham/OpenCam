import SwiftUI

/// The Simulator's stand-in viewfinder. With no look it is `ViewfinderStandIn` as always; with one, it is `LookedStandIn`.
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
