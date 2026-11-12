/// One size and rate the check measures.
nonisolated struct RecorderCheckTarget: Sendable {
    let width: Int32
    let height: Int32
    let framesPerSecond: Int

    var label: String { "\(width)x\(height)@\(framesPerSecond)" }

    static let all = [
        RecorderCheckTarget(width: 1920, height: 1080, framesPerSecond: 30),
        RecorderCheckTarget(width: 1920, height: 1080, framesPerSecond: 60),
        RecorderCheckTarget(width: 3840, height: 2160, framesPerSecond: 30),
        RecorderCheckTarget(width: 3840, height: 2160, framesPerSecond: 60),
    ]
}
