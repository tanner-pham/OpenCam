import SwiftUI

struct PhotoRows: View {
    @Bindable var model: CaptureModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ChipRow(title: "Format", chips: PhotoSettings.formats.map { Chip(id: $0) }, selectedID: model.photo.format, columns: 3) { model.photo.format = $0 }
                ChipRow(title: "Resolution", chips: PhotoSettings.resolutions.map { Chip(id: $0) }, selectedID: model.photo.resolution, columns: 2) { model.photo.resolution = $0 }
                ChipRow(title: "Lens", chips: PhotoSettings.lenses.map { Chip(id: $0) }, selectedID: model.photo.lens, columns: 3) { model.photo.lens = $0 }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, verticalSizeClass == .compact ? 0 : Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
        }
    }
}
