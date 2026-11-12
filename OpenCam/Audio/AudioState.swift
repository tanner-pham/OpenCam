import Foundation

/// The Audio section's state: what the route offers, what the owner chose, and whether the camera is running. Pure; the
/// device is reached only through the `AudioPlan` it produces.
nonisolated struct AudioState: Equatable, Sendable {
    static let automaticID = "automatic"
    static let offID = "off"
    static let onID = "on"
    static let noAccessReason = "No microphone access."
    static let noHeadphonesReason = "Connect headphones to monitor."
    static let bluetoothDelayReason = "Bluetooth headphones add a delay."
    static let microphoneGoneNotice = "Microphone disconnected. Source is Automatic."
    static let headphonesGoneNotice = "Headphones disconnected. Monitoring is off."
    static let pinFailedNotice = "That microphone could not be used. Source is Automatic."
    static let monitorFailedNotice = "Monitoring could not start."

    private(set) var route = AudioRoute()
    private(set) var pinned: AudioPin?
    private(set) var wantsMonitor = false
    var isCameraLive = false
    var hasMicrophone = true

    // MARK: Source

    var sourceChips: [Chip] {
        let reason = hasMicrophone ? nil : Self.noAccessReason
        var chips = [Chip(id: Self.automaticID, title: "Automatic", detail: "Matches the camera", isAvailable: hasMicrophone, reason: reason)]
        for input in route.inputs {
            if input.dataSources.isEmpty {
                chips.append(Chip(id: AudioPin(portUID: input.uid, dataSourceID: nil).chipID, title: input.kind.title, detail: input.name,
                                  isAvailable: hasMicrophone, reason: reason))
            } else {
                for source in input.dataSources {
                    chips.append(Chip(id: AudioPin(portUID: input.uid, dataSourceID: source.id).chipID, title: input.kind.title,
                                      detail: source.label, isAvailable: hasMicrophone, reason: reason))
                }
            }
        }
        return chips
    }

    /// The chosen source's chip, or Automatic when nothing is chosen, the choice is not offered, or there is no access.
    var selectedSourceID: String {
        guard hasMicrophone, let pinned, sourceChips.contains(where: { $0.id == pinned.chipID }) else { return Self.automaticID }
        return pinned.chipID
    }

    var sourceReason: String? { hasMicrophone ? nil : Self.noAccessReason }

    // MARK: Monitor

    private var canMonitor: Bool { hasMicrophone && route.headphones != nil }

    var monitorChips: [Chip] {
        [Chip(id: Self.offID, title: "Off", detail: nil, isAvailable: hasMicrophone, reason: hasMicrophone ? nil : Self.noAccessReason),
         Chip(id: Self.onID, title: "On", detail: nil, isAvailable: canMonitor, reason: canMonitor ? nil : monitorReason)]
    }

    var selectedMonitorID: String { wantsMonitor ? Self.onID : Self.offID }

    var monitorReason: String? {
        guard hasMicrophone else { return Self.noAccessReason }
        guard let headphones = route.headphones else { return Self.noHeadphonesReason }
        return headphones == .bluetooth ? Self.bluetoothDelayReason : nil
    }

    // MARK: Plan

    /// Today's behaviour while nothing is chosen. A chosen source takes the audio session from the capture session only while
    /// the camera runs; monitoring runs only while the camera does and headphones are connected.
    var plan: AudioPlan {
        let activePin = hasMicrophone ? pinned : nil
        return AudioPlan(pin: activePin, captureConfiguresAudio: !(activePin != nil && isCameraLive),
                         isMonitoring: wantsMonitor && isCameraLive && canMonitor)
    }

    // MARK: Changes

    /// A tap on a chip of either row. An unknown or dimmed id changes nothing.
    mutating func select(chipID: String) {
        if let chip = monitorChips.first(where: { $0.id == chipID }) {
            if chip.isAvailable { wantsMonitor = chipID == Self.onID }
            return
        }
        guard let chip = sourceChips.first(where: { $0.id == chipID }), chip.isAvailable else { return }
        pinned = chipID == Self.automaticID ? nil : pin(forChipID: chipID)
    }

    mutating func setMonitor(_ isOn: Bool) {
        select(chipID: isOn ? Self.onID : Self.offID)
    }

    /// Takes in the route the session reports. Returns the notice when something the owner chose was taken away.
    mutating func routeChanged(to route: AudioRoute) -> String? {
        self.route = route
        var notice: String?
        if let pinned, !isListed(pinned) {
            self.pinned = nil
            notice = Self.microphoneGoneNotice
        }
        if wantsMonitor, route.headphones == nil {
            wantsMonitor = false
            notice = notice ?? Self.headphonesGoneNotice
        }
        return notice
    }

    /// A choice the device refused is dropped, so the row never names a microphone the session is not using.
    mutating func failed(_ error: AudioDeviceError) -> String {
        switch error {
        case .inputMissing, .pinRefused:
            pinned = nil
            return Self.pinFailedNotice
        case .monitorRefused:
            wantsMonitor = false
            return Self.monitorFailedNotice
        }
    }

    static func isLive(phase: CameraPhase, mode: CaptureMode, isInterrupted: Bool) -> Bool {
        (phase == .ready || phase == .simulator) && mode == .video && !isInterrupted
    }

    // MARK: Lookup

    private func pin(forChipID chipID: String) -> AudioPin? {
        for input in route.inputs {
            if input.dataSources.isEmpty, input.uid == chipID { return AudioPin(portUID: input.uid, dataSourceID: nil) }
            for source in input.dataSources where AudioPin(portUID: input.uid, dataSourceID: source.id).chipID == chipID {
                return AudioPin(portUID: input.uid, dataSourceID: source.id)
            }
        }
        return nil
    }

    private func isListed(_ pin: AudioPin) -> Bool {
        // A route read with the camera stopped can be empty (the session lists inputs for its current category only), and an
        // empty list then says nothing about the microphone.
        if !isCameraLive, route.inputs.isEmpty { return true }
        guard let input = route.inputs.first(where: { $0.uid == pin.portUID }) else { return false }
        guard let id = pin.dataSourceID else { return true }
        return input.dataSources.contains { $0.id == id }
    }
}
