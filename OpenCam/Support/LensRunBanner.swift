import Observation
import SwiftUI
import UIKit

/// What the scripted lens run shows over the camera: the step it is on.
@Observable
final class LensRunProgress {
    var line = "Lens run"
    var isFinished = false
}

/// One line over the real camera screen while a `-lensRun` launch drives it. The screen stays on meanwhile.
struct LensRunBanner: View {
    let progress: LensRunProgress

    var body: some View {
        Text(progress.line)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 60)
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onChange(of: progress.isFinished) { _, isFinished in
                UIApplication.shared.isIdleTimerDisabled = !isFinished
            }
    }
}
