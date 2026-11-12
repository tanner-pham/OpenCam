import Foundation

/// What a device tells the model on its own.
nonisolated enum AudioChange: Sendable, Equatable {
    /// The route or the available inputs changed; the model reads the route again.
    case routeChanged
    /// Something the device was doing failed without a call from the model, such as a monitor that could not restart.
    case failed(AudioDeviceError)
}
