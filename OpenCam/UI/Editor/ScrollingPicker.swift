import SwiftUI

/// A row of system buttons, one per option with its full title, scrolling sideways when it is wider than the space; the
/// selected one is filled. A drag that starts on a button scrolls the row (a segmented control would keep it), and the
/// selection is kept in view, centred where the row can scroll that far. It reads as one control named `title`.
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
            // Centred, so the selection never stops flush against or cut by the row's edge, as the least scroll would leave it.
            .onAppear { centreSelection(proxy) }
            // The scroll view keeps its offset when its width or its safe-area insets change (the editor settling beside the
            // system strip, or turning), which left the selection, or the last groups, out of view.
            .onScrollGeometryChange(for: CGSize.self, of: \.containerSize) { _, _ in centreSelection(proxy) }
            .onScrollGeometryChange(for: EdgeInsets.self, of: \.contentInsets) { _, _ in centreSelection(proxy) }
            .onChange(of: selection) { _, _ in
                withAnimation { centreSelection(proxy) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// One button whatever the selection, so it keeps its identity (and VoiceOver its focus) when chosen. The selected option is
    /// filled in the accent with dark text, which white text on the light accent would not be legible against; the others
    /// are a faint neutral fill, so the row does not compete with the panel's own accent controls.
    private func button(for option: Value) -> some View {
        let isSelected = option == selection
        return Button { selection = option } label: {
            Text(label(option))
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: Self.labelHeight)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? Theme.accent : Color.primary.opacity(Self.unselectedFill))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static var unselectedFill: Double { 0.18 }

    private func centreSelection(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(selection, anchor: .center)
    }

    private var isSelectionInLastHalf: Bool {
        guard let index = options.firstIndex(of: selection) else { return false }
        return index * 2 >= options.count
    }
}
