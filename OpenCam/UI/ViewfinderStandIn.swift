import SwiftUI

/// Drawn scene standing in for the camera feed in the Simulator.
struct ViewfinderStandIn: View {
    /// Extra top inset for the caption when readouts float over the picture.
    var captionTopInset: CGFloat = 0
    /// False for the Simulator sample pictures, which have no caption.
    var showsCaption = true

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, u = min(w, h)
            let horizon = h * 0.6

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.08, green: 0.3, blue: 0.9), Color(red: 0.45, green: 0.6, blue: 0.95), Color(red: 1, green: 0.62, blue: 0.35)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

            context.fill(Path(ellipseIn: CGRect(x: w * 0.72 - u * 0.08, y: horizon - u * 0.28, width: u * 0.16, height: u * 0.16)),
                         with: .color(Color(red: 1, green: 0.92, blue: 0.4)))

            var far = Path()
            far.move(to: CGPoint(x: 0, y: horizon))
            far.addCurve(to: CGPoint(x: w * 0.55, y: horizon - u * 0.06), control1: CGPoint(x: w * 0.15, y: horizon - u * 0.22), control2: CGPoint(x: w * 0.35, y: horizon + u * 0.02))
            far.addCurve(to: CGPoint(x: w, y: horizon - u * 0.02), control1: CGPoint(x: w * 0.75, y: horizon - u * 0.2), control2: CGPoint(x: w * 0.9, y: horizon - u * 0.1))
            far.addLine(to: CGPoint(x: w, y: h))
            far.addLine(to: CGPoint(x: 0, y: h))
            context.fill(far, with: .color(Color(red: 0.08, green: 0.5, blue: 0.5)))

            var near = Path()
            near.move(to: CGPoint(x: 0, y: horizon + u * 0.12))
            near.addCurve(to: CGPoint(x: w, y: horizon + u * 0.08), control1: CGPoint(x: w * 0.3, y: horizon - u * 0.02), control2: CGPoint(x: w * 0.7, y: horizon + u * 0.25))
            near.addLine(to: CGPoint(x: w, y: h))
            near.addLine(to: CGPoint(x: 0, y: h))
            context.fill(near, with: .linearGradient(
                Gradient(colors: [Color(red: 0.25, green: 0.75, blue: 0.2), Color(red: 0.08, green: 0.4, blue: 0.15)]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

            let subject = CGPoint(x: w * 0.36, y: h * 0.8)
            context.fill(Path(roundedRect: CGRect(x: subject.x - u * 0.05, y: subject.y - u * 0.02, width: u * 0.1, height: u * 0.2), cornerRadius: u * 0.02),
                         with: .color(Color(red: 0.1, green: 0.15, blue: 0.5)))
            context.fill(Path(roundedRect: CGRect(x: subject.x - u * 0.07, y: subject.y - u * 0.2, width: u * 0.14, height: u * 0.2), cornerRadius: u * 0.05),
                         with: .color(Color(red: 0.95, green: 0.12, blue: 0.15)))
            context.fill(Path(ellipseIn: CGRect(x: subject.x - u * 0.045, y: subject.y - u * 0.31, width: u * 0.09, height: u * 0.09)),
                         with: .color(Color(red: 0.95, green: 0.72, blue: 0.55)))

            var kite = Path()
            let k = CGPoint(x: w * 0.62, y: h * 0.2)
            kite.move(to: CGPoint(x: k.x, y: k.y - u * 0.09))
            kite.addLine(to: CGPoint(x: k.x + u * 0.06, y: k.y))
            kite.addLine(to: CGPoint(x: k.x, y: k.y + u * 0.1))
            kite.addLine(to: CGPoint(x: k.x - u * 0.06, y: k.y))
            kite.closeSubpath()
            context.fill(kite, with: .color(Color(red: 1, green: 0.1, blue: 0.7)))
            var string = Path()
            string.move(to: CGPoint(x: k.x, y: k.y + u * 0.1))
            string.addQuadCurve(to: CGPoint(x: subject.x + u * 0.05, y: subject.y - u * 0.12), control: CGPoint(x: w * 0.5, y: h * 0.55))
            context.stroke(string, with: .color(.white.opacity(0.8)), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if showsCaption {
                Text("No camera in Simulator")
                    .font(.caption2)
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.vertical, Theme.Space.xs)
                    .glassEffect(.regular, in: .capsule)
                    .padding(Theme.Space.s)
                    .padding(.top, captionTopInset)
            }
        }
    }
}
