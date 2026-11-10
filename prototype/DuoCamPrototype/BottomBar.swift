import SwiftUI

/// Histogram, format summary, audio meters, remaining time and the record button.
struct BottomBar: View {
    let model: CaptureModel

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            HistogramView()
            Spacer(minLength: 0)
            FormatButton(parts: model.summaryParts) { model.sheet = .record }
            Spacer(minLength: 0)
            Button { model.sheet = .audio } label: {
                AudioMetersView(levels: model.meterLevels)
                    .frame(minHeight: Theme.Size.minTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(model.remainingText)
                .font(Theme.Text.value)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            CaptureButton(symbol: model.isRecording ? "stop.fill" : "circle.fill", tint: Theme.recordRed,
                          label: model.isRecording ? "Stop recording" : "Start recording") {
                model.toggleRecording()
            }
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Size.cornerInset)
    }
}
