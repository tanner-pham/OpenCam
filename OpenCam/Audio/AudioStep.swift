import Foundation

/// One device call, in the order `AudioPlan.steps(from:)` lists them.
nonisolated enum AudioStep: Equatable, Sendable {
    case stopMonitor, clearPin, captureConfiguresAudio(Bool), pin(AudioPin), startMonitor
}
