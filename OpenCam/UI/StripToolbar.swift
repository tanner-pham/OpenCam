import SwiftUI

/// The four strip controls as native toolbar items, so the system draws them in the side strip.
struct StripToolbar: ToolbarContent {
    @Bindable var model: CameraModel
    let isLandscape: Bool

    private enum Item: CaseIterable { case mode, lens, record, library }

    /// Horizontal: mode sits at the bottom of the strip, so it is declared last.
    private var items: [Item] { isLandscape ? Item.allCases.reversed() : Item.allCases }

    var body: some ToolbarContent {
        ForEach(items, id: \.self) { item in
            ToolbarItem(placement: .bottomBar) {
                control(item)
            }
            .axisBehavior(.verticalPreferred)
        }
    }

    @ViewBuilder
    private func control(_ item: Item) -> some View {
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
        case .lens:
            Menu {
                Picker("Lens", selection: Binding(get: { model.lensID }, set: { model.selectLens($0) })) {
                    ForEach(model.lenses) { Text($0.label).tag($0.id) }
                }
            } label: {
                Text(model.currentLens?.label ?? "Lens")
            }
            .accessibilityLabel("Lens, \(model.currentLens?.label ?? "none")")
        case .record:
            Button("Record settings", systemImage: "slider.horizontal.3") { model.sheet = .record }
        case .library:
            Button("Library", systemImage: "photo.on.rectangle") {}
                .disabled(true)
        }
    }
}
