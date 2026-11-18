import SwiftUI
import UIKit

/// The only screen of a `-rawSizeCheck` launch: black, with one line of text. The screen stays on while the check runs.
struct RawSizeCheckView: View {
    let progress: RawSizeCheckProgress

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay { Text(progress.line).foregroundStyle(.white) }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onChange(of: progress.isFinished) { _, isFinished in
                UIApplication.shared.isIdleTimerDisabled = !isFinished
            }
    }
}
