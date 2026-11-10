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

    var isLookOffered: Bool { LookAvailability.isOffered(mode: mode, colour: record.colour) }
    var lookChips: [Chip] { LookAvailability.chips(looks: looks, isOffered: isLookOffered) }
    var lookChipID: String { cameraLook?.id.uuidString ?? LookAvailability.noneID }
    var lookReason: String? {
        LookAvailability.reasonLine(mode: mode, isOffered: isLookOffered, hasLook: cameraLook != nil)
    }

    /// A choice from the Look row: None, or a look's id. Choosing clears the look's own notice.
    func selectLook(chipID: String) {
        clearNotice(from: .look)
        selectLook(UUID(uuidString: chipID))
    }

    /// The look's name for the format summary; nil with no camera picture or no look.
    var summaryLookName: String? {
        guard hasCamera, let cameraLook else { return nil }
        return LookAvailability.summaryName(cameraLook.name)
    }

    /// A look the current mode and colour cannot take becomes None, with a notice. Sets the look directly, so it never
    /// asks the camera to change.
    func settleLook() {
        guard cameraLook != nil, !isLookOffered else { return }
        cameraLook = nil
        show(LookAvailability.turnedOff, from: .look)
    }
}
