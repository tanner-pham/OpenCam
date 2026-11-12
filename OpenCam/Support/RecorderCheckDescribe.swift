/// Settings dictionaries as text with sorted keys, so two runs print the same way.
nonisolated enum RecorderCheckDescribe {
    static func value(_ value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            "{" + dictionary.sorted { $0.key < $1.key }.map { "\($0.key): \(Self.value($0.value))" }.joined(separator: ", ") + "}"
        case let array as [Any]:
            "[" + array.map { Self.value($0) }.joined(separator: ", ") + "]"
        default:
            String(describing: value)
        }
    }
}
