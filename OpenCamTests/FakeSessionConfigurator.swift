import Foundation
@testable import OpenCam

/// Stands in for `CameraSession`: configuring a lens in `failingLensIDs` throws, everything else is recorded.
actor FakeSessionConfigurator: SessionConfigurator {
    let failingLensIDs: Set<String>
    private(set) var applied: [SessionConfiguration] = []

    init(failingLensIDs: Set<String>) {
        self.failingLensIDs = failingLensIDs
    }

    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        guard !failingLensIDs.contains(configuration.lens.id) else {
            throw .noMatchingFormat(option: "fake \(configuration.lens.id)")
        }
        applied.append(configuration)
    }
}
