import SwiftUI

/// Holds the shutter blink and alone reads the photo counter, so a photo re-runs this small view and not the viewfinder.
struct ShutterBlinkOverlay: View {
    @Environment(\.shutterBlinks) private var shutterBlinks

    var body: some View {
        ShutterBlink(trigger: shutterBlinks)
    }
}
