import SwiftUI

/// One strip control. Its label, icon and enabled state are read from the model here, in a view body, so they follow every
/// change of mode, lens and availability.
struct StripControl: View {
    let item: StripToolbar.Item
    let model: CameraModel
    let library: LibraryStore?

    var body: some View {
        switch item {
        case .mode:
            // Two modes, so one tap switches between them; the symbol is the mode in use.
            Button { model.toggleMode() } label: {
                Image(systemName: model.mode == .video ? "video.fill" : "camera.fill")
            }
            .accessibilityLabel("Mode")
            .accessibilityValue(model.mode == .video ? "Video" : "Photo")
            .accessibilityHint(model.mode == .video ? "Switches to photo." : "Switches to video.")
            .disabled(!model.canChangeLensOrMode)
        case .lens:
            // Every lens the scan found, in its order, each with a short title and a symbol.
            let current = model.currentLens.map(LensBadge.make(for:))
            Menu {
                Picker("Lens", selection: Binding(get: { model.lensID }, set: { model.selectLens($0) })) {
                    ForEach(model.lenses) { lens in
                        let badge = LensBadge.make(for: lens)
                        Label(badge.rowTitle, systemImage: badge.symbol ?? LensBadge.backLensSymbol).tag(lens.id)
                    }
                }
            } label: {
                if let symbol = current?.symbol {
                    Image(systemName: symbol)
                } else {
                    Text(current?.shortText ?? "Lens")
                }
            }
            .accessibilityLabel("Lens, \(current?.rowTitle ?? "none")")
            .disabled(!model.canChangeLensOrMode)
        case .library:
            LibraryThumbnail(model: model, library: library)
        case .slider:
            // Clear of the pill's rounded end, which the thumb and the track would otherwise touch at either extreme.
            ControlSlider(model: model)
                .padding(.vertical, Theme.Space.xs)
        case .auto:
            ControlAutoButton(model: model)
        case .close:
            ControlCloseButton(model: model)
        }
    }
}
