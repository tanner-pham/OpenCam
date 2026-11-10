import SwiftUI

/// The picture area. Only the Simulator stand-in exists so far; other phases show black until the live preview lands.
struct ViewfinderArea: View {
    let phase: CameraPhase
    var captionTopInset: CGFloat = 0

    var body: some View {
        switch phase {
        case .simulator:
            ViewfinderStandIn(captionTopInset: captionTopInset)
        case .scanning, .ready, .cameraDenied, .cameraRestricted, .failed:
            Color.black
        }
    }
}
