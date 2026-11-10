import SwiftUI

/// Eight vertical bars (white, yellow, cyan, green, magenta, red, blue, black) over a grey ramp in the bottom quarter.
struct ColourBarsPattern: View {
    private let bars: [Color] = [
        .init(red: 1, green: 1, blue: 1), .init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1), .init(red: 0, green: 1, blue: 0),
        .init(red: 1, green: 0, blue: 1), .init(red: 1, green: 0, blue: 0), .init(red: 0, green: 0, blue: 1), .init(red: 0, green: 0, blue: 0),
    ]

    var body: some View {
        Canvas { context, size in
            let barHeight = size.height * 0.75
            let barWidth = size.width / CGFloat(bars.count)
            for (index, colour) in bars.enumerated() {
                context.fill(Path(CGRect(x: CGFloat(index) * barWidth, y: 0, width: barWidth + 1, height: barHeight)), with: .color(colour))
            }
            context.fill(Path(CGRect(x: 0, y: barHeight, width: size.width, height: size.height - barHeight)),
                         with: .linearGradient(Gradient(colors: [.black, .white]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
        }
    }
}
