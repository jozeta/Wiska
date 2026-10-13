extension Duration {
    /// The duration in seconds, with its fraction.
    public var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
