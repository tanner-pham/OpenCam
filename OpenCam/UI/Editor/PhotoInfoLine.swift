import SwiftUI

/// One line under the picture: the format, lens and exposure. Tapping it opens the full "Photo info" list in a sheet.
struct PhotoInfoLine: View {
    let designation: FormatDesignation?
    let facts: PhotoFacts

    /// The line's height at the default text size; it grows with the text size, so the footnote never overflows it. The editor
    /// scales the same value relative to the same style when it subtracts the line from the picture's height.
    static let baseHeight: CGFloat = 36

    @ScaledMetric(relativeTo: .footnote) private var height = PhotoInfoLine.baseHeight
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
                .frame(maxWidth: .infinity, minHeight: height)
                .contentShape(Rectangle().inset(by: -max(0, Theme.Size.minTarget - height) / 2))
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .accessibilityLabel("Photo info")
        .accessibilityValue(facts.summary(designation))
        .sheet(isPresented: $isShowingInfo) { info }
    }

    /// Large, because the medium detent and a popover cut off rows on the folded display.
    private var info: some View {
        NavigationStack {
            List(facts.rows(designation), id: \.title) { row in
                LabeledContent(row.title, value: row.value)
            }
            .navigationTitle("Photo info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingInfo = false }
                }
            }
        }
        .presentationDetents([.large])
    }
}
