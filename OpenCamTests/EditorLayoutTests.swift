import SwiftUI
import Testing
@testable import OpenCam

@Suite struct EditorLayoutTests {
    @Test func layouts() {
        #expect(EditorLayout.choose(horizontal: .regular, vertical: .regular) == .sideBySide)
        #expect(EditorLayout.choose(horizontal: .compact, vertical: .compact) == .sideBySide)
        #expect(EditorLayout.choose(horizontal: .compact, vertical: .regular) == .stacked)
        #expect(EditorLayout.choose(horizontal: nil, vertical: nil) == .stacked)
    }
}
