import SwiftUI

/// The Mix group: eight band buttons in two rows of four, then the chosen band's hue, saturation and luminance sliders.
struct MixPanel: View {
    @Bindable var model: EditorModel

    private static let columns = 4

    var body: some View {
        ScrollView {
            VStack(spacing: Self.rowGap) {
                bands
                ForEach(model.mixBand.keys, id: \.self) { key in
                    AdjustmentSlider(key: key, value: $model.adjustments[key]) { model.reset(key) }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private static let rowGap = EditorPanel.rowGap

    private var bands: some View {
        Grid(horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
            ForEach(0..<(ColourBand.allCases.count / Self.columns), id: \.self) { row in
                GridRow {
                    ForEach(ColourBand.allCases.dropFirst(row * Self.columns).prefix(Self.columns), id: \.self) { band in
                        bandButton(band)
                    }
                }
            }
        }
        // The first slider's reset target reaches up over the gap above its name row; the padding keeps it off the buttons.
        .padding(.bottom, AdjustmentSlider.reachUp - Self.rowGap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour band")
    }

    @ViewBuilder private func bandButton(_ band: ColourBand) -> some View {
        let isSelected = model.mixBand == band
        let tint = Color(.displayP3, red: Double(band.swatch.x), green: Double(band.swatch.y), blue: Double(band.swatch.z))
        let button = Button { model.mixBand = band } label: {
            Text(band.title)
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isSelected && band.prefersDarkLabel ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
        }
        .tint(tint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        if isSelected { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}

private extension ColourBand {
    /// Black reads better than white on the band's bright swatch when white would fall short of the other's contrast.
    var prefersDarkLabel: Bool {
        func linear(_ c: Float) -> Float { ColourMath.decode(c) }
        let s = swatch
        let luminance = 0.2126 * linear(s.x) + 0.7152 * linear(s.y) + 0.0722 * linear(s.z)
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }
}
