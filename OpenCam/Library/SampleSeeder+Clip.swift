import CoreGraphics
import Foundation
import SwiftUI

@MainActor extension SampleSeeder {
    /// 0 when Captures holds any clip. Else one 3 second H.264 clip of the hue sweep turning through the hue circle, with a sidecar
    /// read back from the file, so the Library's clip screen can be shown in the Simulator. Anything that fails throws `.seedFailed`
    /// and removes what was written.
    static func seedClipIfAbsent(_ captures: CaptureStore) async throws(LibraryError) -> Int {
        guard !LibraryScanner.items(in: captures.directory).contains(where: { $0.kind == .clip }) else { return 0 }
        let function = "seedClipIfAbsent"
        let sequence = captures.reserveSequence()
        let clipURL = captures.url(sequence: sequence, kind: .mov), sidecarURL = captures.url(sequence: sequence, kind: .sidecar)
        let renderer = ImageRenderer(content: HueSweepPattern().frame(width: CGFloat(SampleClipWriter.width), height: CGFloat(SampleClipWriter.height)))
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            throw .seedFailed(function: function, path: clipURL.path(percentEncoded: false), reason: "The picture could not be rendered")
        }
        do throws(LibraryError) {
            try await SampleClipWriter.write(image, to: clipURL)
            let facts: ClipFacts
            do throws(RecordingError) {
                facts = try await ClipInspector.inspect(url: clipURL, requestedFrameRate: Int(SampleClipWriter.framesPerSecond))
            } catch {
                throw .seedFailed(function: function, path: clipURL.path(percentEncoded: false), reason: error.description)
            }
            let codec = VideoCodec(family: .h264, quality: "High", codecType: "avc1", bitrateTier: .high)
            let requested = VideoOption(lensID: "sample", codec: codec, resolution: Resolution.named(width: SampleClipWriter.width, height: SampleClipWriter.height),
                                        frameRate: Int(SampleClipWriter.framesPerSecond), colour: .rec709)
            let sidecar = ClipSidecar(requested: requested, actual: facts, outcome: "sample", recordedAt: .now, error: nil, recorder: .system)
            do {
                try sidecar.encoded().write(to: sidecarURL, options: .atomic)
            } catch {
                throw .seedFailed(function: function, path: sidecarURL.path(percentEncoded: false), reason: error.localizedDescription)
            }
        } catch {
            for url in [clipURL, sidecarURL] { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return 1
    }
}
