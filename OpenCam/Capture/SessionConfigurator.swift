import Foundation

/// What the model needs from the session to apply a selection. `CameraSession` is the real one; tests use a fake.
nonisolated protocol SessionConfigurator: Sendable {
    /// Throws when the configuration cannot be applied; the session then keeps or restores the last one that worked.
    func configure(_ configuration: SessionConfiguration) async throws(CameraSessionError)
    func start() async
    /// A rescan stops the session first, because it sets each camera's format directly.
    func stop() async
}
