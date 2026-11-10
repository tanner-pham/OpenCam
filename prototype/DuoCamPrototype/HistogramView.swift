import SwiftUI

struct HistogramView: View {
    var body: some View {
        Canvas { context, size in
            let count = 32
            let barWidth = size.width / CGFloat(count)
            for i in 0..<count {
                let x = Double(i) / Double(count - 1)
                let level = 0.15 + 0.85 * (0.7 * exp(-pow((x - 0.35) * 3.2, 2)) + 0.45 * exp(-pow((x - 0.8) * 5, 2)))
                let height = size.height * level
                context.fill(Path(CGRect(x: CGFloat(i) * barWidth, y: size.height - height, width: barWidth - 1, height: height)),
                             with: .color(.white.opacity(0.75)))
            }
        }
        .frame(width: Theme.Size.histogramWidth, height: Theme.Size.histogramHeight)
        .accessibilityLabel("Histogram")
    }
}
