import SwiftUI

/// Up to three small thumbnails drawn as a loose stack: the newest on top and upright, the ones beneath turned
/// by -8 and +6 degrees and offset by a couple of points, each with a thin light edge. One capture draws one thumbnail.
/// The stack keeps to the `side` square: with more than one capture the cards are smaller, so the turned ones stay inside it.
struct ThumbnailStack: View {
    static let side: CGFloat = 30
    private static let stackedSide: CGFloat = 24
    /// Turn and offset of the cards beneath the newest, in order.
    private static let beneath: [(degrees: Double, x: CGFloat, y: CGFloat)] = [(-8, -2, 1), (6, 2, -1)]

    let thumbnails: [CGImage]

    var body: some View {
        let shown = Array(thumbnails.prefix(1 + Self.beneath.count))
        let cardSide = shown.count > 1 ? Self.stackedSide : Self.side
        ZStack {
            // The newest is drawn last, so it sits on top.
            ForEach(Array(shown.enumerated()).reversed(), id: \.offset) { index, image in
                let placement = index == 0 ? (degrees: 0, x: 0, y: 0) : Self.beneath[index - 1]
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cardSide, height: cardSide)
                    .clipShape(.rect(cornerRadius: Theme.Space.xs + 2))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Space.xs + 2)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 0.5)
                    }
                    .rotationEffect(.degrees(placement.degrees))
                    .offset(x: placement.x, y: placement.y)
            }
        }
        .frame(width: Self.side, height: Self.side)
    }
}
