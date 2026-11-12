import SwiftUI

/// One grading region's wheel, as wide as the panel: its name and "<hue>° · <saturation>" on a row like a slider's, a centred disc
/// of every hue that whitens to the centre with a puck at the region's hue and saturation, and the region's luminance slider
/// below, as wide as Blending and Balance. The colour drawn under the puck is the colour the region adds. A touch on the disc
/// takes the puck to the finger and a drag moves it; a double tap takes it back to the centre. The drag wins over the panel's
/// scroll view, so a vertical drag that starts on the disc moves the puck, never the panel.
struct ColourWheel: View {
    let region: GradingRegion
    @Bindable var model: EditorModel
    let diameter: CGFloat

    private static let puckDiameter: CGFloat = 16
    private static let ringWidth: CGFloat = 2
    /// Every 30° of hue at full saturation, from 0 at the right; y points down, so the conic gradient runs clockwise on screen
    /// as `WheelGeometry` does.
    private static let hues = Gradient(colors: stride(from: 0, through: 360, by: 30).map { colour(hue: Double($0), saturation: 100) })

    private var hue: Double { model.adjustments[region.hueKey] }
    private var saturation: Double { model.adjustments[region.saturationKey] }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            titleRow
            disc
                // The luminance slider's reset target reaches up over the gap above its name row; the padding keeps it off the disc.
                .padding(.bottom, AdjustmentSlider.reachUp - Theme.Space.s)
            AdjustmentSlider(key: region.luminanceKey, value: $model.adjustments[region.luminanceKey], title: "Luminance") {
                model.reset(region.luminanceKey)
            }
        }
    }

    /// The name at the leading edge and the readout at the trailing one, as a slider's name and value are. When the two do not
    /// fit one row at full size (the longest pair at accessibility text sizes) the readout goes under the name, and either may
    /// wrap rather than be cut or shrunk.
    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(region.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                readout
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: 0) {
                Text(region.title)
                readout
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        // The disc's sliders say the same.
        .accessibilityHidden(true)
    }

    private var readout: some View {
        Text("\(region.hueKey.valueText(hue)) · \(region.saturationKey.valueText(saturation))")
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private var disc: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let centre = CGPoint(x: bounds.midX, y: bounds.midY)
            let disc = Path(ellipseIn: bounds)
            context.fill(disc, with: .conicGradient(Self.hues, center: centre))
            // White at the centre to clear at the rim: the colour at a point is the hue at that point's saturation.
            context.fill(disc, with: .radialGradient(Gradient(colors: [.white, .white.opacity(0)]), center: centre,
                                                     startRadius: 0, endRadius: min(size.width, size.height) / 2))
        }
        .frame(width: diameter, height: diameter)
        .overlay { puck }
        .contentShape(.circle)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                let tint = WheelGeometry.tint(at: value.location, diameter: diameter)
                model.setWheel(region, hue: tint.hue, saturation: tint.saturation)
            }
        )
        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in model.resetWheel(region) })
        .accessibilityRepresentation {
            Slider(value: $model.adjustments[region.hueKey], in: region.hueKey.range, step: region.hueKey.step) {
                Text(region.hueKey.title)
            }
            .accessibilityValue(region.hueKey.valueText(hue))
            .accessibilityAdjustableAction { direction in
                model.adjustments[region.hueKey] = WheelGeometry.steppedHue(hue, steps: direction.steps)
            }
            .accessibilityAction(named: "Reset") { model.resetWheel(region) }
            Slider(value: $model.adjustments[region.saturationKey], in: region.saturationKey.range, step: region.saturationKey.step) {
                Text(region.saturationKey.title)
            }
            .accessibilityValue(region.saturationKey.valueText(saturation))
            .accessibilityAdjustableAction { direction in
                model.adjustments[region.saturationKey] = WheelGeometry.steppedSaturation(saturation, steps: direction.steps)
            }
            .accessibilityAction(named: "Reset") { model.resetWheel(region) }
        }
    }

    /// Filled with the colour under it, in a white ring with a dark edge so it stands apart on the white centre too. Drawn over
    /// the disc's frame, so a puck on the rim is never cut.
    private var puck: some View {
        ZStack {
            Circle().fill(Self.colour(hue: hue, saturation: saturation))
            Circle().strokeBorder(.white, lineWidth: Self.ringWidth)
            Circle().stroke(.black.opacity(0.6), lineWidth: 1)
        }
        .frame(width: Self.puckDiameter, height: Self.puckDiameter)
        .position(WheelGeometry.point(hue: hue, saturation: saturation, diameter: diameter))
        .allowsHitTesting(false)
    }

    /// The Display P3 colour of a hue (degrees) at a saturation of 0...100 and full value.
    private static func colour(hue: Double, saturation: Double) -> Color {
        let rgb = ColourMath.rgb(hue: Float(hue), saturation: Float(saturation / 100), value: 1)
        return Color(.displayP3, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

private extension AccessibilityAdjustmentDirection {
    /// +1 for an increment, -1 for a decrement.
    var steps: Int {
        switch self {
        case .increment: 1
        case .decrement: -1
        @unknown default: 0
        }
    }
}
