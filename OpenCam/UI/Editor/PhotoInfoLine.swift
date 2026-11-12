import SwiftUI

/// One line under the picture: the format, lens and exposure. Tapping it opens the full "Photo info" list in a popover.
struct PhotoInfoLine: View {
    let designation: FormatDesignation?
    let facts: PhotoFacts

    static let height: CGFloat = 36

    @State private var isShowingInfo = false

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
        .sheet(isPresented: $isShowingInfo) { info }
    }

    /// A full-height sheet: the medium detent cut off the last row on the folded display, and a popover has even less room: a popover opens below the line and has too little room for seven rows and a title.
    private var info: some View {
        NavigationStack {
            List(facts.rows(designation), id: \.title) { row in
                LabeledContent(row.title, value: row.value)
            }
            .navigationTitle("Photo info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
