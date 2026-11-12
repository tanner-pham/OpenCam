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
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tint(tint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        if isSelected { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}
