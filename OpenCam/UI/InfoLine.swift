import SwiftUI

/// One line under a picture or a clip: a summary of its facts. With rows, tapping it opens them in a sheet titled `title`;
/// without, it is plain secondary text.
struct InfoLine: View {
    let title: String
    let summary: String
    let rows: [PhotoInfoRow]

    /// The line's height at the default text size; it grows with the text size, so the footnote never overflows it. The editor
    /// scales the same value relative to the same style when it subtracts the line from the picture's height.
    static let baseHeight: CGFloat = 36

    @ScaledMetric(relativeTo: .footnote) private var height = InfoLine.baseHeight
    @State private var isShowingInfo = false

    var body: some View {
        if rows.isEmpty {
            label
                .frame(height: height)
                .accessibilityLabel(summary)
        } else {
            Button { isShowingInfo = true } label: {
                label
                    .contentShape(Rectangle().inset(by: -max(0, Theme.Size.minTarget - height) / 2))
            }
            .buttonStyle(.plain)
            .frame(height: height)
            .accessibilityLabel(title)
            .accessibilityValue(summary)
            .sheet(isPresented: $isShowingInfo) { info }
        }
    }

    private var label: some View {
        Text(summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: height)
    }

    /// Large, because the medium detent and a popover cut off rows on the folded display.
    private var info: some View {
        NavigationStack {
            List(rows, id: \.title) { row in
                LabeledContent(row.title, value: row.value)
            }
            .navigationTitle(title)
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
