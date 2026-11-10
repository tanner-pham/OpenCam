import SwiftUI

/// The Library's bottom bar in Select mode: Apply look (every look, then Remove look) and Delete, both icon-only in the strip.
struct LibrarySelectionBar: ToolbarContent {
    let count: Int
    let looks: [Look]
    let onApply: (Look) -> Void
    let onRemoveLook: () -> Void
    let onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Menu {
                ForEach(looks) { look in
                    Button(look.name) { onApply(look) }
                }
                Divider()
                Button("Remove look", role: .destructive, action: onRemoveLook)
            } label: {
                Label("Apply look", systemImage: "camera.filters")
            }
            .labelStyle(.iconOnly)
            .disabled(count == 0)
        }
        .axisBehavior(.verticalPreferred)
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .tint(.red)
                .disabled(count == 0)
        }
        .axisBehavior(.verticalPreferred)
    }
}
