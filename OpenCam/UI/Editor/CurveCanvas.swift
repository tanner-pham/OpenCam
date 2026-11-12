import SwiftUI

/// One channel's curve over the picture's histogram, edited by touch (a finger or Pencil, through the same drag): a touch on
/// the line adds a point there without changing the picture, a point drags between its neighbours, an inner point dragged
/// well off the plot is removed on release (drawn faded until then), and a double tap removes a point. The end points clamp
/// at the plot's edge and are never removed.
struct CurveCanvas: View {
    @Binding var curve: ToneCurve
    let channel: CurveChannel
    let histogram: PictureHistogram?

    /// The touch under way; nil when there is none, when it began on nothing, or after a double tap removed its point.
    @State private var drag: CurveDrag?
    /// Where the touch has taken the dragged point, unclamped.
    @State private var target: CurvePoint?
    /// True from a touch's first change until it ends, so each touch begins at most one drag.
    @State private var isTouchBegun = false
    /// Resets when a touch ends or is cancelled; a cancelled touch never calls `onEnded`.
    @GestureState private var isTouching = false

    private static let pointDiameter: CGFloat = 10
    private static let curveWidth: CGFloat = 2
    /// The curve is drawn as straight pieces this far apart across the plot.
    private static let sampleStep: CGFloat = 2
    private static let removingOpacity = 0.35

    var body: some View {
        GeometryReader { geo in
            let geometry = CurveGeometry(side: min(geo.size.width, geo.size.height))
            Canvas { context, _ in draw(in: &context, geometry) }
                .contentShape(.rect)
                .highPriorityGesture(dragGesture(geometry))
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { removePoint(at: $0.location, geometry) })
        }
        .onChange(of: isTouching) { _, isNowTouching in
            if !isNowTouching { endTouch() }
        }
        .accessibilityElement()
        .accessibilityLabel("\(channel.title) curve")
        // A curve always keeps its two end points, so the count is never 1.
        .accessibilityValue("\(curve.points.count) points")
        // Offered only while there is something to reset, as the visible Reset is.
        .accessibilityActions {
            if !curve.isIdentity { Button("Reset") { curve = .identity } }
        }
    }

    // MARK: - Touch

    private func dragGesture(_ geometry: CurveGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, isTouching, _ in isTouching = true }
            .onChanged { value in
                if !isTouchBegun {
                    isTouchBegun = true
                    drag = CurveDrag.begin(on: curve, at: geometry.curvePoint(value.startLocation), radius: geometry.hitRadius)
                }
                follow(value, geometry)
            }
            .onEnded { value in
                follow(value, geometry)
                endTouch()
            }
    }

    /// Works the curve out from the drag's original each time, so it never drifts from the finger.
    private func follow(_ value: DragGesture.Value, _ geometry: CurveGeometry) {
        guard let drag else { return }
        let start = geometry.curvePoint(value.startLocation), now = geometry.curvePoint(value.location)
        let translation = CurvePoint(x: now.x - start.x, y: now.y - start.y)
        target = drag.target(translation: translation)
        let edited = drag.curve(translation: translation, margin: geometry.removeMargin)
        if edited != curve { curve = edited }
    }

    private func endTouch() {
        drag = nil
        target = nil
        isTouchBegun = false
    }

    private func removePoint(at location: CGPoint, _ geometry: CurveGeometry) {
        guard case .point(let index) = curve.hit(geometry.curvePoint(location), radius: geometry.hitRadius) else { return }
        // The touch this tap ends must not put the point back when its own end arrives.
        drag = nil
        target = nil
        curve = curve.removing(index)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, _ geometry: CurveGeometry) {
        let topLeft = geometry.viewPoint(CurvePoint(x: 0, y: 1)), bottomRight = geometry.viewPoint(CurvePoint(x: 1, y: 0))
        let plot = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        guard plot.width > Self.pointDiameter else { return }
        context.fill(Path(plot), with: .style(.quaternary))
        drawGrid(in: &context, geometry)
        if let histogram { drawHistogram(histogram, in: &context, geometry) }
        var diagonal = Path()
        diagonal.move(to: geometry.viewPoint(CurvePoint(x: 0, y: 0)))
        diagonal.addLine(to: geometry.viewPoint(CurvePoint(x: 1, y: 1)))
        context.stroke(diagonal, with: .style(.tertiary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        context.stroke(curvePath(geometry, width: plot.width), with: curveShading,
                       style: StrokeStyle(lineWidth: Self.curveWidth, lineCap: .round, lineJoin: .round))
        drawPoints(in: &context, geometry)
    }

    private func drawGrid(in context: inout GraphicsContext, _ geometry: CurveGeometry) {
        var grid = Path()
        for quarter in [0.25, 0.5, 0.75] {
            grid.move(to: geometry.viewPoint(CurvePoint(x: quarter, y: 0)))
            grid.addLine(to: geometry.viewPoint(CurvePoint(x: quarter, y: 1)))
            grid.move(to: geometry.viewPoint(CurvePoint(x: 0, y: quarter)))
            grid.addLine(to: geometry.viewPoint(CurvePoint(x: 1, y: quarter)))
        }
        context.stroke(grid, with: .style(.tertiary), lineWidth: 0.5)
    }

    /// RGB: luma in white, with red, green and blue added over it; a colour channel: its own bins only.
    private func drawHistogram(_ histogram: PictureHistogram, in context: inout GraphicsContext, _ geometry: CurveGeometry) {
        func area(_ channel: HistogramChannel) -> Path {
            let heights = histogram.heights(channel)
            let last = Double(max(heights.count - 1, 1))
            var path = Path()
            path.move(to: geometry.viewPoint(CurvePoint(x: 0, y: 0)))
            for (bin, height) in heights.enumerated() {
                path.addLine(to: geometry.viewPoint(CurvePoint(x: Double(bin) / last, y: height)))
            }
            path.addLine(to: geometry.viewPoint(CurvePoint(x: 1, y: 0)))
            path.closeSubpath()
            return path
        }
        var added = context
        added.blendMode = .plusLighter
        switch channel {
        case .master:
            context.fill(area(.luma), with: .color(.white.opacity(0.25)))
            added.fill(area(.red), with: .color(.red.opacity(0.3)))
            added.fill(area(.green), with: .color(.green.opacity(0.3)))
            added.fill(area(.blue), with: .color(.blue.opacity(0.3)))
        case .red: added.fill(area(.red), with: .color(.red.opacity(0.3)))
        case .green: added.fill(area(.green), with: .color(.green.opacity(0.3)))
        case .blue: added.fill(area(.blue), with: .color(.blue.opacity(0.3)))
        }
    }

    private func curvePath(_ geometry: CurveGeometry, width: CGFloat) -> Path {
        let steps = Int((width / Self.sampleStep).rounded(.up))
        var path = Path()
        for step in 0...steps {
            let x = min(1, Double(CGFloat(step) * Self.sampleStep / width))
            let point = geometry.viewPoint(CurvePoint(x: x, y: Double(curve.value(at: Float(x)))))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The dragged point in the accent colour; while it would be removed it is drawn faded where the finger has taken it, kept
    /// on the canvas.
    private func drawPoints(in context: inout GraphicsContext, _ geometry: CurveGeometry) {
        let isRemoving = drag.map { curve.points.count < $0.original.points.count } ?? false
        for (index, point) in curve.points.enumerated() {
            let isDragged = !isRemoving && drag?.index == index
            drawPoint(at: geometry.viewPoint(point), shading: isDragged ? .color(Theme.accent) : curveShading, in: &context)
        }
        guard isRemoving, let target else { return }
        let radius = Self.pointDiameter / 2
        let finger = geometry.viewPoint(target)
        let kept = CGPoint(x: min(max(finger.x, radius), geometry.side - radius), y: min(max(finger.y, radius), geometry.side - radius))
        var faded = context
        faded.opacity = Self.removingOpacity
        drawPoint(at: kept, shading: .color(Theme.accent), in: &faded)
    }

    /// A dark ring keeps a point apart from the line through it and from the histogram.
    private func drawPoint(at center: CGPoint, shading: GraphicsContext.Shading, in context: inout GraphicsContext) {
        let radius = Self.pointDiameter / 2
        let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: Self.pointDiameter, height: Self.pointDiameter))
        context.fill(dot, with: shading)
        context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1)
    }

    private var curveShading: GraphicsContext.Shading {
        switch channel {
        case .master: .style(.primary)
        case .red: .color(.red)
        case .green: .color(.green)
        case .blue: .color(.blue)
        }
    }
}
