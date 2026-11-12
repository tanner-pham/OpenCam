import Testing
@testable import OpenCam

@Suite struct SessionOutputPlanTests {
    func wanted(_ mode: CaptureMode, _ recorder: RecorderPath, frames: Bool = false, microphone: Bool = true) -> Set<SessionOutput> {
        SessionOutputPlan.wanted(mode: mode, recorder: recorder, needsFrames: frames, hasMicrophone: microphone)
    }

    @Test func eachConfigurationWantsItsOwnOutputs() {
        #expect(wanted(.photo, .system) == [.photo])
        #expect(wanted(.photo, .system, frames: true) == [.photo, .lookFrames])
        #expect(wanted(.video, .system) == [.movie])
        #expect(wanted(.video, .system, frames: true) == [.movie, .lookFrames])
        #expect(wanted(.video, .writer) == [.writerVideo, .writerSound])
        #expect(wanted(.video, .writer, microphone: false) == [.writerVideo])
    }

    @Test func noLookFramesOnTheWriterPathWhateverTheConfigurationAsks() {
        #expect(wanted(.video, .writer, frames: true) == [.writerVideo, .writerSound])
    }

    @Test func systemToWriterRemovesTheMovieOutputBeforeAddingTheWriterOutputs() {
        let plan = SessionOutputPlan.make(attached: wanted(.video, .system), wanted: wanted(.video, .writer))
        #expect(plan.removals == [.movie])
        #expect(plan.additions == [.writerVideo, .writerSound])
    }

    @Test func writerToSystemRemovesTheWriterOutputsBeforeAddingTheMovieOutput() {
        let plan = SessionOutputPlan.make(attached: wanted(.video, .writer), wanted: wanted(.video, .system))
        #expect(plan.removals == [.writerVideo, .writerSound])
        #expect(plan.additions == [.movie])
    }

    @Test func aLookFrameOutputGoesBeforeTheWriterVideoOutputComesIn() {
        let plan = SessionOutputPlan.make(attached: wanted(.video, .system, frames: true), wanted: wanted(.video, .writer, frames: true))
        #expect(plan.removals == [.movie, .lookFrames])
        #expect(plan.additions == [.writerVideo, .writerSound])
    }

    @Test func writerToWriterAndUnchangedDoNothing() {
        let writer = wanted(.video, .writer)
        #expect(SessionOutputPlan.make(attached: writer, wanted: writer) == SessionOutputPlan(removals: [], additions: []))
        let system = wanted(.video, .system)
        #expect(SessionOutputPlan.make(attached: system, wanted: system) == SessionOutputPlan(removals: [], additions: []))
    }

    @Test func aLostMicrophoneRemovesOnlyTheSoundOutput() {
        let plan = SessionOutputPlan.make(attached: wanted(.video, .writer), wanted: wanted(.video, .writer, microphone: false))
        #expect(plan.removals == [.writerSound])
        #expect(plan.additions.isEmpty)
    }

    @Test func photoAndVideoSwapRemoveFirst() {
        let plan = SessionOutputPlan.make(attached: wanted(.photo, .system), wanted: wanted(.video, .writer))
        #expect(plan.removals == [.photo])
        #expect(plan.additions == [.writerVideo, .writerSound])
    }
}
