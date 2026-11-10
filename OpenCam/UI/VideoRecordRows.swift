import SwiftUI

/// Codec, quality, resolution, frame rate and colour, top to bottom. Each row filters the rows below it.
struct VideoRecordRows: View {
    let resolver: RecordSelectionResolver
    @Binding var selection: RecordSelection
    let freeBytes: Int64
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(RecordRow.allCases, id: \.self) { row in
                    ChipRow(title: row.title,
                            chips: resolver.chips(row, for: selection),
                            selectedID: selectedID(row),
                            reason: resolver.reasonLine(row, for: selection),
                            columns: row.columns(isWide: verticalSizeClass == .compact)) { chipID in
                        if let changed = resolver.select(row, chipID: chipID, in: selection) { selection = changed }
                    }
                }
                if let option = resolver.option(for: selection) {
                    Text(DataRateEstimator.footer(for: option, freeBytes: freeBytes))
                        .font(.footnote.monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, verticalSizeClass == .compact ? 0 : Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
        }
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
