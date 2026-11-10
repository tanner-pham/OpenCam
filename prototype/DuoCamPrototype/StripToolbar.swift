import SwiftUI

/// The five strip controls as native toolbar items, so the system draws them in the side strip.
struct StripToolbar: ToolbarContent {
    @Bindable var model: CaptureModel
    let isLandscape: Bool

    private enum Item: CaseIterable { case mode, lens, record, monitor, library }

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
                Picker("Lens", selection: $model.lens) {
                    ForEach(Lens.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Text(model.lens.shortName)
            }
            .accessibilityLabel("Lens, \(model.lens.rawValue)")
        case .record:
            Button("Record settings", systemImage: "slider.horizontal.3") { model.sheet = .record }
        case .monitor:
            Button("Monitor tools", systemImage: "scope") { model.sheet = .monitor }
        case .library:
            Button { } label: {
                RoundedRectangle(cornerRadius: Theme.Space.s)
                    .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.3, blue: 0.9), Color(red: 1, green: 0.62, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Library")
        }
    }
}
