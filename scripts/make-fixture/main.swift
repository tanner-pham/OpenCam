// Builds OpenCam/Support/CapabilitiesFixture.json on stdout.
// Build and run: swiftc OpenCam/Capability/*.swift scripts/make-fixture/main.swift -o .build/make-fixture
import Foundation

let lenses = [
    Lens(id: "ultraWide", kind: .ultraWide, deviceUniqueID: "fixture-ultraWide", zoomFactor: 1, label: "0.5x"),
    Lens(id: "wide", kind: .wide, deviceUniqueID: "fixture-wide", zoomFactor: 1, label: "1x"),
    Lens(id: "wide@2", kind: .wide, deviceUniqueID: "fixture-wide", zoomFactor: 2, label: "2x"),
    Lens(id: "outer", kind: .outerUltraWide, deviceUniqueID: "fixture-outer", zoomFactor: 1, label: "Outer front"),
    Lens(id: "inner", kind: .innerUltraWide, deviceUniqueID: "fixture-inner", zoomFactor: 1, label: "Inner front"),
]

let proRes: [VideoCodec] = [("422 HQ", "apch"), ("422", "apcn"), ("422 LT", "apcs"), ("422 Proxy", "apco")].map {
    VideoCodec(family: .proRes, quality: $0.0, codecType: $0.1, bitrateTier: nil)
}
func tiered(_ family: CodecFamily, _ codecType: String) -> [VideoCodec] {
    BitrateTier.allCases.map { VideoCodec(family: family, quality: $0.rawValue, codecType: codecType, bitrateTier: $0) }
}
let hevc = tiered(.hevc, "hvc1")
let h264 = tiered(.h264, "avc1")

let uhd = Resolution.named(width: 3840, height: 2160)
let hd = Resolution.named(width: 1920, height: 1080)
let standardRates = [24, 25, 30, 48, 50, 60]

var video: [VideoOption] = []
// One table row: every lens x codec x (resolution, rates) x colour.
func add(_ lensIDs: [String], _ codecs: [VideoCodec], _ modes: [(Resolution, [Int])], _ colours: [ColourMode]) {
    for lensID in lensIDs {
        for codec in codecs {
            for (resolution, rates) in modes {
                for colour in colours {
                    for rate in rates {
                        video.append(VideoOption(lensID: lensID, codec: codec, resolution: resolution, frameRate: rate, colour: colour))
                    }
                }
            }
        }
    }
}

let rear = ["wide", "wide@2", "ultraWide"]
let frontRates = [24, 25, 30, 60]
add(["wide", "wide@2"], proRes, [(uhd, [24, 25, 30]), (hd, standardRates)], [.rec709, .hlg, .appleLog, .appleLog2])
add(["ultraWide"], proRes, [(hd, standardRates)], [.rec709, .hlg, .appleLog, .appleLog2])
add(rear, hevc, [(uhd, standardRates), (hd, standardRates)], [.rec709, .hlg, .appleLog2])
add(rear, hevc, [(hd, [100, 120])], [.rec709])
add(rear, h264, [(uhd, standardRates), (hd, standardRates + [100, 120])], [.rec709])
add(["outer", "inner"], hevc, [(hd, frontRates)], [.rec709, .hlg])
add(["outer", "inner"], h264, [(hd, frontRates)], [.rec709])

var photo: [PhotoOption] = []
for format in PhotoFormat.allCases {
    photo.append(PhotoOption(lensID: "wide", format: format, width: 8064, height: 6048))
}
for format in PhotoFormat.allCases {
    photo.append(PhotoOption(lensID: "wide", format: format, width: 4032, height: 3024))
}
for format in PhotoFormat.allCases {
    photo.append(PhotoOption(lensID: "ultraWide", format: format, width: 4032, height: 3024))
}
for lensID in ["wide@2", "outer", "inner"] {
    photo.append(PhotoOption(lensID: lensID, format: .heif, width: 4032, height: 3024))
}

let capabilities = CaptureCapabilities(lenses: lenses, videoOptions: video, photoOptions: photo, osBuild: "fixture", modelIdentifier: "fixture")
do {
    FileHandle.standardOutput.write(try capabilities.encoded())
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
