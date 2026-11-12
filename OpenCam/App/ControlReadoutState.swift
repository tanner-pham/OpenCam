import Foundation

/// What one readout shows and does: its text, whether it is set by hand, open, or can be opened.
nonisolated struct ControlReadoutState: Sendable, Equatable {
    var text: String
    /// What VoiceOver says for the value.
    var spoken: String
    /// Set by hand (shutter and ISO together; temperature and tint together).
    var isSet: Bool
    var isOpen: Bool
    /// False when there is no scale for it, the camera cannot be adjusted now, or exposure is manual and this is EV.
    var isAvailable: Bool
    /// Drawn dimmed: only for a lasting reason (exposure is manual and this is EV, or the camera's ranges are known and it has no
    /// scale for this control). Unknown ranges never dim, since they are only unknown while the camera changes.
    var isDimmed: Bool
}
