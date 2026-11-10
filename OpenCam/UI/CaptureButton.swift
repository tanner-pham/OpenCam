import SwiftUI

/// Round glass button that records video or takes a photo, by mode.
struct CaptureButton: View {
    let model: CameraModel

    private var isPhoto: Bool { model.mode == .photo }

    var body: some View {
        Button { model.capturePressed() } label: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(isPhoto ? .black : .white)
                .frame(width: Theme.Size.captureButton, height: Theme.Size.captureButton)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(isPhoto ? .white : Theme.recordRed)
        .disabled(!model.canCapture && !model.isRecording)
        .accessibilityLabel(label)
    }

    private var symbol: String {
        if isPhoto { return "circle.inset.filled" }
        return model.isRecording ? "stop.fill" : "circle.fill"
    }

    private var label: String {
        if isPhoto { return "Take photo" }
        return model.isRecording ? "Stop recording" : "Start recording"
    }
}
