import CoreImage
import Foundation
import OSLog
import Vision

/// Finds the people and objects in the foreground of a photo with Vision's on-device segmentation.
nonisolated enum SubjectMasker {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "SubjectMasker")

    /// A grayscale mask over `image.extent`, white on every foreground instance. Nil, with a log line, when Vision finds nothing
    /// or fails; a subject mask then does nothing.
    @concurrent static func mask(for image: CIImage) async -> CIImage? {
        let handler = ImageRequestHandler(image)
        do {
            guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()),
                  !observation.allInstances.isEmpty else {
                logger.info("[SubjectMasker:mask] Vision found no subject — {extent: \(image.extent.debugDescription, privacy: .public)}")
                return nil
            }
            let buffer = try observation.generateScaledMask(for: observation.allInstances, scaledToImageFrom: handler)
            return CIImage(cvPixelBuffer: buffer)
        } catch let error as VisionError {
            logger.error("[SubjectMasker:mask] Vision could not find the subject — {error: \(String(describing: error), privacy: .public)}")
            return nil
        } catch {
            logger.error("[SubjectMasker:mask] The subject could not be found — {error: \(error.localizedDescription, privacy: .public)}")
            return nil
        }
    }
}
