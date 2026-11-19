import Foundation

/// A request waiting for or on its way to the session. `serial` is the marker a hold's answer is for; `generation` is the
/// camera it was made for, so a request that waited across a camera change is dropped.
nonisolated struct FocusJob: Sendable, Equatable {
    let request: FocusRequest
    let serial: Int?
    let generation: Int
}
