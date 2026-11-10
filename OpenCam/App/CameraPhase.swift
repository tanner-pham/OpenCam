import Foundation

nonisolated enum CameraPhase: Equatable, Sendable {
    /// `released`: the camera let go of its sensor while the Library covers it; it names no format and shows no readouts.
    case scanning, ready, simulator, cameraDenied, cameraRestricted, released
    case failed(String)
}
