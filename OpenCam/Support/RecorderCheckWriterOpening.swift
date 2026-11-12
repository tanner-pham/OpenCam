import Foundation

/// Lets the trial open a sink's writer without naming a deprecated method: the sink's witness is marked deprecated, the
/// requirement is not.
nonisolated protocol RecorderCheckWriterOpening {
    func open(url: URL, settings: [String: Any]) throws
}
