import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct StatusTextTests {   // CaptureStore is main-actor
    @Test func viewfinderStates() {
        #expect(StatusText.viewfinder(.scanning) == ViewfinderStatus(message: "Reading camera formats…", offersSettings: false))
        #expect(StatusText.viewfinder(.cameraDenied) == ViewfinderStatus(message: "Camera access is off.", offersSettings: true))
        #expect(StatusText.viewfinder(.ready) == nil)
        #expect(StatusText.viewfinder(.failed("The camera stopped.")) == ViewfinderStatus(message: "The camera stopped.", offersSettings: false))
    }
    @Test func recordingNeedsReadyAndStorage() {
        #expect(StatusText.canRecord(phase: .ready, mode: .video, minutesRemaining: 20))
        #expect(!StatusText.canRecord(phase: .ready, mode: .video, minutesRemaining: 0))
        #expect(StatusText.canRecord(phase: .ready, mode: .photo, minutesRemaining: 0))
        #expect(!StatusText.canRecord(phase: .cameraDenied, mode: .video, minutesRemaining: 20))
        #expect(!StatusText.canRecord(phase: .simulator, mode: .photo, minutesRemaining: 20))
    }
    @Test func pressureCopy() {
        #expect(StatusText.pressure(.serious, isThermal: true) == "The phone is hot. Frame rate may drop.")
        #expect(StatusText.pressure(.critical, isThermal: false) == "The phone is under heavy load. Recording may stop.")
        #expect(StatusText.pressure(.fair, isThermal: true) == nil)
    }
    @Test func bottomNoticePrecedence() {
        let micOff = CaptureAccess(camera: .authorized, microphone: .denied), micOn = CaptureAccess(camera: .authorized, microphone: .authorized)
        #expect(StatusText.bottomNotice(access: micOff, pressure: "P", notice: "N") == "P")
        #expect(StatusText.bottomNotice(access: micOff, pressure: nil, notice: "N") == "No microphone access")
        #expect(StatusText.bottomNotice(access: micOn, pressure: nil, notice: "N") == "N")
        #expect(StatusText.bottomNotice(access: micOn, pressure: nil, notice: nil) == nil)
    }
    @Test func remainingAndLatest() {
        #expect(StatusText.remaining(minutes: 4) == RemainingTime(text: "4 min", isWarning: true))
        #expect(StatusText.remaining(minutes: 0) == RemainingTime(text: "Storage full", isWarning: true))
        #expect(StatusText.remaining(minutes: 5) == RemainingTime(text: "5 min", isWarning: false))
        #expect(CaptureStore.latestCaptureName(["OC_0003.MOV", "OC_0004.json", "sweep-x.json"]) == "OC_0003.MOV")
        #expect(CaptureStore.latestCaptureName(["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.MOV", "OC_0002.json", "sweep-x.json"]) == "OC_0002.MOV")
        #expect(CaptureStore.latestCaptureName(["OC_0003.DNG", "OC_0003.HEIC"]) == "OC_0003.HEIC"); #expect(CaptureStore.latestCaptureName([]) == nil)
    }
}
