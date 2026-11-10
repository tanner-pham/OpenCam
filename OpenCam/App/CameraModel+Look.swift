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
}
