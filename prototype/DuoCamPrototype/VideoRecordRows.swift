import SwiftUI

/// Codec, quality, resolution, frame rate and colour, top to bottom. Each row filters the rows below it.
struct VideoRecordRows: View {
    let model: CaptureModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let rate = model.capabilities.gbPerMinute(for: model.record)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(RecordRow.allCases, id: \.self) { row in
                    ChipRow(title: row.title,
                            chips: model.capabilities.chips(row, for: model.record),
                            selectedID: model.selectedID(row),
                            columns: row.columns(isWide: verticalSizeClass == .compact)) { model.select(row, id: $0) }
                }
                Text("About \(rate.formatted(.number.precision(.fractionLength(1)))) GB per minute. \(model.capabilities.minutesLeft(for: model.record)) min left.")
                    .font(.footnote.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, verticalSizeClass == .compact ? 0 : Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
        }
    }
}
