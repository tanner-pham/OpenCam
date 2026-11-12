import SwiftUI

/// The Masks group: one row with the Add menu and the masks, then Invert, Show mask and Delete, then a radial mask's Feather slider and the seven sliders.
struct MasksPanel: View {
    @Bindable var model: EditorModel

    private static let rowGap = EditorPanel.rowGap

    var body: some View {
        ScrollView {
            VStack(spacing: Self.rowGap) {
                topRow
                if model.masks.isEmpty {
                    Text("Add a mask to change one part of the photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    actions
                    if case let .radial(_, _, feather)? = model.selectedMask?.shape { featherSlider(feather) }
                    if model.selectedMask?.shape.kind == .brush { brushControls }
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

    /// The Add menu and, once a mask exists, the masks by position in the rest of the row.
    private var topRow: some View {
        HStack(spacing: Theme.Space.s) {
            addMenu
            if !model.masks.isEmpty { maskRow }
            else { Spacer(minLength: 0) }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(MaskKind.allCases, id: \.self) { kind in
                Button(kind.title) { model.addMask(kind) }
            }
        } label: {
            Label("Add", systemImage: "plus")
                .frame(minHeight: Theme.Size.minTarget - Self.borderedInset)
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .accessibilityLabel("Add mask")
    }

    /// The bordered styles add about 6.5 pt above and below the label (measured, as in `ScrollingPicker`).
    private static let borderedInset: CGFloat = 13

    /// The masks by position, bound through the selected id (the picker's selection is not optional).
    private var maskRow: some View {
        let selection = Binding(
            get: { model.selectedMaskID ?? model.masks.first?.id ?? UUID() },
            set: { model.selectedMaskID = $0 }
        )
        return ScrollingPicker(title: "Mask", selection: selection, options: model.masks.map(\.id), label: title(of:))
    }

    private func title(of id: UUID) -> String {
        guard let index = model.masks.firstIndex(where: { $0.id == id }) else { return "" }
        return "\(model.masks[index].shape.kind.title) \(index + 1)"
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.s) {
            toggleButton("Invert", isOn: model.selectedMask?.isInverted ?? false) { model.updateSelectedMask { $0.isInverted.toggle() } }
            toggleButton("Show mask", isOn: model.isShowingMaskOverlay) { model.isShowingMaskOverlay.toggle() }
            Button(role: .destructive) { model.deleteSelectedMask() } label: {
                Text("Delete")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget - Self.borderedInset)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        // The first slider's reset target reaches up over the gap above its name row; the padding keeps it off the buttons.
        .padding(.bottom, AdjustmentSlider.reachUp - Self.rowGap)
    }

    /// Filled in the accent with dark text when on, the faint neutral fill when off, as the picker's buttons are.
    private func toggleButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Color.black : Color.primary)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget - Self.borderedInset)
        }
        .buttonStyle(.borderedProminent)
        .tint(isOn ? Theme.accent : Color.primary.opacity(0.18))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Paint or Erase, then the brush's size; settings of the editor, not of the mask.
    @ViewBuilder
    private var brushControls: some View {
        Picker("Brush mode", selection: $model.isErasing) {
            Text("Paint").tag(false)
            Text("Erase").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(minHeight: Theme.Size.minTarget)
        AdjustmentSlider(title: "Size", value: $model.brushSize, range: 1...100, valueText: "\(Int(model.brushSize.rounded()))") {
            model.brushSize = 30
        }
    }

    /// How far a radial mask's soft edge reaches in from its outline, 0 to 100.
    private func featherSlider(_ feather: Double) -> some View {
        let binding = Binding(
            get: { feather * 100 },
            set: { value in
                model.updateSelectedMask { mask in
                    if case let .radial(centre, radius, _) = mask.shape { mask.shape = .radial(centre: centre, radius: radius, feather: value / 100) }
                }
            }
        )
        return AdjustmentSlider(title: "Feather", value: binding, range: 0...100, valueText: "\(Int(binding.wrappedValue.rounded()))") {
            model.updateSelectedMask { mask in
                if case let .radial(centre, radius, _) = mask.shape { mask.shape = .radial(centre: centre, radius: radius, feather: 0.5) }
            }
        }
    }

    private func sliderBinding(_ key: AdjustmentKey) -> Binding<Double> {
        Binding(
            get: { model.selectedMask?.adjustments[key] ?? 0 },
            set: { value in model.updateSelectedMask { $0.adjustments[key] = value } }
        )
    }
}
