import SwiftUI

/// Puts the strip's items on the navigation stack's content. This modifier alone reads which control is open, and only
/// where the slider goes in the strip, so opening, switching and closing re-run it and nothing larger; the toolbar content
/// it builds takes the item list as a plain value and reads no model.
struct StripToolbarModifier: ViewModifier {
    let model: CameraModel
    let library: LibraryStore?
    let isLandscape: Bool
    @Environment(\.sliderPlacement) private var placement

    func body(content: Content) -> some View {
        let open = placement == .strip ? model.openControl : nil
        content.toolbar {
            StripToolbar(model: model, library: library, items: StripToolbar.items(open: open, isLandscape: isLandscape))
        }
    }
}
