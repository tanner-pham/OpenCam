import AVFAudio

/// What kind of connection an audio port is, as the Audio section names it.
nonisolated enum AudioPortKind: Equatable, Sendable {
    case builtIn, wired, usb, bluetooth, other

    /// `portType` is an `AVAudioSession.Port` raw value. Line in and line out, HDMI, AirPlay, car audio, the Continuity
    /// microphone and virtual ports are `other`: none is a headset, headphone jack, USB or Bluetooth device.
    init(portType: String) {
        switch portType {
        case AVAudioSession.Port.builtInMic.rawValue, AVAudioSession.Port.builtInSpeaker.rawValue,
             AVAudioSession.Port.builtInReceiver.rawValue:
            self = .builtIn
        case AVAudioSession.Port.headsetMic.rawValue, AVAudioSession.Port.headphones.rawValue:
            self = .wired
        case AVAudioSession.Port.usbAudio.rawValue:
            self = .usb
        case AVAudioSession.Port.bluetoothA2DP.rawValue, AVAudioSession.Port.bluetoothHFP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue:
            self = .bluetooth
        default:
            self = .other
        }
    }

    var title: String {
        switch self {
        case .builtIn: "Built-in"
        case .wired: "Wired"
        case .usb: "USB"
        case .bluetooth: "Bluetooth"
        case .other: "External"
        }
    }
}
