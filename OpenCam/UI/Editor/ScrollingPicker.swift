import SwiftUI

/// A row of system buttons, one per option with its full title, scrolling sideways when it is wider than the space; the
/// selected one is filled. A drag that starts on a button scrolls the row (a segmented control would keep it), and the
/// selection is kept in view. It reads as one control named `title`.
struct ScrollingPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    /// The bordered styles add about 6.5 pt above and below the label (measured, iOS 27.2), so each button is
    /// `Theme.Size.minTarget` tall.
    private static var labelHeight: CGFloat { Theme.Size.minTarget - 13 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(options, id: \.self) { option in
                        button(for: option)
                            .id(option)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // A scroll view draws past its frame along its axis: into the safe area (the outer display's system strip, in
            // portrait) and while it rubber-bands. The row is cut at its own sides, so a button at the edge stops there; above
            // and below it is left free.
            .mask { Rectangle().padding(.vertical, -Theme.Space.l) }
            // The opening offset only: the end that holds the selection.
            .defaultScrollAnchor(isSelectionInLastHalf ? .trailing : .leading, for: .initialOffset)
            .onAppear { proxy.scrollTo(selection) }
            .onChange(of: selection) { _, chosen in
                withAnimation { proxy.scrollTo(chosen) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// The selected option is filled in the accent with dark text, which white text on the light accent would not be
    /// legible against; the others are neutral, so the row does not compete with the panel's own accent controls.
    @ViewBuilder private func button(for option: Value) -> some View {
        let isSelected = option == selection
        let button = Button { selection = option } label: {
            Text(label(option))
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: Self.labelHeight)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered).tint(.primary)
        }
    }

    private var isSelectionInLastHalf: Bool {
        guard let index = options.firstIndex(of: selection) else { return false }
        return index * 2 >= options.count
    }
}
