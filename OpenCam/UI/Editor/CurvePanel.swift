import SwiftUI

/// The Curve group: the channel picker and Reset, over a square canvas of that channel's curve on the picture's histogram.
/// The canvas is outside any scroll view, so a vertical drag on it moves a point and never the panel.
struct CurvePanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        // The picker row keeps its own height, which grows with the text size; the canvas is the largest square in what is left.
        // Its plot's own 12 pt inset is the gap under the row, so no spacing is added here.
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                Picker("Curve channel", selection: $model.curveChannel) {
                    ForEach(CurveChannel.allCases, id: \.self) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .frame(minHeight: Theme.Size.minTarget)
                Button("Reset") { model.resetCurve(model.curveChannel) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minHeight: Theme.Size.minTarget)
                    .disabled(model.adjustments.curves[model.curveChannel].isIdentity)
            }
            // Every point edit writes the edit's curve for this channel, so it renders through the coalescer like a slider.
            // A new channel is a new canvas, so a touch under way never writes into another channel's curve.
            CurveCanvas(curve: $model.adjustments.curves[model.curveChannel], channel: model.curveChannel, histogram: model.histogram)
                .id(model.curveChannel)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
    }
}
