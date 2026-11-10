import SwiftUI

struct RecordSettingsSheet: View {
    let model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.mode == .video {
                    VideoRecordRows(model: model)
                } else {
                    PhotoRows(model: model)
                }
            }
            .navigationTitle(model.mode == .video ? "Record settings" : "Photo settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }
}
