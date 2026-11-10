import SwiftUI

/// One look in the Looks group: the photo with the look, its name below. The selected tile has an accent outline and mark.
struct LookTile: View {
    let title: String
    let image: CGImage?
    let isSelected: Bool

    private static let corner = Theme.Space.s
    private static let outline: CGFloat = 3

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { picture }
                .clipShape(.rect(cornerRadius: Self.corner))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Self.corner)
                            .strokeBorder(Theme.accent, lineWidth: Self.outline)
                    }
                }
                .overlay(alignment: .topTrailing) { selectionMark }
            // One line; a long name ends in an ellipsis. The full name is in the context menu's header and the rename field.
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? Theme.accent : Color.primary)
                .frame(maxWidth: .infinity)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .shadow(radius: 2)
                .padding(Theme.Space.s)
        }
    }
}
