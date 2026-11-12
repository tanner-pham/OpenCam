import SwiftUI

/// One square in the Library grid: the picture drawn with its edit, or a clip's first frame.
struct LibraryCell: View {
    let library: LibraryStore
    let item: LibraryItem
    let isSelecting: Bool
    let isSelected: Bool

    @State private var state: ThumbnailState = .loading
    @State private var duration: Double?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
            .overlay(alignment: .bottomTrailing) { clipBadge }
            .overlay(alignment: .bottomLeading) { formatBadge }
            .overlay(alignment: .topTrailing) { selectionMark }
            .clipped()
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
            Text(item.kind == .clip ? LibraryCopy.clipCannotOpen : LibraryCopy.cannotOpen)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(Theme.Space.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.secondary)
        }
    }

    @ViewBuilder
    private var clipBadge: some View {
        if item.kind == .clip {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "play.fill")
                if let duration {
                    Text(LibraryCopy.duration(seconds: duration)).monospacedDigit()
                }
            }
            .font(.caption)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .glassEffect(.regular, in: .capsule)
            .padding(Theme.Space.s)
        }
    }

    @ViewBuilder
    private var formatBadge: some View {
        if let designation = FormatDesignation.of(item) {
            Text(designation.title)
                .font(.caption)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xs)
                .glassEffect(.regular, in: .capsule)
                .padding(Theme.Space.s)
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
