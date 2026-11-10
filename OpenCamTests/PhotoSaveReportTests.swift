import Foundation
import Testing
@testable import OpenCam

@Suite struct PhotoSaveReportTests {
    let dng = URL(filePath: "/Captures/OC_0001.DNG")
    let heic = URL(filePath: "/Captures/OC_0001.HEIC")

    @Test func everythingSavedHasNoNotice() {
        let report = PhotoSaveReport.make(requested: [dng, heic], saved: [dng, heic], error: nil)
        #expect(report == PhotoSaveReport(notice: nil, lastCapture: heic))
        #expect(PhotoSaveReport.make(requested: [dng], saved: [dng], error: nil) == PhotoSaveReport(notice: nil, lastCapture: dng))
    }

    @Test func oneOfAPairSaved() {
        #expect(PhotoSaveReport.make(requested: [dng, heic], saved: [heic], error: .writeFailed(path: "OC_0001.DNG", reason: "disk full"))
                == PhotoSaveReport(notice: "RAW not saved. HEIF saved.", lastCapture: heic))
        #expect(PhotoSaveReport.make(requested: [dng, heic], saved: [dng], error: .noPhotoData)
                == PhotoSaveReport(notice: "HEIF not saved. RAW saved.", lastCapture: dng))
    }

    @Test func errorAfterEverythingSavedCountsAsSaved() {
        #expect(PhotoSaveReport.make(requested: [dng, heic], saved: [dng, heic], error: .captureFailed(reason: "late"))
                == PhotoSaveReport(notice: nil, lastCapture: heic))
    }

    @Test func nothingSaved() {
        #expect(PhotoSaveReport.make(requested: [heic], saved: [], error: .captureFailed(reason: "domain: x, code: 1"))
                == PhotoSaveReport(notice: "Photo not saved.", lastCapture: nil))
    }
}
