import Foundation

nonisolated struct CaptureAccess: Sendable, Equatable {
    var camera: AccessState
    var microphone: AccessState

    var canUseCamera: Bool { camera == .authorized }
    var recordsSound: Bool { microphone == .authorized }
}
