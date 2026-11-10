import SwiftUI

/// The Library's navigation destination for a photo. It owns the editor's model, so the model survives the destination being
/// rebuilt and is released, with its proxy and preview, when the editor leaves the navigation stack.
struct EditorScreen: View {
    @State private var model: EditorModel
    let onDone: () -> Void

    init(item: LibraryItem, library: LibraryStore, group: EditorGroup, onDone: @escaping () -> Void) {
        _model = State(initialValue: EditorModel(item: item, edits: library.edits, looks: library.lookStore, group: group))
        self.onDone = onDone
    }

    var body: some View {
        EditorView(model: model, onDone: onDone)
    }
}
