import SwiftUI

/// One strip control. Its label, icon and enabled state are read from the model here, in a view body, so they follow every
/// change of mode, lens and availability.
struct StripControl: View {
    let item: StripToolbar.Item
    @Bindable var model: CameraModel
    let library: LibraryStore?

    var body: some View {
        switch item {
        case .mode:
            Menu {
                Picker("Mode", selection: $model.mode) {
                    Text("Photo").tag(CaptureMode.photo)
                    Text("Video").tag(CaptureMode.video)
                }
            } label: {
                Image(systemName: model.mode == .video ? "video.fill" : "camera.fill")
            }
            .accessibilityLabel("Mode")
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
        case .record:
            // `canOpenRecordSettings` is false while recording and until the formats are known.
            Button("Record settings", systemImage: "slider.horizontal.3") { model.openRecordSettings() }
                .disabled(!model.canOpenRecordSettings)
        case .library:
            LibraryThumbnail(model: model, library: library)
        }
    }
}
