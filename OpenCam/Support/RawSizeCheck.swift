import AVFoundation
import OSLog

/// A one-off diagnostic, reached only with the `-rawSizeCheck` launch argument on a device. It tries every route to a RAW photo
/// the phone could offer (the photo preset, ProRAW, a chosen format, RAW with a HEIF) on each back camera, and records the size
/// of each DNG it gets. The report goes to `Documents/raw-size-check.json`. Every photo is measured in memory; no file is made.
nonisolated enum RawSizeCheck {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "RawSizeCheck")

    /// Runs off the main actor: starting a session blocks.
    @concurrent static func runAndWrite(progress: RawSizeCheckProgress) async {
        let report = RawSizeCheckReport(takenAt: .now, modelIdentifier: DeviceIdentity.modelIdentifier(),
                                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString, osBuild: DeviceIdentity.osBuild(),
                                        buildConfiguration: buildConfiguration, notes: notes)
        let run = RawSizeCheckRun(report: report, progress: progress)
        run.save()
        guard await hasCameraAccess() else {
            run.addError("runAndWrite", "No camera access", context: "status: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
            run.report.isComplete = true
            run.save()
            await progress.stop(because: "No camera access.")
            return
        }
        let cameras = RawSizeCheckCamera.discover()
        run.report.camerasChecked = cameras.map(\.name)
        if cameras.isEmpty { run.addError("runAndWrite", "The phone has no back camera of the kinds the check tries", context: "kinds: wide, ultra wide, dual wide") }
        for step in RawSizeCheckStep.plan(cameraCount: cameras.count) {
            let camera = cameras[step.cameraIndex]
            switch step.phase {
            case .photoPreset: await run.checkPhotoPreset(camera)
            case .chosenFormats: await run.checkChosenFormats(camera)
            }
        }
        run.report.isComplete = true
        run.save()
        await progress.finish()
    }

    private static func hasCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    private static let notes = [
        "Route A: session preset .photo. For each size in the active format's supportedMaxPhotoDimensions, the output's maxPhotoDimensions and the request's maxPhotoDimensions are set to that size and one Bayer RAW (DNG) is taken with quality prioritization speed and zoom 1.",
        "Route B: ProRAW, only where the output says isAppleProRAWSupported; isAppleProRAWEnabled is turned on for each trial and off again after it.",
        "Route C: each format with a photo size above 4032 x 3024 is made the active format (session preset inputPriority), largest photo size first, at most 12 per camera; skippedFormats says how many were left out. The output's size is the format's largest.",
        "Route D: under route A at its largest size, one request for Bayer RAW plus HEIF.",
        "A DNG's size is the largest image ImageIO finds in its data (size); imageSizes lists every image found. resolvedRawPhotoDimensions and resolvedPhotoDimensions come from the resolved settings.",
        "A photo is measured in memory and dropped; no photo is written to disk or saved to the library.",
        "A capture waits at most 6 seconds; a timeout is recorded as such and the session is rebuilt. When the 110 second time budget is used up, the trials left are recorded as skipped.",
        "AVCapturePhotoOutput.h says the 24 MP size is only serviced through deferred photo delivery, so a smaller result at 5712 x 4284 is expected for that reason.",
        "Order: routes A, D and B run on every camera first, then route C camera by camera. Route C also runs a ProRAW trial after a format's Bayer trial where the output reports ProRAW support.",
        "Each trial has an outcome: ran (a request was made), refused (the phone did not offer it), unsafe (a precondition of a safe request did not hold; failedPrecondition names it) or budget (the time budget ran out first).",
        "A RAW counts in the summary with the size ImageIO read from the DNG, or with the resolved settings' RAW size when ImageIO could not read the DNG; the sentence names both when they differ.",
        "The progress total grows as cameras and routes are planned, so the count of trials ahead is not known at the start.",
    ]
}
