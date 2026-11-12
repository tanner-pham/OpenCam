extension Duration {
    /// Milliseconds, with the fraction.
    nonisolated var recorderCheckMilliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
