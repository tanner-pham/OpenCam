import SwiftUI

/// The strip's controls as native toolbar items, so the system draws them in the side strip: Mode, Lens and Library, or,
/// while a control is open, its slider, Auto and a close item. Record settings is not one of them: the format button opens it.
/// Each item's content is a `StripControl` view: the model is read in that view's body, which SwiftUI tracks, and not in
/// this toolbar content's body, which it does not re-run when the model changes. Which items show is decided by
/// `StripToolbarModifier` and passed in.
struct StripToolbar: ToolbarContent {
    let model: CameraModel
    let library: LibraryStore?
    let items: [Item]

    enum Item: Hashable { case mode, lens, library, slider, auto, close }

    /// Horizontal: the first item sits at the bottom of the strip, so the list is declared in reverse. EV has no Auto.
    static func items(open: ManualControl?, isLandscape: Bool) -> [Item] {
        let items: [Item]
        if let open {
            items = open.hasAutomatic ? [.slider, .auto, .close] : [.slider, .close]
        } else {
            items = [.mode, .lens, .library]
        }
        return isLandscape ? items.reversed() : items
    }

    var body: some ToolbarContent {
        ForEach(items, id: \.self) { item in
            ToolbarItem(placement: .bottomBar) {
                StripControl(item: item, model: model, library: library)
            }
            .axisBehavior(.verticalPreferred)
        }
    }
}
