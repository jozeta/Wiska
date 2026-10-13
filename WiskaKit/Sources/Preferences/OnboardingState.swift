/// The first-run checklist.
public enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    // Accessibility before Input Monitoring: macOS judges the request to listen to the fn key
    // through Accessibility, and refuses it (without a prompt) while Accessibility is off.
    case microphone, accessibility, inputMonitoring, fnKey, tryIt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        case .fnKey: "🌐 key → “Do Nothing”"
        case .tryIt: "Try it"
        }
    }

    public var reason: String {
        switch self {
        case .microphone: "to hear you — only while you hold fn"
        case .inputMonitoring: "to notice the fn key"
        case .accessibility: "to paste where you type"
        case .fnKey: "so holding fn doesn't open emoji or switch input"
        case .tryIt: "hold fn, say hi, release"
        }
    }

    public var isRequired: Bool {
        switch self {
        case .microphone, .inputMonitoring, .accessibility: true
        case .fnKey, .tryIt: false
        }
    }
}

public struct OnboardingState: Equatable, Sendable {
    public var microphone: Bool
    public var inputMonitoring: Bool
    public var accessibility: Bool
    public var fnKeyConfirmed: Bool
    public var firstDictationDone: Bool

    public init(microphone: Bool, inputMonitoring: Bool, accessibility: Bool,
                fnKeyConfirmed: Bool, firstDictationDone: Bool) {
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.fnKeyConfirmed = fnKeyConfirmed
        self.firstDictationDone = firstDictationDone
    }

    public func isDone(_ step: OnboardingStep) -> Bool {
        switch step {
        case .microphone: microphone
        case .inputMonitoring: inputMonitoring
        case .accessibility: accessibility
        case .fnKey: fnKeyConfirmed
        case .tryIt: firstDictationDone
        }
    }

    /// The three permissions are required; the 🌐 key and test dictation are recommended.
    public var canFinish: Bool {
        OnboardingStep.allCases.filter(\.isRequired).allSatisfy(isDone)
    }

    public func shouldOpenAtLaunch(completed: Bool) -> Bool {
        !completed || !canFinish
    }
}
