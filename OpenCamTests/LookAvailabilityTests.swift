import Foundation
import Testing
@testable import OpenCam

@Suite struct LookAvailabilityTests {
    let agfa = Look(id: UUID(), name: "Agfa", adjustments: Adjustments(), createdAt: .now)
    let warm = Look(id: UUID(), name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20), createdAt: .now)

    @Test func offeredForRec709AndP3InVideoAndAlwaysInPhoto() {
        #expect(LookAvailability.isOffered(mode: .video, colour: .rec709)); #expect(LookAvailability.isOffered(mode: .video, colour: .p3))
        for colour in [ColourMode.hlg, .appleLog, .appleLog2] { #expect(!LookAvailability.isOffered(mode: .video, colour: colour)) }
        for colour in ColourMode.allCases { #expect(LookAvailability.isOffered(mode: .photo, colour: colour)) }
    }

    @Test func chipsPutNoneFirstAndDimLooksWhenNotOffered() {
        let chips = LookAvailability.chips(looks: [agfa, warm], isOffered: true)
        #expect(chips.map(\.title) == ["None", "Agfa", "Warm fade"]); #expect(chips.map(\.id) == ["none", agfa.id.uuidString, warm.id.uuidString])
        #expect(chips.allSatisfy { $0.isAvailable })
        let dimmed = LookAvailability.chips(looks: [agfa, warm], isOffered: false)
        #expect(dimmed.map(\.isAvailable) == [true, false, false]); #expect(dimmed[2].reason == "Looks need Rec. 709 or P3.")
        #expect(LookAvailability.chips(looks: [], isOffered: true).map(\.title) == ["None"])
    }

    @Test func reasonLinesAndSummaryNames() {
        #expect(LookAvailability.reasonLine(mode: .video, isOffered: true, hasLook: true) == "Shown in the viewfinder only. Video is recorded without it.")
        #expect(LookAvailability.reasonLine(mode: .video, isOffered: true, hasLook: false) == nil)
        #expect(LookAvailability.reasonLine(mode: .video, isOffered: false, hasLook: false) == "Looks need Rec. 709 or P3.")
        #expect(LookAvailability.reasonLine(mode: .photo, isOffered: true, hasLook: true) == nil)
        #expect(LookAvailability.summaryName("Warm fade") == "Warm fade"); #expect(LookAvailability.summaryName("Sixteen chars ok") == "Sixteen chars ok")
        #expect(LookAvailability.summaryName("A very long look name") == "A very long loo…")
    }
}
