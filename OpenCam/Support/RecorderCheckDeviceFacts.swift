import Foundation

/// What the phone is, and how much room it had.
nonisolated struct RecorderCheckDeviceFacts: Codable, Sendable {
    var modelIdentifier: String
    var osVersion: String
    var osBuild: String
    /// `volumeAvailableCapacityForImportantUsage` of the Documents volume; 0 when it could not be read.
    var freeDiskBytesAtStart: Int64
    var freeDiskBytesAtEnd: Int64?

    static func read() -> RecorderCheckDeviceFacts {
        RecorderCheckDeviceFacts(modelIdentifier: DeviceIdentity.modelIdentifier(),
                                 osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                 osBuild: DeviceIdentity.osBuild(), freeDiskBytesAtStart: FreeSpace.availableBytes())
    }
}
