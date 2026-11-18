import AVFoundation

nonisolated extension RawSizeCheckRun {
    /// Photo size cap for route C.
    private static let chosenFormatLimit = 12

    nonisolated(nonsending) func check(_ camera: RawSizeCheckCamera) async {
        await checkPhotoPreset(camera)
        await checkChosenFormats(camera)
    }

    /// Routes A, D and B, on one session with the photo preset.
    nonisolated(nonsending) private func checkPhotoPreset(_ camera: RawSizeCheckCamera) async {
        var rig: RawSizeCheckRig
        do throws(RawSizeCheckFailure) {
            rig = try RawSizeCheckRig(device: camera.device, format: nil)
            try await rig.start()
        } catch {
            addError("checkPhotoPreset", "The photo preset session could not start", context: error.message)
            await plan(1)
            await skippedTrial(.photoPreset, camera: camera, size: nil, reason: error.message)
            return
        }
        let sizes = Self.ascending(camera.device.activeFormat.supportedMaxPhotoDimensions)
        guard let largest = sizes.last else {
            rig.stop()
            await plan(1)
            await skippedTrial(.photoPreset, camera: camera, size: nil, reason: "[RawSizeCheck:checkPhotoPreset] The active format lists no photo size — {camera: \(camera.name)}")
            return
        }
        await plan(sizes.count + 1)
        let firstOfCamera = report.trials.count
        for size in sizes {
            if await trial(.photoPreset, camera: camera, rig: rig, kind: .bayerRAW, size: size) {
                guard let fresh = await replacement(for: camera, after: rig) else { return }
                rig = fresh
            }
        }
        if await trial(.rawWithCompanion, camera: camera, rig: rig, kind: .bayerRAWWithHEIF, size: largest) {
            guard let fresh = await replacement(for: camera, after: rig) else { return }
            rig = fresh
        }
        let proRAWSizes = report.trials[firstOfCamera...].filter { $0.route == .photoPreset && $0.availability?.isAppleProRAWSupported == true }
            .compactMap(\.requestedMaxPhotoDimensions)
        await plan(proRAWSizes.count)
        for size in proRAWSizes {
            if await trial(.proRAW, camera: camera, rig: rig, kind: .proRAW, size: size, enablesProRAW: true) {
                guard let fresh = await replacement(for: camera, after: rig) else { return }
                rig = fresh
            }
        }
        rig.stop()
    }

    /// Route C: every format with a photo size above 12 megapixels, largest first, one session that changes format.
    nonisolated(nonsending) private func checkChosenFormats(_ camera: RawSizeCheckCamera) async {
        let large = camera.device.formats.filter { format in
            format.supportedMaxPhotoDimensions.contains { Int($0.width) * Int($0.height) > RawSizeCheckSize.twelveMegapixel.pixels }
        }
        let ordered = large.sorted { Self.rank($1).lexicographicallyPrecedes(Self.rank($0)) }
        let chosen = Array(ordered.prefix(Self.chosenFormatLimit))
        let left = Array(ordered.dropFirst(Self.chosenFormatLimit))
        report.skippedFormats.append(RawSizeCheckSkippedFormats(camera: camera.name, count: left.count, formats: left.map(RawSizeCheckFormatFacts.init)))
        await plan(chosen.count)
        var rig: RawSizeCheckRig?
        for format in chosen {
            let size = RawSizeCheckFormatFacts(format).supportedMaxPhotoDimensions.max { $0.pixels < $1.pixels }
            guard let size else { continue }
            var isSwitched = false
            if let current = rig { isSwitched = await current.switchFormat(to: format) }
            if !isSwitched {
                rig?.stop()
                rig = nil
                do throws(RawSizeCheckFailure) {
                    let fresh = try RawSizeCheckRig(device: camera.device, format: format)
                    try await fresh.start()
                    rig = fresh
                } catch {
                    addError("checkChosenFormats", "The session for a chosen format could not start", context: error.message)
                    await skippedTrial(.chosenFormat, camera: camera, size: size, reason: error.message)
                    continue
                }
            }
            guard let active = rig else { continue }
            if await trial(.chosenFormat, camera: camera, rig: active, kind: .bayerRAW, size: size) {
                active.stop()
                rig = nil
            }
        }
        rig?.stop()
    }

    /// After a timeout: a new photo-preset session, or nil when it cannot be made (the trials left then fail on their own).
    nonisolated(nonsending) private func replacement(for camera: RawSizeCheckCamera, after old: RawSizeCheckRig) async -> RawSizeCheckRig? {
        old.stop()
        do throws(RawSizeCheckFailure) {
            let fresh = try RawSizeCheckRig(device: camera.device, format: nil)
            try await fresh.start()
            return fresh
        } catch {
            addError("replacement", "The session could not be rebuilt after a timeout", context: error.message)
            return nil
        }
    }

    private static func ascending(_ dimensions: [CMVideoDimensions]) -> [RawSizeCheckSize] {
        var sizes: [RawSizeCheckSize] = []
        for size in dimensions.map(RawSizeCheckSize.init).sorted(by: { $0.pixels < $1.pixels }) where !sizes.contains(size) {
            sizes.append(size)
        }
        return sizes
    }

    /// Largest photo size first, then formats that support the highest photo quality, then the larger picture.
    private static func rank(_ format: AVCaptureDevice.Format) -> [Int] {
        let largest = format.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
        let size = format.formatDescription.dimensions
        return [largest, format.isHighestPhotoQualitySupported ? 1 : 0, Int(size.width) * Int(size.height)]
    }
}
