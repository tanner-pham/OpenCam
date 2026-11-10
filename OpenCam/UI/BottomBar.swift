import SwiftUI

/// Format summary, audio meters, remaining time and the capture button. The histogram slot stays empty until the monitoring plan.
struct BottomBar: View {
    let model: CameraModel

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            controls
            // Always reserves its line, so the controls do not move when a notice comes and goes.
            NoticeLine(model: model)
                .frame(height: Theme.Size.noticeLine)
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Size.cornerInset)
        .padding(.bottom, Theme.Space.s)
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.l) {
            Color.clear.frame(width: Theme.Size.histogramWidth, height: Theme.Size.histogramHeight)
            Spacer(minLength: 0)
            FormatButton(parts: model.summaryParts, isWarning: model.sweepCaption != nil,
                         onLongPress: model.mode == .video ? { model.openSweep() } : nil) { model.openRecordSettings() }
                .disabled(!model.canOpenRecordSettings)
            Spacer(minLength: 0)
            if model.showsVideoReadouts {
                AudioMetersView(levels: model.shownMeterLevels)
                    .frame(minHeight: Theme.Size.minTarget)
                Spacer(minLength: 0)
                Text(model.remaining.text)
                    .font(Theme.Text.value)
                    .foregroundStyle(model.remaining.isWarning ? Theme.recordRed : .secondary)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            CaptureButton(model: model)
        }
    }
}
