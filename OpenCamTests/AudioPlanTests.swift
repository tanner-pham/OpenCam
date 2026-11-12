import Testing
@testable import OpenCam

@Suite struct AudioPlanTests {
    private let pin = AudioPin(portUID: "usb", dataSourceID: nil)
    private let other = AudioPin(portUID: "mic", dataSourceID: 3)

    @Test func theDefaultPlanHasNoSteps() {
        #expect(AudioPlan().steps(from: AudioPlan()).isEmpty)
        // A fresh state with any route, live or not, still plans nothing.
        for route in [AudioFixtures.speaker, AudioFixtures.wiredHeadphones, AudioFixtures.bluetoothHeadphones, AudioFixtures.usbRoute] {
            let state = AudioFixtures.live(route)
            #expect(state.plan == AudioPlan())
            #expect(state.plan.steps(from: AudioPlan()).isEmpty)
        }
    }

    @Test func pinningTakesOverThenSetsTheInput() {
        let target = AudioPlan(pin: pin, captureConfiguresAudio: false)
        #expect(target.steps(from: AudioPlan()) == [.captureConfiguresAudio(false), .pin(pin)])
        // Already taken over: only a different input is set.
        #expect(target.steps(from: AudioPlan(pin: other, captureConfiguresAudio: false)) == [.pin(pin)])
        #expect(target.steps(from: target).isEmpty)
    }

    @Test func backToAutomaticClearsThePinThenHandsBack() {
        let applied = AudioPlan(pin: pin, captureConfiguresAudio: false)
        #expect(AudioPlan().steps(from: applied) == [.clearPin, .captureConfiguresAudio(true)])
    }

    @Test func aParkedPinOnlyHandsBackAndIsSetAgainOnReturn() {
        let running = AudioPlan(pin: pin, captureConfiguresAudio: false)
        let parked = AudioPlan(pin: pin, captureConfiguresAudio: true)
        #expect(parked.steps(from: running) == [.captureConfiguresAudio(true)])
        #expect(running.steps(from: parked) == [.captureConfiguresAudio(false), .pin(pin)])
        // A parked pin the owner then drops is cleared.
        #expect(AudioPlan().steps(from: parked) == [.clearPin])
    }

    @Test func monitoringStopsFirstAndStartsLast() {
        let monitoring = AudioPlan(isMonitoring: true)
        #expect(monitoring.steps(from: AudioPlan()) == [.startMonitor])
        #expect(AudioPlan().steps(from: monitoring) == [.stopMonitor])
        let pinned = AudioPlan(pin: pin, captureConfiguresAudio: false, isMonitoring: true)
        #expect(pinned.steps(from: AudioPlan()) == [.captureConfiguresAudio(false), .pin(pin), .startMonitor])
        #expect(AudioPlan().steps(from: pinned) == [.stopMonitor, .clearPin, .captureConfiguresAudio(true)])
        // A new input under a running monitor rebuilds it.
        let moved = AudioPlan(pin: other, captureConfiguresAudio: false, isMonitoring: true)
        #expect(moved.steps(from: pinned) == [.stopMonitor, .pin(other), .startMonitor])
        #expect(pinned.steps(from: pinned).isEmpty)
    }
}
