/// Decides when the app must release the fn key machine's hands-free lock: only when a
/// hands-free dictation stops (silence, the time cap, an error). Ordinary stops, such as the
/// first tap of a double-tap being cancelled, must leave the machine armed.
public struct HandsFreeLatch {
    private var wasHandsFree = false

    public init() {}

    /// Fed every controller change; true exactly when a hands-free dictation just ended.
    public mutating func update(listening: Bool, handsFree: Bool) -> Bool {
        let active = listening && handsFree
        defer { wasHandsFree = active }
        return wasHandsFree && !active
    }
}
