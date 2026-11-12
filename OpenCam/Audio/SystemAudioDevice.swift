import AVFAudio
import Foundation
import OSLog

/// The only code that touches `AVAudioSession` and `AVAudioEngine` for the Audio section. It executes the steps of an
/// `AudioPlan`; every decision about what to do is in `AudioState` and `AudioPlan.steps(from:)`. With the default plan it
/// makes no audio session or capture session call at all.
///
/// The engine is not Sendable and never leaves this actor. The session and its ports are Sendable, so they are looked up
/// by UID inside each call and never stored.
actor SystemAudioDevice: AudioDevice {
    nonisolated let changes: AsyncStream<AudioChange>
    private let continuation: AsyncStream<AudioChange>.Continuation
    private let capture: any CaptureAudioSession
    /// What the device last did; steps are worked out against it, and each step updates it only once it worked.
    private var applied = AudioPlan()
    private var engine: AVAudioEngine?
    /// The buffer preference before the monitor lowered it, put back when the monitor stops.
    private var earlierBufferDuration: TimeInterval?
    private var tokens: [any NSObjectProtocol] = []
    private var hasJournalledSession = false
    private static let monitorBufferDuration: TimeInterval = 0.005
    private static let logger = Logger(subsystem: "local.opencam.app", category: "SystemAudioDevice")

    init(capture: any CaptureAudioSession) {
        self.capture = capture
        (changes, continuation) = AsyncStream.makeStream(of: AudioChange.self)
    }

    isolated deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        continuation.finish()
    }

    // MARK: AudioDevice

    func route() async -> AudioRoute {
        if tokens.isEmpty { tokens = Self.observe(owner: self, continuation: continuation) }
        let session = AVAudioSession.sharedInstance()
        let inputs = (session.availableInputs ?? []).map { port in
            AudioInput(uid: port.uid, kind: AudioPortKind(portType: port.portType.rawValue), name: port.portName,
                       dataSources: (port.dataSources ?? []).map {
                           AudioDataSource(id: $0.dataSourceID.intValue, name: $0.dataSourceName, orientation: $0.orientation?.rawValue)
                       })
        }
        return AudioRoute(inputs: inputs, outputs: Self.outputKinds(of: session))
    }

    func apply(_ plan: AudioPlan) async throws(AudioDeviceError) {
        for step in plan.steps(from: applied) {
            switch step {
            case .stopMonitor:
                stopMonitor()
                applied.isMonitoring = false
            case .clearPin:
                clearPin()
                applied.pin = nil
            case .captureConfiguresAudio(let isAutomatic):
                await capture.setConfiguresAudioSessionAutomatically(isAutomatic)
                applied.captureConfiguresAudio = isAutomatic
            case .pin(let pin):
                try setPin(pin)
                applied.pin = pin
            case .startMonitor:
                try startMonitor()
                applied.isMonitoring = true
            }
        }
    }

    // MARK: Steps

    /// The data source is set on the port first, then the port is made the preferred input, which is one route change
    /// (AVAudioSessionRoute.h: a data source set on a port outside the route changes nothing until `setPreferredInput`).
    private func setPin(_ pin: AudioPin) throws(AudioDeviceError) {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.availableInputs?.first(where: { $0.uid == pin.portUID }) else {
            throw .inputMissing(uid: pin.portUID)
        }
        var source: AVAudioSessionDataSourceDescription?
        if let id = pin.dataSourceID {
            guard let found = port.dataSources?.first(where: { $0.dataSourceID.intValue == id }) else {
                throw .inputMissing(uid: pin.portUID)
            }
            source = found
        }
        journalSessionOnce(session)
        do {
            if let source { try port.setPreferredDataSource(source) }
            try session.setPreferredInput(port)
        } catch {
            throw .pinRefused(reason: error.localizedDescription)
        }
    }

    /// Logged only: a preference that cannot be cleared leaves the session where it was, and the capture session is handed
    /// back next.
    private func clearPin() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInput(nil)
        } catch {
            Self.logger.error("[SystemAudioDevice:clearPin] The preferred input stays — {reason: \(error.localizedDescription, privacy: .public)}")
        }
        guard let pin = applied.pin, pin.dataSourceID != nil,
              let port = session.availableInputs?.first(where: { $0.uid == pin.portUID }) else { return }
        do {
            try port.setPreferredDataSource(nil)
        } catch {
            Self.logger.error("[SystemAudioDevice:clearPin] The preferred microphone stays — {reason: \(error.localizedDescription, privacy: .public)}")
        }
    }

    private func startMonitor() throws(AudioDeviceError) {
        let session = AVAudioSession.sharedInstance()
        guard AudioRoute(inputs: [], outputs: Self.outputKinds(of: session)).headphones != nil else {
            throw .monitorRefused(reason: "no headphones in the route")
        }
        guard session.category == .playAndRecord, session.isInputAvailable else {
            throw .monitorRefused(reason: "no input in category \(session.category.rawValue)")
        }
        if earlierBufferDuration == nil {
            earlierBufferDuration = session.preferredIOBufferDuration
            do {
                try session.setPreferredIOBufferDuration(Self.monitorBufferDuration)
            } catch {
                Self.logger.error("[SystemAudioDevice:startMonitor] The buffer preference stays — {reason: \(error.localizedDescription, privacy: .public)}")
            }
        }
        do throws(AudioDeviceError) {
            engine = try Self.makeRunningEngine()
        } catch {
            restoreBufferDuration()
            throw error
        }
    }

    private func stopMonitor() {
        engine?.stop()
        engine = nil
        restoreBufferDuration()
    }

    private func restoreBufferDuration() {
        guard let earlier = earlierBufferDuration else { return }
        earlierBufferDuration = nil
        do {
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(earlier)
        } catch {
            Self.logger.error("[SystemAudioDevice:stopMonitor] The buffer preference stays — {reason: \(error.localizedDescription, privacy: .public)}")
        }
    }

    /// The input goes straight to the main mixer, which follows the output format (AVAudioEngine.h). Both formats are checked
    /// first: the engine otherwise raises an exception or fails later.
    private static func makeRunningEngine() throws(AudioDeviceError) -> AVAudioEngine {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw .monitorRefused(reason: "the input format is empty")
        }
        guard outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else {
            throw .monitorRefused(reason: "the output format is empty")
        }
        do {
            try engine.connectNode(input, to: engine.mainMixerNode, format: inputFormat)
            try engine.start()
        } catch {
            throw .monitorRefused(reason: error.localizedDescription)
        }
        return engine
    }

    /// Written once, at the first take-over, because the headers do not say which mode and options the capture session sets;
    /// the owner reads the line on the phone.
    private func journalSessionOnce(_ session: AVAudioSession) {
        guard !hasJournalledSession else { return }
        hasJournalledSession = true
        ErrorJournal.record("[SystemAudioDevice:setPin] Audio session at the first take-over — {category: \(session.category.rawValue), mode: \(session.mode.rawValue), options: \(session.categoryOptions.rawValue), input: \(session.currentRoute.inputs.first?.portType.rawValue ?? "none")}")
    }

    private static func outputKinds(of session: AVAudioSession) -> [AudioPortKind] {
        session.currentRoute.outputs.map { AudioPortKind(portType: $0.portType.rawValue) }
    }

    // MARK: Notifications

    /// The engine stops itself on a hardware format change (AVAudioEngine.h), so a monitor that is meant to run gets a fresh
    /// engine; a failure is reported to the model, which turns the monitor off.
    private func engineConfigurationChanged() {
        guard applied.isMonitoring, engine != nil else { return }
        engine?.stop()
        engine = nil
        do throws(AudioDeviceError) {
            engine = try Self.makeRunningEngine()
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            continuation.yield(.failed(error))
        }
    }

    /// Audio objects must be made again (AVAudioSessionTypes.h). The engine is dropped and the pin and monitor are forgotten, so
    /// the next sync applies them again. The capture session's flag is a property of its object, which the reset does not touch.
    private func mediaServicesWereReset() {
        engine = nil
        earlierBufferDuration = nil
        applied = AudioPlan(pin: nil, captureConfiguresAudio: applied.captureConfiguresAudio, isMonitoring: false)
        continuation.yield(.routeChanged)
    }

    /// The blocks run on whatever thread posts, read nothing, and only yield or start a task on the actor, as
    /// `CameraSession.observeNotifications` does.
    private nonisolated static func observe(owner: SystemAudioDevice, continuation: AsyncStream<AudioChange>.Continuation) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        let routeChange = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { _ in
            continuation.yield(.routeChanged)
        }
        let inputsChange = center.addObserver(forName: AVAudioSession.availableInputsChangeNotification, object: nil, queue: nil) { _ in
            continuation.yield(.routeChanged)
        }
        let reset = center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak owner] _ in
            Task { await owner?.mediaServicesWereReset() }
        }
        let configuration = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak owner] _ in
            Task { await owner?.engineConfigurationChanged() }
        }
        return [routeChange, inputsChange, reset, configuration]
    }
}
