import SwiftUI

/// One square in the Library grid: the picture drawn with its edit, or a clip's first frame.
struct LibraryCell: View {
    let library: LibraryStore
    let item: LibraryItem
    let isSelecting: Bool
    let isSelected: Bool

    @State private var state: ThumbnailState = .loading
    @State private var duration: Double?

    /// The cell's badges, message and selection mark follow the text size only this far. They sit on a thumbnail 110 to 125 pt
    /// wide: at accessibility sizes "RAW + HEIF" took two lines and half the picture, and past this size it no longer fits one
    /// line in the landscape grid. VoiceOver reads the same facts from the cell's label.
    private static let largestText = DynamicTypeSize.xLarge

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
            .overlay(alignment: .bottomTrailing) { clipBadge }
            .overlay(alignment: .bottomLeading) { formatBadge }
            .overlay(alignment: .topTrailing) { selectionMark }
            .clipped()
            .dynamicTypeSize(...Self.largestText)
            .contentShape(.rect)
            .task(id: library.thumbnailKey(for: item)) { state = await library.thumbnail(for: item) }
            .task(id: item.id) {
                guard item.kind == .clip else { return }
                duration = await ClipDuration.seconds(of: item)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var picture: some View {
        switch state {
        case .loading:
            ProgressView()
        case .ready(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        case .failed:
            VStack(spacing: 0) {
                Text(item.kind == .clip ? LibraryCopy.clipCannotOpen : LibraryCopy.cannotOpen)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The badges are drawn over the cell's bottom edge, so the message is centred in the space above them.
                badges.hidden()
            }
            .background(.secondary)
        }
    }

    private var badges: some View {
        ZStack {
            clipBadge
            formatBadge
        }
    }

    @ViewBuilder
    private var clipBadge: some View {
        if item.kind == .clip {
            LibraryBadge {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "play.fill")
                    if let duration {
                        Text(LibraryCopy.duration(seconds: duration)).monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var formatBadge: some View {
        if let designation = FormatDesignation.of(item) {
            LibraryBadge { Text(designation.title) }
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isSelecting {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Color.white)
                .shadow(radius: 2)
                .padding(Theme.Space.s)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String]
        switch item.kind {
        case .photo: parts = [item.stem] + (FormatDesignation.of(item).map { [$0.title] } ?? [])
        case .clip: parts = duration.map { ["Video", LibraryCopy.duration(seconds: $0)] } ?? ["Video"]
        }
        if isSelected { parts.append("Selected") }
        return parts.joined(separator: ", ")
    }
}
