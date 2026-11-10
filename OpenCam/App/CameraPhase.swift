import Foundation

enum CameraPhase: Equatable, Sendable {
    case scanning, ready, simulator, cameraDenied, cameraRestricted
    case failed(String)
}
