import Foundation

/// One selectable microphone on a port, such as the front, back or bottom microphone of the phone.
nonisolated struct AudioDataSource: Equatable, Sendable {
    let id: Int
    let label: String

    /// `orientation` is an `AVAudioSession.Orientation` raw value; one the system leaves unset keeps the system's name.
    init(id: Int, name: String, orientation: String?) {
        self.id = id
        switch orientation?.lowercased() {
        case "front": label = "Front"
        case "back": label = "Back"
        case "bottom": label = "Bottom"
        case "top": label = "Top"
        case "left": label = "Left"
        case "right": label = "Right"
        default: label = name
        }
    }
}
