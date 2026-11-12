import SwiftUI

/// One line under the picture: the format, lens and exposure. Tapping it opens the full "Photo info" list in a popover.
struct PhotoInfoLine: View {
    let designation: FormatDesignation?
    let facts: PhotoFacts

    static let height: CGFloat = 36

    @State private var isShowingInfo = false
    /// The list's content plus the bar and bottom inset above and below it, as the list reports it; 0 until it has.
    @State private var listHeight: CGFloat = 0

    var body: some View {
        Button { isShowingInfo = true } label: {
            Text(facts.summary(designation))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .padding(.horizontal, Theme.Space.s)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .contentShape(Rectangle().inset(by: -(Theme.Size.minTarget - Self.height) / 2))
        }
        .buttonStyle(.plain)
        .frame(height: Self.height)
        .accessibilityLabel("Photo info")
        .accessibilityValue(facts.summary(designation))
        .popover(isPresented: $isShowingInfo) { info }
    }

    /// Sized from the list's own scroll geometry, so the title and every row fit at any text size. The popover caps the
    /// height to the space it has, and the list scrolls when the content is taller.
    private var info: some View {
        let rows = facts.rows(designation)
        return NavigationStack {
            List(rows, id: \.title) { row in
                LabeledContent(row.title, value: row.value)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom } action: { _, height in
                listHeight = height
            }
            .navigationTitle("Photo info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(width: 320, height: listHeight > 0 ? listHeight : CGFloat(rows.count) * Theme.Size.minTarget + 120)
        .presentationCompactAdaptation(.popover)
    }
}
