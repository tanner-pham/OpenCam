import SwiftUI

/// Puts the check's preview view on screen.
struct RecorderCheck2PreviewView: UIViewRepresentable {
    let view: RecorderCheck2PreviewUIView

    func makeUIView(context: Context) -> RecorderCheck2PreviewUIView { view }

    func updateUIView(_ uiView: RecorderCheck2PreviewUIView, context: Context) {}
}
