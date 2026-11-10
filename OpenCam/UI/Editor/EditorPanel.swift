import SwiftUI

/// The group picker and the chosen group's sliders.
struct EditorPanel: View {
    @Bindable var model: EditorModel

    /// The Looks group arrives with Task 8.
    private static let groups = EditorGroup.allCases.filter { $0 != .looks }

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Picker("Group", selection: $model.group) {
                ForEach(Self.groups, id: \.self) { group in
                    Text(group.title).tag(group)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Space.l)
            ScrollView {
                // The rows' 44 pt name areas already space them evenly.
                VStack(spacing: 0) {
                    ForEach(model.group.keys, id: \.self) { key in
                        AdjustmentSlider(key: key, value: $model.adjustments[key]) { model.reset(key) }
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, Theme.Space.m)
    }
}
