import SwiftUI

/// Connects the audio model to the camera: follows the device, tells the model when the camera starts and stops recording
/// sound, and shows the model's notice on the camera's notice line. Does nothing without both.
struct AudioLifecycle: ViewModifier {
    let model: CameraModel?
    let audio: AudioModel?

    private struct Camera: Equatable {
        let isLive: Bool
        let hasMicrophone: Bool
    }

    private var camera: Camera? {
        model.map { Camera(isLive: $0.isAudioLive, hasMicrophone: $0.access.recordsSound) }
    }

    func body(content: Content) -> some View {
        content
            .task { await audio?.run() }
            .onChange(of: camera, initial: true) { _, camera in
                guard let camera else { return }
                audio?.setCamera(isLive: camera.isLive, hasMicrophone: camera.hasMicrophone)
            }
            .onChange(of: audio?.notice) { _, notice in
                model?.showAudioNotice(notice)
            }
    }
}
