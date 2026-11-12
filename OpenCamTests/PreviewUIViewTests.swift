import AVFoundation
import Testing
@testable import OpenCam

@Suite struct PreviewUIViewTests {
    @Test func theSharedPreviewIsMadeOncePerSession() throws {
        let source = PreviewSource(session: AVCaptureSession(), frames: FramePipeline())
        let first = PreviewUIView.shared(for: source)
        let second = PreviewUIView.shared(for: source)
        #expect(first === second)
        let layer = try #require(first.layer as? AVCaptureVideoPreviewLayer)
        #expect(layer.session === source.session)
    }
}
