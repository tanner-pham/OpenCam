import SwiftUI

/// Folded, vertical, video. The picture fills the area beside the strip; readouts and controls float on glass.
struct FoldedVerticalVideoView: View {
    let model: CameraModel
    let size: CGSize
    /// The system bars' top and bottom insets the controls keep clear of; zero on the folded phone. The picture still fills
    /// the whole height.
    var insets = EdgeInsets()

    var body: some View {
        ZStack {
            ViewfinderArea(phase: model.phase, look: model.viewfinderLook, captionTopInset: insets.top + Theme.Space.l + Theme.Size.minTarget + Theme.Space.s,
                           onRetry: model.isCameraStopped ? { model.retryCamera() } : nil)
            VStack(spacing: 0) {
                TopReadoutBar(model: model, isCompact: true)
                    .padding(.horizontal, Theme.Space.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.Space.l))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.l)
                Spacer(minLength: 0)
                if model.bottomNotice != nil {
                    NoticeLine(model: model, isOnGlass: true)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, Theme.Space.xs)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, Theme.Space.s)
                }
                bottomControls
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, Theme.Space.l)
            }
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var bottomControls: some View {
        GlassEffectContainer(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                // The summary is on one line when it fits beside the meters and the shutter; with a look, the format on one
                // line and the look on a second; and one part per line when that does not fit either (a longer summary such
                // as "ProRes 1080p Rec. 709", or larger text), so the row is never wider than the screen. Its priority offers
                // it all the width the meters, the time left and the shutter leave, and those keep their places and sizes
                // either way.
                ViewThatFits(in: .horizontal) {
                    formatButton(.oneLine)
                    if model.summaryLookName != nil { formatButton(.formatAndLook) }
                    formatButton(.onePerLine)
                }
                .layoutPriority(1)
                // The meters capsule takes the width the summary and the shutter leave, so the gaps between the three are
                // equal: the meters at its leading edge, the time left at its trailing edge. "Storage full" is wider than the
                // minutes, so the meters give way to it.
                HStack(spacing: Theme.Space.s) {
                    if !model.isStorageFull { LiveAudioMeters(model: model, width: 48) }
                    Spacer(minLength: 0)
                    remainingText
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.s + Theme.Space.xs / 2)
                .frame(minHeight: Theme.Size.minTarget)
                // Red text over the picture is unreadable (about 1.2:1), so the capsule carries the warning and the text stays primary.
                .glassEffect(model.remaining.isWarning ? .regular.tint(Theme.recordRed) : .regular, in: .capsule)
                CaptureButton(model: model)
            }
        }
    }

    private func formatButton(_ form: SummaryForm) -> some View {
        FormatButton(parts: model.summaryParts, form: form, hasLook: model.summaryLookName != nil, isWarning: model.sweepCaption != nil,
                     onLongPress: { model.openSweep() }) { model.openRecordSettings() }
            .disabled(!model.canOpenRecordSettings)
    }

    private var remainingText: some View {
        Text(model.remaining.text)
            .font(Theme.Text.compactValue)
            .foregroundStyle(.primary)
            .fixedSize()
    }
}
