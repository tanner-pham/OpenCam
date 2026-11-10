import SwiftUI

/// The name prompt for "Save as look" and "Rename look": a small sheet whose reason line and Save button follow the name as
/// it is typed. A system alert keeps the message it opened with, so it cannot do this.
struct LookNameSheet: View {
    let naming: LookNaming
    let onSave: (String) -> Void

    @State private var name: String
    @FocusState private var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private static let height: CGFloat = 160

    init(naming: LookNaming, onSave: @escaping (String) -> Void) {
        self.naming = naming
        self.onSave = onSave
        _name = State(initialValue: naming.look?.name ?? "")
    }

    /// Why the name cannot be saved yet; nil when it can.
    private var problem: String? { LookStore.nameProblem(name) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                // The line keeps its height when there is nothing to say, so the field does not move while typing.
                Text(problem ?? " ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(problem == nil)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.s)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(naming.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(problem != nil)
                }
            }
        }
        .presentationDetents([.height(Self.height)])
        .onAppear { isFieldFocused = true }
    }

    private func save() {
        guard problem == nil else { return }
        onSave(name)
        dismiss()
    }
}
