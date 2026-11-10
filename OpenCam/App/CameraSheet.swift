import Foundation

enum CameraSheet: String, Identifiable {
    case record, sweep

    var id: String { rawValue }
}
