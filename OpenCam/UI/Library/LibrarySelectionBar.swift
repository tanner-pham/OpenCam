import SwiftUI

/// The Library's bottom bar in Select mode.
struct LibrarySelectionBar: View {
    let count: Int
    let onDelete: () -> Void

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            .labelStyle(.iconOnly)
            .tint(.red)
            .disabled(count == 0)
    }
}
