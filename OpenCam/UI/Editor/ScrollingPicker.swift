import SwiftUI

/// A system segmented picker at its natural width, so every segment keeps its full title, scrolling sideways when it is wider
/// than the space. It opens scrolled to the end that holds the selection.
struct ScrollingPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        ScrollView(.horizontal) {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, Theme.Space.l)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Only the opening offset: a later choice never moves the strip under the finger.
        .defaultScrollAnchor(isSelectionInLastHalf ? .trailing : .leading, for: .initialOffset)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isSelectionInLastHalf: Bool {
        guard let index = options.firstIndex(of: selection) else { return false }
        return index * 2 >= options.count
    }
}
