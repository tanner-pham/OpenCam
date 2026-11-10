import SwiftUI

@main
struct DuoCamProbeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var model = ProbeModel()

    var body: some View {
        VStack(spacing: 12) {
            Button(model.isRunning ? "Running" : "Run probe") {
                Task { await model.run() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRunning)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let url = model.reportURL {
                ShareLink(item: url)
            }
        }
        .padding()
    }
}
