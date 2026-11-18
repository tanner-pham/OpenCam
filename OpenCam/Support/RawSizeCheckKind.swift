/// What one capture asks for.
nonisolated enum RawSizeCheckKind: String, Codable, Sendable {
    case bayerRAW
    case proRAW
    case bayerRAWWithHEIF
}
