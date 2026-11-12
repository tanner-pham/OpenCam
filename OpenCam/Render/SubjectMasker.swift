import CoreImage
import Foundation
import OSLog
import Vision

/// Finds the people and objects in the foreground of a photo with Vision's on-device segmentation.
/// How a search for the subject ended: it found one, Vision found nothing in the picture, or the search itself failed.
nonisolated enum SubjectSearch: Sendable {
    case found(CIImage), notFound, failed
}

nonisolated enum SubjectMasker {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "SubjectMasker")

    /// `image` scaled down so its long side is `longSide`, as the editor's preview proxy is; an image already that small is
    /// returned as it is. The subject search runs on this, so it never holds a full-resolution mask buffer, and the mask
    /// that comes back is scaled to the picture by `MaskImage`, as in the preview.
    static func searchImage(from image: CIImage, longSide: Int) -> CIImage {
        let long = max(image.extent.width, image.extent.height)
        guard long > CGFloat(longSide), long.isFinite else { return image }
        let scale = CGFloat(longSide) / long
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// A grayscale mask over `image.extent`, white on every foreground instance. `.notFound` when Vision finds nothing and
    /// `.failed` when it throws, each with a log line; a subject mask then does nothing.
    @concurrent static func mask(for image: CIImage) async -> SubjectSearch {
        let handler = ImageRequestHandler(image)
        do {
            guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()),
                  !observation.allInstances.isEmpty else {
                logger.info("[SubjectMasker:mask] Vision found no subject — {extent: \(image.extent.debugDescription, privacy: .public)}")
                return .notFound
            }
            let buffer = try observation.generateScaledMask(for: observation.allInstances, scaledToImageFrom: handler)
            return .found(CIImage(cvPixelBuffer: buffer))
        } catch let error as VisionError {
            logger.error("[SubjectMasker:mask] Vision could not find the subject — {error: \(String(describing: error), privacy: .public)}")
            return .failed
        } catch {
            logger.error("[SubjectMasker:mask] The subject could not be found — {error: \(error.localizedDescription, privacy: .public)}")
            return .failed
        }
    }
}
