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
                // The summary is on one line when it fits beside the meters and the shutter, and stacked when it does not (a
                // longer summary such as "ProRes 1080p Rec. 709"), so the row is never wider than the screen. Its priority
                // offers it all the width the meters, the time left and the shutter leave, and those keep their places and
                // sizes either way. With a look the summary has a fourth part and is always stacked.
                ViewThatFits(in: .horizontal) {
                    if model.summaryLookName == nil { formatButton(isStacked: false) }
                    formatButton(isStacked: true)
                }
                .layoutPriority(1)
                // "Storage full" is wider than the minutes, so the meters give way to it.
                HStack(spacing: Theme.Space.s) {
                    if !model.isStorageFull { LiveAudioMeters(model: model, width: 48) }
                    remainingText
                }
                .padding(.horizontal, Theme.Space.s + Theme.Space.xs / 2)
                .frame(minHeight: Theme.Size.minTarget)
                .glassEffect(.regular, in: .capsule)
                // Pushed to the trailing edge by its frame rather than a spacer, which would add a second gap of its own.
                CaptureButton(model: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func formatButton(isStacked: Bool) -> some View {
        FormatButton(parts: model.summaryParts, isStacked: isStacked, isWarning: model.sweepCaption != nil,
                     onLongPress: { model.openSweep() }) { model.openRecordSettings() }
            .disabled(!model.canOpenRecordSettings)
    }

    private var remainingText: some View {
        Text(model.remaining.text)
            .font(Theme.Text.compactValue)
            .foregroundStyle(model.remaining.isWarning ? Theme.recordRed : .primary)
            .fixedSize()
    }
}
