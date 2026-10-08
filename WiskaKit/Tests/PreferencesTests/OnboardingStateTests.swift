import Testing
@testable import Preferences

struct OnboardingStateTests {
    let allGranted = OnboardingState(microphone: true, inputMonitoring: true, accessibility: true,
                                     fnKeyConfirmed: false, firstDictationDone: false)

    @Test func finishNeedsOnlyThePermissions() {
        #expect(allGranted.canFinish)
        var missing = allGranted
        missing.accessibility = false
        #expect(!missing.canFinish)
    }

    @Test func stepStatuses() {
        var state = allGranted
        state.fnKeyConfirmed = true
        #expect(state.isDone(.microphone))
        #expect(state.isDone(.fnKey))
        #expect(!state.isDone(.tryIt))
        #expect(!OnboardingStep.tryIt.isRequired && OnboardingStep.accessibility.isRequired)
    }

    @Test func opensOnFirstLaunch() {
        #expect(allGranted.shouldOpenAtLaunch(completed: false))
    }

    @Test func reopensWhenPermissionMissing() {
        var state = allGranted
        state.inputMonitoring = false
        #expect(state.shouldOpenAtLaunch(completed: true))
        #expect(!allGranted.shouldOpenAtLaunch(completed: true))
    }
}
