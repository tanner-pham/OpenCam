import SwiftUI
import UIKit

/// The only screen of a `-recorderCheck` launch: black, with one line of text. The screen stays on while the check runs.
struct RecorderCheckView: View {
    let isFinished: Bool

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                Text(isFinished ? "Recorder check finished." : "Recorder check running. Keep the app open.")
                    .foregroundStyle(.white)
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onChange(of: isFinished) { _, isFinished in
                UIApplication.shared.isIdleTimerDisabled = !isFinished
            }
    }
}
