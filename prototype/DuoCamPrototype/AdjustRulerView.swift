import SwiftUI

/// Glass ruler for the selected readout, with an Auto button. Drag to change the value.
struct AdjustRulerView: View {
    let readout: Readout
    let model: CaptureModel

    private let tickSpacing: CGFloat = 24
    private let rulerHeight: CGFloat = 32

    var body: some View {
        let isAuto = model.autoReadouts.contains(readout)
        GlassEffectContainer(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                VStack(spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(readout.caption).font(Theme.Text.caption).foregroundStyle(.secondary)
                        Text(model.value(of: readout)).font(Theme.Text.value).foregroundStyle(Theme.accent)
                    }
                    ruler
                }
                .padding(.vertical, Theme.Space.s)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.Space.l))

                autoButton(isAuto: isAuto)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.m)
    }

    @ViewBuilder
    private func autoButton(isAuto: Bool) -> some View {
        let button = Button("Auto") { model.autoReadouts.insert(readout) }
            .controlSize(.large)
            .frame(minHeight: Theme.Size.minTarget)
        if isAuto {
            button.buttonStyle(.glassProminent).tint(Theme.accent).foregroundStyle(.black)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var ruler: some View {
        let count = model.ladder(for: readout).count
        let position = Binding<Int?>(
            get: { model.index(of: readout) },
            set: { if let index = $0 { model.setIndex(index, of: readout) } })
        return GeometryReader { geo in
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        ZStack {
                            Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 20)
                            if index < count - 1 {
                                Capsule().fill(.white.opacity(0.4)).frame(width: 1, height: 12)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .frame(width: tickSpacing, height: rulerHeight)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: position, anchor: .center)
            .onAppear { proxy.scrollTo(model.index(of: readout), anchor: .center) }
            .contentMargins(.horizontal, max(0, (geo.size.width - tickSpacing) / 2), for: .scrollContent)
            .overlay {
                Capsule().fill(Theme.accent).frame(width: 3, height: rulerHeight).allowsHitTesting(false)
            }
            }
        }
        .frame(height: rulerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(readout.caption) ruler")
        .accessibilityValue(model.value(of: readout))
    }
}
