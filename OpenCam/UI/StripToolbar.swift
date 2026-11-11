import SwiftUI

/// The three strip controls as native toolbar items, so the system draws them in the side strip. Record settings is not
/// one of them: the format button opens it.
/// Each item's content is a `StripControl` view: the model is read in that view's body, which SwiftUI tracks, and not in
/// this toolbar content's body, which it does not re-run when the model changes.
struct StripToolbar: ToolbarContent {
    let model: CameraModel
    let library: LibraryStore?
    let isLandscape: Bool

    enum Item: CaseIterable { case mode, lens, library }

    /// Horizontal: mode sits at the bottom of the strip, so it is declared last.
    private var items: [Item] { isLandscape ? Item.allCases.reversed() : Item.allCases }

    var body: some ToolbarContent {
        ForEach(items, id: \.self) { item in
            ToolbarItem(placement: .bottomBar) {
                StripControl(item: item, model: model, library: library)
            }
            .axisBehavior(.verticalPreferred)
        }
    }
}
