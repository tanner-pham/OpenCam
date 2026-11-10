import Foundation

/// Launch arguments, e.g. `-orientation landscape -mode video -screen record -recording off`.
nonisolated struct LaunchConfig: Equatable, Sendable {
    var orientation: LaunchOrientation?
    var mode: CaptureMode = .video
    var screen: LaunchScreen = .main
    var isRecording = false
    var simulatedState: SimulatedState?
    var freeSpaceMarginMB: Int?
    var keepsSweepClips = false
    var editorGroup: EditorGroup = .light   // -editorGroup light|colour|detail|effects|looks
    var seedsSamples = false                // -seedSamples on (honoured in the Simulator only)
    var seedsLook = false                   // -seedLook on (honoured in the Simulator only)
    var startsInSelectMode = false          // -librarySelect on
    var cameraLookName: String?             // -cameraLook <name>: the look of that name is selected, or None when there is none
    /// True when -orientation, -mode, -screen, -recording, -state, -editorGroup, -cameraLook or an "on" flag among -seedSamples,
    /// -seedLook and -librarySelect parsed to a valid value; such launches never restore or save selections.
    var isScripted = false

    static func parse(_ args: [String]) -> LaunchConfig {
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        var config = LaunchConfig()
        if let orientation = value("-orientation").flatMap(LaunchOrientation.init(rawValue:)) {
            config.orientation = orientation
            config.isScripted = true
        }
        if let mode = value("-mode").flatMap(CaptureMode.init(rawValue:)) {
            config.mode = mode
            config.isScripted = true
        }
        if let screen = value("-screen").flatMap(LaunchScreen.init(rawValue:)) {
            config.screen = screen
            config.isScripted = true
        }
        if let recording = value("-recording"), recording == "on" || recording == "off" {
            config.isRecording = recording == "on"
            config.isScripted = true
        }
        if let state = value("-state").flatMap(SimulatedState.init(rawValue:)) {
            config.simulatedState = state
            config.isScripted = true
        }
        if let group = value("-editorGroup").flatMap(EditorGroup.init(rawValue:)) {
            config.editorGroup = group
            config.isScripted = true
        }
        if value("-seedSamples") == "on" {
            config.seedsSamples = true
            config.isScripted = true
        }
        if value("-seedLook") == "on" {
            config.seedsLook = true
            config.isScripted = true
        }
        if value("-librarySelect") == "on" {
            config.startsInSelectMode = true
            config.isScripted = true
        }
        if let name = value("-cameraLook") {
            config.cameraLookName = name
            config.isScripted = true
        }
        config.freeSpaceMarginMB = value("-freeSpaceMarginMB").flatMap { Int($0) }
        config.keepsSweepClips = value("-keepSweepClips") == "on"
        return config
    }
}
