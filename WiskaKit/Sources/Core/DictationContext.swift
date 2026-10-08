/// What was in front of the user when they started dictating. Cleanup uses it in M3 (app-aware tone).
public struct DictationContext: Sendable, Equatable {
    public var appBundleID: String?

    public init(appBundleID: String? = nil) {
        self.appBundleID = appBundleID
    }
}
