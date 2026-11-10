import SwiftUI

/// Hue from left to right; saturation 1 at the top to 0 at the bottom.
struct HueSweepPattern: View {
    private let hues: [Color] = (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }

    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size)
            context.fill(Path(frame), with: .linearGradient(Gradient(colors: hues), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            context.fill(Path(frame), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}
