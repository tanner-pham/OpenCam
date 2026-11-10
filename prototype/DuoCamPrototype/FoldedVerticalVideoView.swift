import SwiftUI

/// Folded, vertical, video. The picture fills the area beside the strip; readouts and controls float on glass.
struct FoldedVerticalVideoView: View {
    let model: CaptureModel
    let size: CGSize

    var body: some View {
        ZStack {
            ViewfinderStandIn(isFlat: model.lut == .off, captionTopInset: Theme.Space.l + Theme.Size.minTarget + Theme.Space.s)
            VStack(spacing: 0) {
                TopReadoutBar(model: model, isCompact: true)
                    .padding(.horizontal, Theme.Space.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.Space.l))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.l)
                Spacer(minLength: 0)
                if let readout = model.selectedReadout {
                    AdjustRulerView(readout: readout, model: model)
                        .padding(.horizontal, -Theme.Space.s)
                }
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
                FormatButton(parts: model.summaryParts) { model.sheet = .record }
                Button { model.sheet = .audio } label: {
                    HStack(spacing: Theme.Space.s) {
                        AudioMetersView(levels: model.meterLevels, width: 56)
                        Text(model.remainingText).font(Theme.Text.compactValue)
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .frame(minHeight: Theme.Size.minTarget)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                CaptureButton(symbol: model.isRecording ? "stop.fill" : "circle.fill", tint: Theme.recordRed,
                              label: model.isRecording ? "Stop recording" : "Start recording") {
                    model.toggleRecording()
                }
            }
        }
    }
}
