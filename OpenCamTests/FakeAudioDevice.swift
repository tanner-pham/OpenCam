import Foundation
@testable import OpenCam

/// Stands in for the audio hardware: reports the route it is given, records every plan, and refuses pins or monitors on request.
actor FakeAudioDevice: AudioDevice {
    nonisolated let changes: AsyncStream<AudioChange>
    private let continuation: AsyncStream<AudioChange>.Continuation
    private var currentRoute: AudioRoute
    private(set) var plans: [AudioPlan] = []
    private var refusesPins = false
    private var refusesMonitors = false

    init(route: AudioRoute) {
        currentRoute = route
        (changes, continuation) = AsyncStream.makeStream(of: AudioChange.self)
    }

    func setRoute(_ route: AudioRoute) { currentRoute = route }
    func setRefusesPins(_ isRefusing: Bool) { refusesPins = isRefusing }
    func setRefusesMonitors(_ isRefusing: Bool) { refusesMonitors = isRefusing }
    func send(_ change: AudioChange) { continuation.yield(change) }

    func route() async -> AudioRoute { currentRoute }

    func apply(_ plan: AudioPlan) async throws(AudioDeviceError) {
        plans.append(plan)
        if refusesPins, plan.pin != nil { throw .pinRefused(reason: "fake") }
        if refusesMonitors, plan.isMonitoring { throw .monitorRefused(reason: "fake") }
    }
}
