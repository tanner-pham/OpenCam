import SwiftUI

struct MonitorSheet: View {
    @Bindable var model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("LUT", selection: $model.lut) {
                        ForEach(LUTChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: { SheetHeader("Preview") }
                Section {
                    Toggle("Zebra", isOn: $model.monitor.isZebraOn)
                    if model.monitor.isZebraOn {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Threshold")
                                Spacer()
                                Text("\(Int(model.monitor.zebraThreshold))%").monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: $model.monitor.zebraThreshold, in: 70...100, step: 1)
                        }
                    }
                    Toggle("False colour", isOn: $model.monitor.isFalseColourOn)
                } header: { SheetHeader("Exposure") }
                Section {
                    Toggle("Focus peaking", isOn: $model.monitor.isPeakingOn)
                } header: { SheetHeader("Focus") }
                Section {
                    Toggle("Histogram", isOn: $model.monitor.isHistogramOn)
                    Toggle("Waveform", isOn: $model.monitor.isWaveformOn)
                } header: { SheetHeader("Scopes") }
                Section {
                    Picker("Frame guides", selection: $model.monitor.frameGuide) {
                        ForEach(MonitorSettings.frameGuides, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Grid", isOn: $model.monitor.isGridOn)
                    Toggle("Level", isOn: $model.monitor.isLevelOn)
                } header: { SheetHeader("Guides") }
            }
            .navigationTitle("Monitor tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }
}
