import Foundation

extension CameraModel {
    /// Chooses the look the camera applies; nil, or an id no look has, is None.
    func selectLook(_ id: UUID?) {
        cameraLook = looks.first { $0.id == id }.map(CameraLook.init)
        selectionChanged()
    }

    /// Reads the saved looks again (the Library may have renamed, changed or deleted them). The selection follows its look,
    /// or becomes None when the look is gone; the camera is only asked to change when the selection did.
    func reloadLooks() {
        looks = lookStore?.all() ?? []
        let reconciled = CameraLook.reconciled(cameraLook, with: looks)
        guard reconciled != cameraLook else { return }
        cameraLook = reconciled
        selectionChanged()
    }

    var isLookOffered: Bool { LookAvailability.isOffered(mode: mode, colour: record.colour, recorder: recorderPath) }
    var lookChips: [Chip] { LookAvailability.chips(looks: looks, isOffered: isLookOffered, recorder: recorderPath) }
    var lookChipID: String { cameraLook?.id.uuidString ?? LookAvailability.noneID }
    /// In video, while the viewfinder cannot show the look, it applies nowhere, so the row says that instead.
    var lookReason: String? {
        if mode == .video, cameraLook != nil, isLookViewfinderUnavailable { return Self.framesUnavailableNotice }
        return LookAvailability.reasonLine(mode: mode, isOffered: isLookOffered, hasLook: cameraLook != nil, recorder: recorderPath)
    }

    /// A choice from the Look row: None, or a look's id. Choosing clears the look's own notice.
    func selectLook(chipID: String) {
        clearNotice(from: .look)
        selectLook(UUID(uuidString: chipID))
    }

    /// The look drawn on the viewfinder: the selection while the mode and colour offer it and its frames can be drawn.
    /// A sweep suspends it.
    var viewfinderLook: CameraLook? { isLookOffered && !isLookViewfinderUnavailable && !isSweeping ? cameraLook : nil }

    /// The look's name for the format summary; nil with no camera picture or no look, and in video mode while the viewfinder
    /// cannot show it, since the look then applies nowhere.
    var summaryLookName: String? {
        guard hasCamera, let cameraLook, !(mode == .video && isLookViewfinderUnavailable) else { return nil }
        return LookAvailability.summaryName(cameraLook.name)
    }

    /// A look the current mode and colour cannot take becomes None. Its own notice is shown only when there is no notice or
    /// the current one is from `.look`, so a capture or configuration notice is never replaced. Sets the look directly, so it never
    /// asks the camera to change. A sweep's options are not the user's choice, so nothing is settled while one runs; the
    /// sweep settles once against the restored selection when it ends.
    func settleLook() {
        guard !isSweeping, cameraLook != nil, !isLookOffered else { return }
        cameraLook = nil
        showLookNotice(recorderPath == .writer ? LookAvailability.turnedOffForRecorder : LookAvailability.turnedOff)
    }

    /// The look's own notices are shown only when there is no notice or the current one is the look's, so a capture or
    /// configuration notice is never replaced.
    func showLookNotice(_ text: String) {
        guard notice == nil || noticeSource == .look else { return }
        show(text, from: .look)
    }
}
