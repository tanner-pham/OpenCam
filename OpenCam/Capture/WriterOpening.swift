import Foundation

/// Opens a writer for one clip. The sink's witness uses writer calls iOS 27 deprecates, so it is marked deprecated; reaching it
/// through this protocol keeps the callers free of warnings. Call inside the writer queue.
nonisolated protocol WriterOpening {
    func open(_ plan: WriterClipPlan, recordsSound: Bool) throws(RecordingError)
}
