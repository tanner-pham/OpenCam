import SwiftUI

/// The screen of a `-recorderCheck2` launch: the live preview full screen with two lines of text on a dark capsule.
struct RecorderCheck2View: View {
    let progress: RecorderCheck2Progress

    var body: some View {
        RecorderCheck2PreviewView(view: progress.previewView)
            .ignoresSafeArea()
            .background(Color.black)
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    Text(progress.isFinished ? "Recorder check 2 finished." : "Recorder check 2. Point the phone at a busy, moving scene.")
                    if !progress.isFinished, !progress.line.isEmpty { Text(progress.line) }
                }
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.7), in: Capsule())
                .padding(.bottom, 24)
                .padding(.horizontal, 16)
            }
    }
}
