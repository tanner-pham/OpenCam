import Foundation

/// A microphone port the session can route from, with the microphones it offers.
nonisolated struct AudioInput: Equatable, Sendable {
    let uid: String
    let kind: AudioPortKind
    let name: String
    let dataSources: [AudioDataSource]
}
