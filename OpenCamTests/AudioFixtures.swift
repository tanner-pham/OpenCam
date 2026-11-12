import Foundation
@testable import OpenCam

/// Routes the audio tests share.
nonisolated enum AudioFixtures {
    static let builtIn = AudioInput(uid: "mic", kind: .builtIn, name: "iPhone Microphone", dataSources: [
        AudioDataSource(id: 1, name: "Front", orientation: "Front"),
        AudioDataSource(id: 2, name: "Back", orientation: "Back"),
        AudioDataSource(id: 3, name: "Bottom", orientation: "Bottom")])
    static let usb = AudioInput(uid: "usb", kind: .usb, name: "USB Audio", dataSources: [])
    static let headset = AudioInput(uid: "headset", kind: .wired, name: "Headset microphone", dataSources: [])

    static let speaker = AudioRoute(inputs: [builtIn], outputs: [.builtIn])
    static let wiredHeadphones = AudioRoute(inputs: [builtIn, headset], outputs: [.wired])
    static let bluetoothHeadphones = AudioRoute(inputs: [builtIn], outputs: [.bluetooth])
    static let usbRoute = AudioRoute(inputs: [builtIn, usb], outputs: [.builtIn])

    static let back = AudioPin(portUID: "mic", dataSourceID: 2)
    static let usbPin = AudioPin(portUID: "usb", dataSourceID: nil)

    /// A state that has seen `route`, with the camera running.
    static func live(_ route: AudioRoute) -> AudioState {
        var state = AudioState()
        state.isCameraLive = true
        _ = state.routeChanged(to: route)
        return state
    }
}
