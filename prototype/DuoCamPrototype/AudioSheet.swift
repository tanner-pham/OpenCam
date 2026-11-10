import SwiftUI

struct AudioSheet: View {
    @Bindable var model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(model.audio.inputs) { input in
                        Button { model.audio.input = input.name } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(input.name)
                                    if !input.isConnected {
                                        Text("Not connected").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if model.audio.input == input.name {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .foregroundStyle(.primary)
                        .disabled(!input.isConnected)
                    }
                } header: { SheetHeader("Input") }
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Gain")
                            Spacer()
                            Text("\(Int(model.audio.gain)) dB").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $model.audio.gain, in: 0...24, step: 1)
                    }
                    AudioMetersView(levels: model.meterLevels, width: nil)
                } header: { SheetHeader("Level") }
                Section {
                    Picker("Format", selection: $model.audio.format) {
                        ForEach(AudioSettings.formats, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Toggle("Monitor in headphones", isOn: .constant(false))
                        .disabled(!model.audio.hasHeadphones)
                } footer: {
                    if !model.audio.hasHeadphones {
                        Text("Connect headphones to monitor audio.")
                    }
                }
            }
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }
}
