import SwiftUI

/// The selected linear or radial mask drawn on the fitted picture, with a handle on each of its points. Sized by the picture
/// it overlays. Each move of a handle writes through `updateSelectedMask`, so a drag is one undo step.
struct MaskHandles: View {
    @Bindable var model: EditorModel

    private static let space = "maskHandles"

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch model.selectedMask?.shape {
                case let .linear(start, end):
                    linear(start: start, end: end, in: size)
                case let .radial(centre, radius, feather):
                    radial(centre: centre, radius: radius, feather: feather, in: size)
                default:
                    EmptyView()
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(.named(Self.space))
        }
    }

    // MARK: Linear

    @ViewBuilder
    private func linear(start: MaskPoint, end: MaskPoint, in size: CGSize) -> some View {
        let from = MaskGeometry.location(start, in: size), to = MaskGeometry.location(end, in: size)
        MaskLines { path in
            let dx = to.x - from.x, dy = to.y - from.y
            let length = hypot(dx, dy)
            guard length > 0.5 else { return }
            // A perpendicular long enough to cross the picture from any point on it.
            let reach = hypot(size.width, size.height) * 2
            let nx = -dy / length * reach, ny = dx / length * reach
            for point in [from, to] {
                path.move(to: CGPoint(x: point.x - nx, y: point.y - ny))
                path.addLine(to: CGPoint(x: point.x + nx, y: point.y + ny))
            }
        }
        MaskHandle(position: from, label: "Mask start", space: Self.space) { location in
            let point = MaskGeometry.point(location, in: size)
            model.updateSelectedMask { mask in
                if case let .linear(_, end) = mask.shape { mask.shape = .linear(start: point, end: end) }
            }
        }
        MaskHandle(position: to, label: "Mask end", space: Self.space) { location in
            let point = MaskGeometry.point(location, in: size)
            model.updateSelectedMask { mask in
                if case let .linear(start, _) = mask.shape { mask.shape = .linear(start: start, end: point) }
            }
        }
    }

    // MARK: Radial

    @ViewBuilder
    private func radial(centre: MaskPoint, radius: Double, feather: Double, in size: CGSize) -> some View {
        let middle = MaskGeometry.location(centre, in: size)
        let short = min(size.width, size.height)
        let outer = CGFloat(radius.isFinite ? min(max(radius, 0), 4) : 0) * short
        let inner = outer * CGFloat(1 - (feather.isFinite ? min(max(feather, 0), 1) : 0))
        MaskLines(dash: []) { $0.addEllipse(in: CGRect(x: middle.x - outer, y: middle.y - outer, width: 2 * outer, height: 2 * outer)) }
        MaskLines(dash: [6, 5]) { $0.addEllipse(in: CGRect(x: middle.x - inner, y: middle.y - inner, width: 2 * inner, height: 2 * inner)) }
        MaskHandle(position: middle, label: "Mask centre", space: Self.space) { location in
            let point = MaskGeometry.point(location, in: size)
            model.updateSelectedMask { mask in
                if case let .radial(_, radius, feather) = mask.shape { mask.shape = .radial(centre: point, radius: radius, feather: feather) }
            }
        }
        // On the right of the circle, held inside the picture so a large circle's handle can still be reached.
        MaskHandle(position: CGPoint(x: min(max(middle.x + outer, 0), size.width), y: middle.y), label: "Mask size", space: Self.space) { location in
            let point = MaskGeometry.point(location, in: size)
            model.updateSelectedMask { mask in
                if case let .radial(centre, _, feather) = mask.shape {
                    mask.shape = .radial(centre: centre, radius: max(MaskGeometry.radius(from: centre, to: point, in: size), 0.01), feather: feather)
                }
            }
        }
    }
}

/// A white line or circle with a faint dark shadow, so it reads on a bright sky. Not hit-testable.
private struct MaskLines: View {
    var dash: [CGFloat] = []
    let draw: (inout Path) -> Void

    init(dash: [CGFloat] = [], draw: @escaping (inout Path) -> Void) {
        self.dash = dash
        self.draw = draw
    }

    var body: some View {
        var path = Path()
        draw(&path)
        return path
            .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: dash))
            .shadow(color: .black.opacity(0.4), radius: 1.5)
            // Lines stop at the picture's edge; handles are not clipped, so one on the edge stays whole.
            .clipped()
            .allowsHitTesting(false)
    }
}

/// One draggable point: the puck of the colour wheel, 14 pt drawn inside a 44 pt hit area. It keeps the finger's offset from
/// the point it grabbed, so the point does not jump to the finger.
private struct MaskHandle: View {
    let position: CGPoint
    let label: String
    let space: String
    let onMove: (CGPoint) -> Void

    @State private var grab: CGSize?

    private static let diameter: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(.clear)
            Circle().strokeBorder(.white, lineWidth: 2)
            Circle().stroke(.black.opacity(0.6), lineWidth: 1)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .shadow(color: .black.opacity(0.3), radius: 1.5)
        .frame(width: 44, height: 44)
        .contentShape(.circle)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                .onChanged { value in
                    let offset = grab ?? CGSize(width: position.x - value.startLocation.x, height: position.y - value.startLocation.y)
                    grab = offset
                    onMove(CGPoint(x: value.location.x + offset.width, y: value.location.y + offset.height))
                }
                .onEnded { _ in grab = nil }
        )
        .position(position)
        .accessibilityLabel(label)
    }
}
