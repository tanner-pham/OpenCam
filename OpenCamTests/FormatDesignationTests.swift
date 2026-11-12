import Foundation
import Testing
@testable import OpenCam

@Suite struct FormatDesignationTests {
    @Test func designationsFollowTheFiles() {
        let names = ["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.HEIC", "OC_0003.DNG", "OC_0004.JPG", "OC_0005.jpeg", "OC_0006.PNG",
                     "OC_0007.HEIF", "OC_0008.JPG", "OC_0008.DNG", "OC_0009.MOV"]
        let items = LibraryScanner.group(names: names, directory: URL(filePath: "/tmp/c"))
        let titles = Dictionary(uniqueKeysWithValues: items.map { ($0.id, FormatDesignation.of($0)?.title ?? "clip") })
        #expect(titles == ["OC_0001": "RAW + HEIF", "OC_0002": "HEIF", "OC_0003": "RAW", "OC_0004": "JPEG", "OC_0005": "JPEG",
                           "OC_0006": "PNG", "OC_0007": "HEIF", "OC_0008": "RAW + JPEG", "OC_0009.MOV": "clip"])
    }
}
