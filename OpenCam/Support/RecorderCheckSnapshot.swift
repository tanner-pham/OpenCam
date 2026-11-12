import UIKit

/// The phone's heat and battery at one moment.
nonisolated struct RecorderCheckSnapshot: Codable, Sendable {
    var thermalState: String
    /// Nil when the phone does not report a level.
    var batteryLevelPercent: Int?
    var batteryState: String
    var isCharging: Bool

    static var thermal: String { thermalName(ProcessInfo.processInfo.thermalState) }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// Serious or critical: the run stops starting new trials.
    static var isHot: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    @MainActor static func now() -> RecorderCheckSnapshot {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let name: String
        switch device.batteryState {
        case .unplugged: name = "unplugged"
        case .charging: name = "charging"
        case .full: name = "full"
        case .unknown: name = "unknown"
        @unknown default: name = "unknown"
        }
        let level = device.batteryLevel
        return RecorderCheckSnapshot(thermalState: thermal, batteryLevelPercent: level < 0 ? nil : Int((level * 100).rounded()),
                                     batteryState: name, isCharging: device.batteryState == .charging)
    }
}
