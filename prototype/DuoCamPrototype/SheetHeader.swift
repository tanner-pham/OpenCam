import SwiftUI

/// Section header pulled left so it shares the sheet title's leading edge.
struct SheetHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).padding(.leading, -Theme.Size.sectionHeaderInset)
    }
}
