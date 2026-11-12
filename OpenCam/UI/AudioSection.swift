import SwiftUI

/// The microphone and headphone monitor choices in Record settings, after the Look row. Draws nothing without an audio model.
struct AudioSection: View {
    let columns: Int
    @Environment(AudioModel.self) private var audio: AudioModel?

    var body: some View {
        if let audio {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Audio")
                    .font(.headline)
                ChipRow(title: "Source", chips: audio.state.sourceChips, selectedID: audio.state.selectedSourceID,
                        reason: audio.state.sourceReason, columns: columns) { audio.select(chipID: $0) }
                ChipRow(title: "Monitor in headphones", chips: audio.state.monitorChips, selectedID: audio.state.selectedMonitorID,
                        reason: audio.state.monitorReason, columns: columns) { audio.select(chipID: $0) }
            }
        }
    }
}
