import Foundation
import Testing
@testable import OpenCam

@Suite struct ClipFinisherTests {
    func pending(_ url: URL, option: VideoOption = SinkRig.proResProxy()) -> PendingRecording {
        PendingRecording(url: url, option: option, recordedAt: Date(timeIntervalSince1970: 1_700_000_000), onFinish: {})
    }

    @Test func aMissingFileIsFailed() async throws {
        let url = try TestFiles.directory().appending(path: "OC_0009.MOV")
        let result = await ClipFinisher.finish(pending(url), recorder: .system, drops: nil, errorMessage: nil, outcome: { _ in .completed })
        guard case .failed(let message) = result.outcome else {
            Issue.record("A finished clip with no file should be failed, got \(result.outcome)")
            return
        }
        #expect(message.contains("Clip missing after recording"))
        #expect(result.sidecar == nil)
        // An outcome that already says the clip is not playable stands.
        let stopped = await ClipFinisher.finish(pending(url), recorder: .system, drops: nil, errorMessage: nil,
                                                outcome: { _ in .stopped(.storageFull, isPlayable: false) })
        #expect(stopped.outcome == .stopped(.storageFull, isPlayable: false))
    }

    @Test func theSidecarCarriesTheRecorderAndTheDrops() async throws {
        let rig = try SinkRig()
        try rig.open(policy: .keepRecording)
        try await rig.deliver(frames: 0..<10)
        rig.drop(.outOfBuffers, atFrame: 10)
        try await rig.deliver(frames: 11..<20)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        let result = await ClipFinisher.finish(pending(rig.url), recorder: .writer, drops: report.facts, errorMessage: report.errorText,
                                               outcome: { RecordingOutcome(writerEnd: report.end, hasFrames: report.hasFrames, isReadable: $0) })
        #expect(result.outcome == .completed)
        let sidecar = try #require(result.sidecar)
        #expect(sidecar.recorder == .writer)
        #expect(sidecar.drops?.total == 1)
        #expect(sidecar.drops?.byReason[DropReason.outOfBuffers.rawValue] == 1)
        #expect(sidecar.drops?.framesWritten == 19)
        #expect(sidecar.actual?.frameCount == 19)
        // It was written beside the clip and reads back with the same fields.
        let json = rig.url.deletingPathExtension().appendingPathExtension("json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClipSidecar.self, from: Data(contentsOf: json))
        #expect(decoded.recorder == .writer)
        #expect(decoded.drops == sidecar.drops)
    }

    @Test func theSystemRecorderWritesItsPathAndNoDrops() async throws {
        let rig = try SinkRig()
        try rig.open()
        try await rig.deliver(frames: 0..<5)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        let result = await ClipFinisher.finish(pending(rig.url), recorder: .system, drops: nil, errorMessage: nil, outcome: { _ in .completed })
        #expect(result.sidecar?.recorder == .system)
        #expect(result.sidecar?.drops == nil)
    }

    @Test func aSidecarWrittenBeforeTheseFieldsStillDecodes() throws {
        let option = SinkRig.proResProxy()
        let written = ClipSidecar(requested: option, actual: nil, outcome: "completed", recordedAt: Date(timeIntervalSince1970: 1_700_000_000), error: nil,
                                  recorder: .writer, drops: DropFacts(total: 2))
        var object = try #require(JSONSerialization.jsonObject(with: written.encoded()) as? [String: Any])
        #expect(object["recorder"] != nil)
        object["recorder"] = nil
        object["drops"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClipSidecar.self, from: old)
        #expect(decoded.recorder == nil)
        #expect(decoded.drops == nil)
        #expect(decoded.requested == option)
        #expect(decoded.outcome == "completed")
    }
}
