import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct DropSettingTests {
    func model(config: LaunchConfig = LaunchConfig(), defaults: UserDefaults, isSimulator: Bool = false) throws -> CameraModel {
        CameraModel(config: config, capabilities: try Fixture.loadDuo().withWriterOptions(.all), isSimulator: isSimulator, defaults: defaults,
                    captureStore: try CaptureStore(directory: TestFiles.directory()))
    }

    @Test func theThreeLines() {
        #expect(DropPolicy.rowTitle == "When frames drop")
        #expect(DropPolicy.line(.keepRecording, recorder: .writer) == "Dropped frames are counted on screen and saved with the clip.")
        #expect(DropPolicy.line(.stopRecording, recorder: .writer) == "Recording stops at the first dropped frame. The clip is saved.")
        let system = "This format is checked for dropped frames when the clip ends. It does not stop early."
        #expect(DropPolicy.line(.keepRecording, recorder: .system) == system)
        #expect(DropPolicy.line(.stopRecording, recorder: .system) == system)
    }

    @Test func theTwoChips() throws {
        #expect(DropPolicy.keepRecording.title == "Keep recording")
        #expect(DropPolicy.stopRecording.title == "Stop recording")
        let m = try model(defaults: try Fixture.freshDefaults())
        let choice = m.dropChoice
        #expect(choice.chips.map(\.title) == ["Keep recording", "Stop recording"])
        #expect(choice.chips.allSatisfy { $0.isAvailable })
        #expect(choice.selectedID == DropPolicy.keepRecording.rawValue)
        choice.onSelect(DropPolicy.stopRecording.rawValue)
        #expect(m.dropPolicy == .stopRecording)
        #expect(m.dropChoice.selectedID == DropPolicy.stopRecording.rawValue)
        #expect(m.dropChoice.reason == DropPolicy.line(.stopRecording, recorder: m.recorderPath))
        m.dropChoice.onSelect("nonsense")
        #expect(m.dropPolicy == .stopRecording)
    }

    @Test func thePolicyIsSavedAndRestored() throws {
        let defaults = try Fixture.freshDefaults()
        #expect(DropPolicy.load(from: defaults) == .keepRecording)
        DropPolicy.stopRecording.save(to: defaults)
        #expect(DropPolicy.load(from: defaults) == .stopRecording)
        defaults.set("unknown", forKey: "dropPolicy")
        #expect(DropPolicy.load(from: defaults) == .keepRecording)
        let shared = try Fixture.freshDefaults()
        let one = try model(defaults: shared)
        one.dropPolicy = .stopRecording
        #expect(try model(defaults: shared).dropPolicy == .stopRecording)
        #expect(try model(defaults: try Fixture.freshDefaults()).dropPolicy == .keepRecording)
    }

    @Test func aScriptedLaunchNeitherLoadsNorSavesIt() throws {
        let defaults = try Fixture.freshDefaults()
        DropPolicy.stopRecording.save(to: defaults)
        let scripted = try model(config: LaunchConfig.parse(["app", "-mode", "video"]), defaults: defaults)
        #expect(scripted.dropPolicy == .keepRecording)
        DropPolicy.keepRecording.save(to: defaults)
        scripted.dropPolicy = .stopRecording
        #expect(DropPolicy.load(from: defaults) == .keepRecording)
    }

    @Test func aSimulatedDropCountNeedsASimulatedRecording() throws {
        let withRecording = try model(config: LaunchConfig.parse(["app", "-recording", "on", "-droppedFrames", "3"]), defaults: try Fixture.freshDefaults(), isSimulator: true)
        #expect(withRecording.droppedFrames == 3)
        let without = try model(config: LaunchConfig.parse(["app", "-droppedFrames", "3"]), defaults: try Fixture.freshDefaults(), isSimulator: true)
        #expect(without.droppedFrames == 0)
        let onDevice = try model(config: LaunchConfig.parse(["app", "-recording", "on", "-droppedFrames", "3"]), defaults: try Fixture.freshDefaults())
        #expect(onDevice.droppedFrames == 0)
    }

    @Test func noStringHasAnEmDash() {
        var texts = [DropPolicy.rowTitle]
        for policy in DropPolicy.allCases {
            texts.append(policy.title)
            for recorder in [RecorderPath.system, .writer] { texts.append(DropPolicy.line(policy, recorder: recorder)) }
        }
        for text in texts { #expect(!text.contains("\u{2014}")) }
    }
}
