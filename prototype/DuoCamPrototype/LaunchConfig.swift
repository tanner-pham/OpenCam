import Foundation

enum CaptureMode: String { case video, photo }
enum ScreenState: String { case main, ruler, record, monitor, audio }
enum LaunchOrientation: String { case landscape, portrait }

/// Launch arguments, e.g. `-orientation landscape -mode video -screen main -lut on -recording off`.
struct LaunchConfig {
    var orientation: LaunchOrientation?
    var mode: CaptureMode = .video
    var screen: ScreenState = .main
    var isLutOn = true
    var isRecording = false

    static func parse(_ args: [String] = ProcessInfo.processInfo.arguments) -> LaunchConfig {
        var config = LaunchConfig()
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        config.orientation = value("-orientation").flatMap(LaunchOrientation.init(rawValue:))
        config.mode = value("-mode").flatMap(CaptureMode.init(rawValue:)) ?? .video
        config.screen = value("-screen").flatMap(ScreenState.init(rawValue:)) ?? .main
        config.isLutOn = value("-lut") != "off"
        config.isRecording = value("-recording") == "on"
        return config
    }
}
