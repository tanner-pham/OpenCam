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
            Menu {
                Picker("Lens", selection: Binding(get: { model.lensID }, set: { model.selectLens($0) })) {
                    ForEach(model.lenses) { Text($0.label).tag($0.id) }
                }
            } label: {
                Text(model.currentLens?.label ?? "Lens")
            }
            .accessibilityLabel("Lens, \(model.currentLens?.label ?? "none")")
            .disabled(!model.canChangeLensOrMode)
        case .library:
            LibraryThumbnail(model: model, library: library)
        }
    }
}
