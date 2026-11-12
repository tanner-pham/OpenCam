import Foundation

/// What the user has set by hand. `.automatic` at launch and after every camera change. Never saved.
nonisolated struct ManualSettings: Sendable, Equatable {
    enum Exposure: Sendable, Equatable {
        case automatic
        /// Nil holds the value the camera has now.
        case manual(shutterSeconds: Double?, iso: Float?)
    }

    enum WhiteBalance: Sendable, Equatable {
        case automatic
        case manual(kelvin: Float, tint: Float)
    }

    var exposure = Exposure.automatic
    /// Nil: never set here, so the camera's own bias is left alone.
    var bias: Float?
    var whiteBalance = WhiteBalance.automatic
    /// Nil: continuous autofocus.
    var focus: Float?

    static let automatic = ManualSettings()

    /// Bias does not count.
    var isAutomatic: Bool {
        exposure == .automatic && whiteBalance == .automatic && focus == nil
    }

    func setting(_ control: ManualControl, to value: Double, live: LiveReadouts) -> ManualSettings {
        var next = self
        switch control {
        case .shutter:
            next.exposure = .manual(shutterSeconds: value, iso: heldISO)
        case .iso:
            next.exposure = .manual(shutterSeconds: heldShutter, iso: Float(value))
        case .bias:
            next.bias = Float(value)
        case .temperature:
            next.whiteBalance = .manual(kelvin: Float(value), tint: heldTint ?? live.tint ?? 0)
        case .tint:
            next.whiteBalance = .manual(kelvin: heldKelvin ?? live.kelvin ?? 5600, tint: Float(value))
        case .focus:
            next.focus = Float(value)
        }
        return next
    }

    /// Shutter or ISO: both. Temperature or tint: both. Bias: unchanged.
    func settingAutomatic(_ control: ManualControl) -> ManualSettings {
        var next = self
        switch control {
        case .shutter, .iso: next.exposure = .automatic
        case .temperature, .tint: next.whiteBalance = .automatic
        case .focus: next.focus = nil
        case .bias: break
        }
        return next
    }

    /// What the readout and the thumb show.
    func value(of control: ManualControl, live: LiveReadouts) -> Double? {
        switch control {
        case .shutter: return heldShutter ?? live.shutterSeconds
        case .iso: return (heldISO ?? live.iso).map { Double($0) }
        case .bias:
            guard exposure == .automatic else { return nil }
            return (bias ?? live.exposureBias).map { Double($0) }
        case .temperature: return (heldKelvin ?? live.kelvin).map { Double($0) }
        case .tint: return (heldTint ?? live.tint).map { Double($0) }
        case .focus: return (focus ?? live.lensPosition).map { Double($0) }
        }
    }

    /// Shutter and ISO together; never `.bias`.
    func isSet(_ control: ManualControl) -> Bool {
        switch control {
        case .shutter, .iso: exposure != .automatic
        case .temperature, .tint: whiteBalance != .automatic
        case .focus: focus != nil
        case .bias: false
        }
    }

    /// False only for `.bias` while exposure is manual.
    func isAdjustable(_ control: ManualControl) -> Bool {
        control != .bias || exposure == .automatic
    }

    /// Nil: every group (bias only when set).
    func changedGroups(from applied: ManualSettings?) -> Set<ManualGroup> {
        guard let applied else {
            var groups: Set<ManualGroup> = [.exposure, .whiteBalance, .focus]
            if bias != nil { groups.insert(.bias) }
            return groups
        }
        var groups: Set<ManualGroup> = []
        if exposure != applied.exposure { groups.insert(.exposure) }
        if bias != applied.bias { groups.insert(.bias) }
        if whiteBalance != applied.whiteBalance { groups.insert(.whiteBalance) }
        if focus != applied.focus { groups.insert(.focus) }
        return groups
    }

    private var heldShutter: Double? {
        if case .manual(let shutter, _) = exposure { return shutter }
        return nil
    }

    private var heldISO: Float? {
        if case .manual(_, let iso) = exposure { return iso }
        return nil
    }

    private var heldKelvin: Float? {
        if case .manual(let kelvin, _) = whiteBalance { return kelvin }
        return nil
    }

    private var heldTint: Float? {
        if case .manual(_, let tint) = whiteBalance { return tint }
        return nil
    }
}
