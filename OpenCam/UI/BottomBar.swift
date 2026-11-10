import SwiftUI

/// Format summary, audio meters, remaining time and the capture button. The histogram slot stays empty until the monitoring plan.
struct BottomBar: View {
    let model: CameraModel

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Color.clear.frame(width: Theme.Size.histogramWidth, height: Theme.Size.histogramHeight)
            Spacer(minLength: 0)
            FormatButton(parts: model.summaryParts) { model.sheet = .record }
            Spacer(minLength: 0)
            AudioMetersView(levels: model.meterLevels)
                .frame(minHeight: Theme.Size.minTarget)
            Spacer(minLength: 0)
            Text(model.remainingText)
                .font(Theme.Text.value)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            CaptureButton(model: model)
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Size.cornerInset)
    }
}
