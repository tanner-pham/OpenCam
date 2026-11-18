import SwiftUI

/// One line under the picture: the format, lens and exposure. Tapping it opens the full "Photo info" list in a sheet.
struct PhotoInfoLine: View {
    let designation: FormatDesignation?
    let facts: PhotoFacts

    /// The line's height at the default text size; see `InfoLine`.
    static let baseHeight = InfoLine.baseHeight

    var body: some View {
        InfoLine(title: "Photo info", summary: facts.summary(designation), rows: facts.rows(designation))
    }
}
