import SwiftUI

/// The Library's navigation destination for a photo. It owns the editor's model, so the model survives the destination being
/// rebuilt and is released, with its proxy and preview, when the editor leaves the navigation stack.
struct EditorScreen: View {
    @State private var model: EditorModel
    let onDone: () -> Void

    /// `lookName` names a saved look the editor applies, unsaved, once the photo has loaded (the `-editorLook` launch push).
    init(item: LibraryItem, library: LibraryStore, group: EditorGroup, lookName: String? = nil, onDone: @escaping () -> Void) {
        _model = State(initialValue: EditorModel(item: item, edits: library.edits, looks: library.lookStore, group: group,
                                                 launchLook: lookName))
        self.onDone = onDone
    }

    var body: some View {
        EditorView(model: model, onDone: onDone)
    }
}
