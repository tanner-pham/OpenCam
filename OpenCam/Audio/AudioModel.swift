import Foundation
import Observation
import OSLog

/// Owns the Audio section's state and sends its plans to the device, one sync at a time on a serial chain.
@Observable final class AudioModel {
    private(set) var state = AudioState()
    /// The newest thing the owner should be told, until their next choice; shown through the camera's notice line.
    private(set) var notice: String?

    @ObservationIgnored private let device: any AudioDevice
    /// The tail of the serial chain of syncs, so plans reach the device in the order they were made.
    @ObservationIgnored private var syncTail: Task<Void, Never>?
    private static let logger = Logger(subsystem: "local.opencam.app", category: "Audio")

    init(device: any AudioDevice) {
        self.device = device
    }

    /// Follows what the device reports for as long as the calling task runs.
    func run() async {
        for await change in device.changes {
            switch change {
            case .routeChanged:
                break
            case .failed(let error):
                notice = state.failed(error)
            }
            queueSync()
        }
    }

    func select(chipID: String) {
        state.select(chipID: chipID)
        notice = nil
        queueSync()
    }

    func setMonitor(_ isOn: Bool) {
        state.setMonitor(isOn)
        notice = nil
        queueSync()
    }

    func setCamera(isLive: Bool, hasMicrophone: Bool) {
        state.isCameraLive = isLive
        state.hasMicrophone = hasMicrophone
        queueSync()
    }

    /// Waits for the syncs queued so far; for tests.
    func settle() async {
        while let tail = syncTail {
            await tail.value
            if syncTail == tail { return }
        }
    }

    private func queueSync() {
        let previous = syncTail
        syncTail = Task {
            await previous?.value
            await sync()
        }
    }

    /// Reads the route, then applies the plan. A refused plan is reduced to a fallback and applied once more.
    private func sync() async {
        let route = await device.route()
        if let routeNotice = state.routeChanged(to: route) { notice = routeNotice }
        do throws(AudioDeviceError) {
            try await device.apply(state.plan)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            notice = state.failed(error)
            do throws(AudioDeviceError) {
                try await device.apply(state.plan)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
                notice = state.failed(error)
            }
        }
    }
}
