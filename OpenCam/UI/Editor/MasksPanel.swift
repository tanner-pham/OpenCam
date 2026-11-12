import SwiftUI

/// The Masks group: four buttons that add a mask, then the chosen mask's row, Invert and Delete, then its seven sliders.
struct MasksPanel: View {
    @Bindable var model: EditorModel

    private static let rowGap = EditorPanel.rowGap

    var body: some View {
        ScrollView {
            VStack(spacing: Self.rowGap) {
                addButtons
                if model.masks.isEmpty {
                    Text("Add a mask to change one part of the photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    maskRow
                    actions
                    ForEach(LocalMask.keys, id: \.self) { key in
                        AdjustmentSlider(key: key, value: sliderBinding(key)) { model.updateSelectedMask { $0.adjustments[key] = 0 } }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var addButtons: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(MaskKind.allCases, id: \.self) { kind in
                Button { model.addMask(kind) } label: {
                    Text(kind.title)
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add a mask")
    }

    /// The masks by position, bound through the selected id (the picker's selection is not optional).
    private var maskRow: some View {
        let selection = Binding(
            get: { model.selectedMaskID ?? model.masks.first?.id ?? UUID() },
            set: { model.selectedMaskID = $0 }
        )
        return ScrollingPicker(title: "Mask", selection: selection, options: model.masks.map(\.id), label: title(of:))
            // The picker pads its own sides; the panel's padding already does.
            .padding(.horizontal, -Theme.Space.l)
    }

    private func title(of id: UUID) -> String {
        guard let index = model.masks.firstIndex(where: { $0.id == id }) else { return "" }
        return "\(model.masks[index].shape.kind.title) \(index + 1)"
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.s) {
            let isInverted = model.selectedMask?.isInverted ?? false
            Button { model.updateSelectedMask { $0.isInverted.toggle() } } label: {
                Text("Invert").frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
            }
            .buttonStyle(.bordered)
            .tint(isInverted ? Theme.accent : Color.primary)
            .fontWeight(isInverted ? .semibold : .regular)
            .accessibilityAddTraits(isInverted ? .isSelected : [])
            Button(role: .destructive) { model.deleteSelectedMask() } label: {
                Text("Delete").frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
            }
            .buttonStyle(.bordered)
        }
        // The first slider's reset target reaches up over the gap above its name row; the padding keeps it off the buttons.
        .padding(.bottom, AdjustmentSlider.reachUp - Self.rowGap)
    }

    private func sliderBinding(_ key: AdjustmentKey) -> Binding<Double> {
        Binding(
            get: { model.selectedMask?.adjustments[key] ?? 0 },
            set: { value in model.updateSelectedMask { $0.adjustments[key] = value } }
        )
    }
}
