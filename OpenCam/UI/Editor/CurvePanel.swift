import SwiftUI

/// The Curve group: the channel picker and Reset, over a square canvas of that channel's curve on the picture's histogram.
/// The canvas is outside any scroll view, so a vertical drag on it moves a point and never the panel.
struct CurvePanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let side = CurveGeometry.side(for: geo.size)
            VStack(spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    Picker("Curve channel", selection: $model.curveChannel) {
                        ForEach(CurveChannel.allCases, id: \.self) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Button("Reset") { model.resetCurve(model.curveChannel) }
                        .buttonStyle(.bordered)
                        .disabled(model.adjustments.curves[model.curveChannel].isIdentity)
                }
                // Every point edit writes the edit's curve for this channel, so it renders through the coalescer like a slider.
                // A new channel is a new canvas, so a touch under way never writes into another channel's curve.
                CurveCanvas(curve: $model.adjustments.curves[model.curveChannel], channel: model.curveChannel, histogram: model.histogram)
                    .id(model.curveChannel)
                    .frame(width: side, height: side)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
