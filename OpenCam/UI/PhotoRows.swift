import SwiftUI

struct PhotoRows: View {
    let resolver: PhotoSelectionResolver
    @Binding var selection: PhotoSelection
    let look: LookChoice
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(PhotoRow.allCases, id: \.self) { row in
                    ChipRow(title: row.title,
                            chips: resolver.chips(row, for: selection),
                            selectedID: selectedID(row),
                            reason: resolver.reasonLine(row, for: selection),
                            columns: row == .format ? 3 : 2) { chipID in
                        if let changed = resolver.select(row, chipID: chipID, in: selection) { selection = changed }
                    }
                }
                ChipRow(title: "Look", chips: look.chips, selectedID: look.selectedID, reason: look.reason, columns: 1,
                        isSingleLine: true, onSelect: look.onSelect)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, verticalSizeClass == .compact ? 0 : Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
        }
        .defaultScrollAnchor(look.scrollsIntoView ? .bottom : .top, for: .initialOffset)
    }

    private func selectedID(_ row: PhotoRow) -> String {
        switch row {
        case .format: selection.format.rawValue
        case .resolution: String(selection.megapixels)
        }
    }
}
