import Foundation

/// The inputs the session offers and the kinds of output it plays to.
nonisolated struct AudioRoute: Equatable, Sendable {
    var inputs: [AudioInput] = []
    var outputs: [AudioPortKind] = []

    /// The kind of headphones in use: at least one output, and every output wired, USB or Bluetooth. A speaker or receiver in
    /// the route means the sound would not stay private, so there are no headphones then. Bluetooth wins when mixed.
    var headphones: AudioPortKind? {
        guard !outputs.isEmpty, outputs.allSatisfy({ $0 == .wired || $0 == .usb || $0 == .bluetooth }) else { return nil }
        return outputs.first { $0 == .bluetooth } ?? outputs.first
    }
}
