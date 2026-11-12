import Foundation

/// The microphone the owner chose: a port, and one of its microphones when it has several.
nonisolated struct AudioPin: Equatable, Sendable {
    let portUID: String
    let dataSourceID: Int?

    /// The id of the chip that stands for this choice: the port's UID, or "uid#3" for its microphone 3.
    var chipID: String { dataSourceID.map { "\(portUID)#\($0)" } ?? portUID }
}
