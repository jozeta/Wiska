import Core
import Testing
@testable import Dictation

@MainActor
struct DictationControllerTests {
    let audio = FakeAudio()
    let transcriber = FakeTranscriber()
    let cleaner = FakeCleaner()
    let injector = FakeInjector()

    func makeController(maxDuration: Duration = .seconds(300)) -> DictationController {
        DictationController(
            audio: audio, transcriber: transcriber, cleaner: cleaner, injector: injector,
            contextProvider: { DictationContext(appBundleID: "com.apple.TextEdit") },
            maxDuration: maxDuration, noticeDuration: .seconds(60)
        )
    }

    @Test func happyPathTranscribesCleansAndInjects() async {
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }

        controller.handle(.pressed)
        #expect(controller.state == .listening)
        audio.emit([0.1, 0.2])
        audio.emit([0.3])
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(transcriber.session.appended == [[0.1, 0.2], [0.3]])
        #expect(transcriber.languages == [.fixed(.english)])
        #expect(cleaner.contexts == [DictationContext(appBundleID: "com.apple.TextEdit")])
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(recorder.states == [.listening, .transcribing, .cleaning, .injecting, .idle])
        #expect(controller.lastLatency != nil)
    }

    @Test func levelsAreTrackedForTheWaveform() async {
        let controller = makeController()
        controller.handle(.pressed)
        audio.emitLevel(0.5)
        audio.emitLevel(0.7)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.levels == [0.5, 0.7])
        controller.handle(.released)
        await controller.currentTask?.value
    }

    @Test func cancelledDiscardsAudioAndInjectsNothing() async {
        let controller = makeController()
        controller.handle(.pressed)
        audio.emit([0.1])
        controller.handle(.cancelled)
        await controller.currentTask?.value

        #expect(controller.state == .idle)
        #expect(injector.injected.isEmpty)
        #expect(transcriber.session.cancelled)
    }

    @Test func emptyTranscriptFailsWithNoSpeech() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(controller.state == .failed(.noSpeech))
        #expect(injector.injected.isEmpty)
    }

    @Test func transcriberErrorFails() async {
        transcriber.session.result = .failure(FakeError())
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        guard case .failed(.transcription) = controller.state else {
            Issue.record("expected transcription failure, got \(controller.state)")
            return
        }
    }

    @Test func secureInputFailsWithSecureInput() async {
        injector.error = .secureInputActive
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(controller.state == .failed(.secureInput))
    }

    @Test func microphoneFailureFailsImmediately() {
        audio.failOnStart = true
        let controller = makeController()
        controller.handle(.pressed)
        guard case .failed(.audio) = controller.state else {
            Issue.record("expected audio failure, got \(controller.state)")
            return
        }
    }

    @Test func pressWhileBusyIsIgnored() async {
        transcriber.session.finishDelay = .milliseconds(100)
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        controller.handle(.pressed)          // user presses again while transcribing
        await controller.currentTask?.value

        #expect(audio.startCount == 1)
        #expect(injector.injected.count == 1)
        #expect(controller.state == .idle)
    }

    @Test func canStartAgainAfterFailure() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))

        controller.handle(.pressed)
        #expect(controller.state == .listening)
        #expect(audio.startCount == 2)
    }

    @Test func audioBeforeSessionReadyIsStillTranscribed() async {
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(.pressed)
        audio.emit([0.1])
        audio.emit([0.2])
        controller.handle(.released)         // before makeSession returned
        await controller.currentTask?.value

        #expect(transcriber.session.appended == [[0.1], [0.2]])
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func showsPreparingModelWhenTranscriberIsNotReady() async {
        transcriber.isReady = false
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(recorder.states.contains(.preparingModel))
    }

    @Test func maxDurationAutoReleases() async throws {
        let controller = makeController(maxDuration: .milliseconds(50))
        controller.handle(.pressed)
        audio.emit([0.4])
        try await Task.sleep(for: .milliseconds(150))
        await controller.currentTask?.value

        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func quickTapRightAfterReleaseCannotStartSecondRecording() async {
        // Review I1: release, then a <250 ms tap (→ .cancelled) and another press while
        // the first dictation is still finishing must not start a second recording.
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(.pressed)
        audio.emit([0.1])
        controller.handle(.released)
        controller.handle(.cancelled)
        controller.handle(.pressed)
        await controller.currentTask?.value

        #expect(audio.startCount == 1)
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func captureEndingUnexpectedlyFinishesDictation() async throws {
        // Review I2: the mic stream ends on its own (device change) while still listening →
        // transcribe what we have instead of showing "Listening" forever.
        let controller = makeController()
        controller.handle(.pressed)
        audio.emit([0.3])
        audio.stop()                          // the recorder gave up, not the user
        try await Task.sleep(for: .milliseconds(50))
        await controller.currentTask?.value

        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func releaseWhenIdleIsIgnored() {
        let controller = makeController()
        controller.handle(.released)
        controller.handle(.cancelled)
        #expect(controller.state == .idle)
        #expect(audio.startCount == 0)
    }
}
