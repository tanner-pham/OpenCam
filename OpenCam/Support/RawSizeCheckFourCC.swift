/// Four-character codes ('bgg4', '420f') as text; a code with unprintable bytes prints as its number.
nonisolated enum RawSizeCheckFourCC {
    static func string(_ code: UInt32) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(code) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
