import Testing
@testable import OpenCam

@Suite struct AudioMeterTests {
    @Test func scale() {
        #expect(AudioMeter.level(decibels: -60) == 0); #expect(AudioMeter.level(decibels: -30) == 0.5)
        #expect(AudioMeter.level(decibels: -90) == 0); #expect(AudioMeter.level(decibels: 3) == 1)
    }
}
