import Foundation

/// Honoured only in the Simulator.
nonisolated enum SimulatedState: String, Sendable { case scanning, cameraDenied, micDenied, lowStorage, storageFull, pressure }
