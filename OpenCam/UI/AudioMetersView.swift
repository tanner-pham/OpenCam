import SwiftUI

/// Stereo level meters, left over right.
struct AudioMetersView: View {
    let levels: [Double]
    var width: CGFloat? = Theme.Size.meterWidth

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                HStack(spacing: Theme.Space.xs) {
                    Text(index == 0 ? "L" : "R")
                        .font(Theme.Text.caption)
                        .foregroundStyle(.secondary)
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(LinearGradient(colors: [.green, .green, .yellow, Theme.recordRed], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * level)
                            }
                        }
                        .frame(height: Theme.Space.s - 2)
                }
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio levels")
    }
}
