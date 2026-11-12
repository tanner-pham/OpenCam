import SwiftUI

/// The count of frames missing from the clip being recorded, over the picture. Drawn only while recording with a count above
/// zero, and always as an overlay, so no control moves when it appears. It reads only `isRecording` and `droppedFrames`, so a new
/// count re-runs this body alone. The capsule carries the warning (red text over the picture is unreadable); the text stays primary.
struct DroppedFramesBadge: View {
    let model: CameraModel
    var isCompact = false

    var body: some View {
        if model.isRecording, model.droppedFrames > 0 {
            ReadoutView(caption: "DROPPED", value: String(model.droppedFrames), isCompact: isCompact, isOnWarning: true)
                .fixedSize()
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.xs)
                .glassEffect(.regular.tint(Theme.recordRed), in: .capsule)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Dropped frames")
                .accessibilityValue(String(model.droppedFrames))
        }
    }
}
