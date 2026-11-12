import AVFoundation
import Observation
import SwiftUI
import UIKit

/// Hands a check session to the preview layer on the main actor. `AVCaptureSession` is not Sendable in the SDK; the layer
/// only attaches to it and never configures it.
nonisolated struct LensCheckSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}

/// What the lens check's screen shows: the preview of the session running now, what to do with the phone, and the step.
@Observable
final class LensCheckProgress {
    var headline = "Lens check"
    var line = ""
    var isFinished = false
    @ObservationIgnored let previewView = LensCheckPreviewUIView()

    func set(headline: String? = nil, line: String) {
        if let headline { self.headline = headline }
        self.line = line
    }

    func show(_ box: LensCheckSessionBox?) {
        previewView.show(box?.session)
    }

    func finish() {
        isFinished = true
    }
}

/// A view whose layer is the preview layer of the check's own session.
final class LensCheckPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    /// Attaches the session (nil detaches it) and turns the preview upright for a portrait phone.
    func show(_ session: AVCaptureSession?) {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.videoGravity = .resizeAspect
        previewLayer.session = session
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

struct LensCheckPreviewView: UIViewRepresentable {
    let view: LensCheckPreviewUIView

    func makeUIView(context: Context) -> LensCheckPreviewUIView { view }
    func updateUIView(_ uiView: LensCheckPreviewUIView, context: Context) {}
}

/// The only screen of a `-lensCheck` launch: the live preview with two lines of text. The screen stays on while it runs.
struct LensCheckView: View {
    let progress: LensCheckProgress

    var body: some View {
        LensCheckPreviewView(view: progress.previewView)
            .ignoresSafeArea()
            .background(Color.black)
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    Text(progress.isFinished ? "Lens check finished." : progress.headline)
                        .font(.headline)
                    if !progress.isFinished, !progress.line.isEmpty { Text(progress.line).font(.footnote) }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 24)
                .padding(.horizontal, 16)
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onChange(of: progress.isFinished) { _, isFinished in
                UIApplication.shared.isIdleTimerDisabled = !isFinished
            }
    }
}
