import SwiftUI

/// Folded, vertical, video. The picture fills the area beside the strip; readouts and controls float on glass.
struct FoldedVerticalVideoView: View {
    let model: CameraModel
    let size: CGSize

    var body: some View {
        ZStack {
            ViewfinderArea(phase: model.phase, captionTopInset: Theme.Space.l + Theme.Size.minTarget + Theme.Space.s)
            VStack(spacing: 0) {
                TopReadoutBar(model: model, isCompact: true)
                    .padding(.horizontal, Theme.Space.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.Space.l))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.l)
                Spacer(minLength: 0)
                bottomControls
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, Theme.Space.l)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var bottomControls: some View {
        GlassEffectContainer(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                FormatButton(parts: model.summaryParts) { model.openRecordSettings() }
                    .disabled(!model.canOpenRecordSettings)
                HStack(spacing: Theme.Space.s) {
                    AudioMetersView(levels: model.meterLevels, width: 56)
                    Text(model.remainingText).font(Theme.Text.compactValue).fixedSize()
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: Theme.Size.minTarget)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                CaptureButton(model: model)
            }
        }
    }
}
