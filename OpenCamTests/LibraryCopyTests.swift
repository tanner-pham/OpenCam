import Testing
@testable import OpenCam

@Suite struct LibraryCopyTests {
    @Test func copy() {
        #expect(LibraryCopy.selectionTitle(count: 0) == "Select items"); #expect(LibraryCopy.selectionTitle(count: 1) == "1 selected")
        #expect(LibraryCopy.selectionTitle(count: 3) == "3 selected")
        #expect(LibraryCopy.deleteTitle(count: 1) == "Delete 1 item?"); #expect(LibraryCopy.deleteTitle(count: 2) == "Delete 2 items?")
        #expect(LibraryCopy.duration(seconds: 42.5) == "0:42"); #expect(LibraryCopy.duration(seconds: 62) == "1:02"); #expect(LibraryCopy.duration(seconds: 3725) == "1:02:05")
        #expect(LibraryCopy.emptyTitle + ". " + LibraryCopy.emptyDetail == "No photos yet. Take one or import from Photos.")
        #expect(LibraryCopy.newerEdit == "This photo was edited by a newer version of OpenCam.")
    }
}
