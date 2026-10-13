/// Decides when Setup asks "Restart Wiska?". macOS lets Wiska listen to the fn key once
/// Accessibility is on, but only from the next launch. So: when Microphone and Accessibility
/// become allowed during this launch and listening still isn't, offer a restart, once.
public struct RestartOffer: Sendable {
    public struct Permissions: Equatable, Sendable {
        public var microphone: Bool
        public var accessibility: Bool
        public var inputMonitoring: Bool

        public init(microphone: Bool, accessibility: Bool, inputMonitoring: Bool) {
            self.microphone = microphone
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
        }
    }

    private var sawMissing = false
    private var offered = false

    public init() {}

    /// Feed every permission check; true exactly when the restart should be offered.
    public mutating func update(_ now: Permissions) -> Bool {
        let ready = now.microphone && now.accessibility
        if !ready { sawMissing = true }
        guard ready, !now.inputMonitoring, sawMissing, !offered else { return false }
        offered = true
        return true
    }
}
