import SwiftUI

/// Codec, quality, resolution, frame rate and colour, top to bottom. Each row filters the rows below it.
struct VideoRecordRows: View {
    let resolver: RecordSelectionResolver
    @Binding var selection: RecordSelection
    let freeBytes: Int64
    let look: LookChoice
    let drop: DropChoice
    var sweepCaption: String? = nil
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(RecordRow.allCases, id: \.self) { row in
                    // Worked out once per row; the reason line is the first dimmed chip's reason (`reasonLine`).
                    let chips = RecordRowText.chips(row, from: resolver.chips(row, for: selection, freeBytes: freeBytes))
                    ChipRow(title: row.title,
                            chips: chips,
                            selectedID: selectedID(row),
                            reason: RecordRowText.line(row, chips: chips, selection: selection),
                            columns: row.columns(isWide: verticalSizeClass == .compact)) { chipID in
                        if let changed = resolver.select(row, chipID: chipID, in: selection) { selection = changed }
                    }
                }
                ChipRow(title: "Look", chips: look.chips, selectedID: look.selectedID, reason: look.reason, columns: 1,
                        isSingleLine: true, onSelect: look.onSelect)
                ChipRow(title: DropPolicy.rowTitle, chips: drop.chips, selectedID: drop.selectedID, reason: drop.reason, columns: 2,
                        onSelect: drop.onSelect)
                if let option = resolver.option(for: selection) {
                    Text(DataRateEstimator.footer(for: option, freeBytes: freeBytes))
                        .font(.footnote.monospacedDigit())
                }
                if let sweepCaption {
                    Text(sweepCaption)
                        .font(.footnote)
                        .foregroundStyle(Theme.recordRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, verticalSizeClass == .compact ? 0 : Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
        }
        .defaultScrollAnchor(look.scrollsIntoView ? .bottom : .top, for: .initialOffset)
    }

    private func selectedID(_ row: RecordRow) -> String {
        switch row {
        case .codec: selection.family.rawValue
        case .quality: selection.quality
        case .resolution: selection.resolution.id
        case .frameRate: String(selection.frameRate)
        case .colour: selection.colour.rawValue
        }
    }
}
