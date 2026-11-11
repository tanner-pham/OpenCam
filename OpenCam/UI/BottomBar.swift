import SwiftUI

/// Format summary, audio meters, remaining time and the capture button. The histogram slot stays empty until the monitoring plan.
struct BottomBar: View {
    let model: CameraModel
    /// The side of the system's vertical bar. The bar keeps the screen's corner inset on the other side.
    var stripEdge: HorizontalEdge? = .leading

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            controls
            // Always reserves its line, so the controls do not move when a notice comes and goes.
            NoticeLine(model: model)
                .frame(height: Theme.Size.noticeLine)
        }
        .padding(stripEdge == .trailing ? .trailing : .leading, Theme.Space.l)
        .padding(stripEdge == .trailing ? .leading : .trailing, Theme.Size.cornerInset)
        .padding(.bottom, Theme.Space.s)
    }

    /// The row with its usual gaps when it fits; with half gaps when it would be wider than the bar (a long summary with a
    /// look, such as "ProRes 1080p Rec. 709 Warm fade"), so it never overflows. Every control keeps its size.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlsRow(spacing: Theme.Space.l)
            controlsRow(spacing: Theme.Space.s)
        }
    }

    private func controlsRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            // Empty room for the histogram. Its width is fixed, as it always was, unless a look's name is in the summary: only
            // then may it give way, so the row with no look is laid out exactly as before.
            Color.clear.frame(minWidth: model.summaryLookName == nil ? Theme.Size.histogramWidth : 0, maxWidth: Theme.Size.histogramWidth,
                              minHeight: Theme.Size.histogramHeight, maxHeight: Theme.Size.histogramHeight)
            Spacer(minLength: 0)
            FormatButton(parts: model.summaryParts, isWarning: model.sweepCaption != nil,
                         onLongPress: model.mode == .video ? { model.openSweep() } : nil) { model.openRecordSettings() }
                .disabled(!model.canOpenRecordSettings)
            Spacer(minLength: 0)
            if model.showsVideoReadouts {
                LiveAudioMeters(model: model)
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
