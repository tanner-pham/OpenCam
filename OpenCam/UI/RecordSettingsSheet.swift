import SwiftUI

struct RecordSettingsSheet: View {
    let mode: CaptureMode
    let recordResolver: RecordSelectionResolver
    let photoResolver: PhotoSelectionResolver
    @Binding var record: RecordSelection
    @Binding var photo: PhotoSelection
    let freeBytes: Int64
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .video: VideoRecordRows(resolver: recordResolver, selection: $record, freeBytes: freeBytes)
                case .photo: PhotoRows(resolver: photoResolver, selection: $photo)
                }
            }
            .navigationTitle(mode == .video ? "Record settings" : "Photo settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }
}
