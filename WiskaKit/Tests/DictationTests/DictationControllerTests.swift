import Core
import Testing
@testable import Dictation

@MainActor
struct DictationControllerTests {
    let audio = FakeAudio()
    let transcriber = FakeTranscriber()
    let cleaner = FakeCleaner()
    let injector = FakeInjector()

    func makeController(maxDuration: Duration = .seconds(300), releaseTail: Duration = .zero,
                        provider: (@MainActor (LanguageChoice) -> any Transcriber)? = nil) -> DictationController {
        let transcriber = transcriber
        return DictationController(
            audio: audio, transcriber: provider ?? { _ in transcriber }, cleaner: cleaner, injector: injector,
            contextProvider: { DictationContext(appBundleID: "com.apple.TextEdit") },
            maxDuration: maxDuration, noticeDuration: .seconds(60), releaseTail: releaseTail
        )
    }

    let en = DictationCommand.start(.fixed(.english))

    @Test func happyPathTranscribesCleansAndInjects() async {
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }

        controller.handle(en)
        #expect(controller.state == .listening)
        audio.emit([0.1, 0.2])
        audio.emit([0.3])
        controller.handle(.finish)
        await controller.currentTask?.value

        #expect(transcriber.session.appended == [[0.1, 0.2], [0.3]])
        #expect(transcriber.languages == [.fixed(.english)])
        #expect(cleaner.contexts == [DictationContext(appBundleID: "com.apple.TextEdit", language: .english)])
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(recorder.states == [.listening, .transcribing, .cleaning, .injecting, .idle])
        #expect(controller.lastLatency != nil)
    }

    @Test func startPassesLanguageChoiceToTranscriber() async {
        let controller = makeController()
        controller.handle(.start(.automatic))
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(transcriber.languages == [.automatic])
        #expect(controller.currentChoice == .automatic)
    }

    @Test func automaticDictationReportsDetectedLanguageAfterIdle() async {
        transcriber.session.language = .swedish
        let controller = makeController()
        let detected = Box<[Language]>([])
        let stateAtCallback = Box<DictationController.State?>(nil)
        controller.onLanguageDetected = { [unowned controller] language in
            detected.value.append(language)
            stateAtCallback.value = controller.state
        }
        controller.handle(.start(.automatic))
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(detected.value == [.swedish])
        #expect(stateAtCallback.value == .idle)
    }

    @Test func fixedDictationDoesNotReportDetectedLanguage() async {
        let controller = makeController()
        let called = Box(false)
        controller.onLanguageDetected = { _ in called.value = true }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(!called.value)
    }

    @Test func transcriberIsChosenAtStartNotAtFinish() async {
        let other = FakeTranscriber()
        let useOther = Box(false)
        let first = transcriber
        let controller = makeController(provider: { _ in useOther.value ? other : first })
        controller.handle(en)
        useOther.value = true                // user switches engine mid-hold
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(first.languages.count == 1)
        #expect(other.languages.isEmpty)
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func releaseTailKeepsCapturingBriefly() async throws {
        let controller = makeController(releaseTail: .milliseconds(150))
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.finish)
        try await Task.sleep(for: .milliseconds(30))
        audio.emit([0.9])                    // the last syllable, after fn-up
        await controller.currentTask?.value
        #expect(transcriber.session.appended == [[0.1], [0.9]])
    }

    @Test func levelsAreTrackedForTheWaveform() async {
        let controller = makeController()
        controller.handle(en)
        audio.emitLevel(0.5)
        audio.emitLevel(0.7)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.levels == [0.5, 0.7])
        controller.handle(.finish)
        await controller.currentTask?.value
    }

    @Test func cancelDiscardsAudioAndInjectsNothing() async {
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.cancel)
        await controller.currentTask?.value
        #expect(controller.state == .idle)
        #expect(injector.injected.isEmpty)
        #expect(transcriber.session.cancelled)
    }

    @Test func switchLanguageRestartsTheRecordingInTheNewLanguage() async {
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.switchLanguage(.fixed(.swedish)))
        // Let the first recording's task notice its stream ended: it must not finish the new one.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!recorder.states.contains(.idle))
        #expect(controller.state == .listening)
        #expect(controller.currentChoice == .fixed(.swedish))
        audio.emit([0.2])
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(transcriber.languages == [.fixed(.english), .fixed(.swedish)])
        #expect(injector.injected.count == 1)
    }

    @Test func switchLanguageWhenNotListeningIsIgnored() async {
        let controller = makeController()
        controller.handle(.switchLanguage(.fixed(.swedish)))
        #expect(controller.state == .idle)
        #expect(transcriber.languages.isEmpty)
    }

    @Test func switchLanguagePassesTheNewChoiceToTheProvider() async {
        let choices = Box<[LanguageChoice]>([])
        let transcriber = transcriber
        let controller = makeController(provider: { choice in
            choices.value.append(choice)
            return transcriber
        })
        controller.handle(en)
        controller.handle(.switchLanguage(.fixed(.swedish)))
        controller.handle(.cancel)
        await controller.currentTask?.value
        #expect(choices.value == [.fixed(.english), .fixed(.swedish)])
    }

    @Test func recordUsesTheEngineThatProducedTheText() async {
        transcriber.session.engine = .parakeet   // FakeTranscriber itself reports .apple
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.first?.engine == .parakeet)
    }

    @Test func cleanerReceivesTheTranscriptLanguage() async {
        transcriber.session.language = .danish
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(cleaner.contexts.first?.language == .danish)
    }

    @Test func readinessIsJudgedForThisDictationsLanguage() async {
        transcriber.isReady = false                  // another ticked language is still downloading
        transcriber.readyChoices = [.fixed(.english)]
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(!recorder.states.contains(.preparingModel))
    }

    @Test func emptyTranscriptFailsWithNoSpeech() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))
        #expect(injector.injected.isEmpty)
    }

    @Test func transcriberErrorFails() async {
        transcriber.session.result = .failure(FakeError())
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        guard case .failed(.transcription) = controller.state else {
            Issue.record("expected transcription failure, got \(controller.state)")
            return
        }
    }

    @Test func secureInputFailsWithSecureInput() async {
        injector.error = .secureInputActive
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.secureInput))
    }

    @Test func microphoneFailureFailsImmediately() {
        audio.failOnStart = true
        let controller = makeController()
        controller.handle(en)
        guard case .failed(.audio) = controller.state else {
            Issue.record("expected audio failure, got \(controller.state)")
            return
        }
    }

    @Test func startWhileBusyIsIgnored() async {
        transcriber.session.finishDelay = .milliseconds(100)
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        controller.handle(en)
        await controller.currentTask?.value
        #expect(audio.startCount == 1)
        #expect(injector.injected.count == 1)
        #expect(controller.state == .idle)
    }

    @Test func canStartAgainAfterFailure() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))
        controller.handle(en)
        #expect(controller.state == .listening)
        #expect(audio.startCount == 2)
    }

    @Test func audioBeforeSessionReadyIsStillTranscribed() async {
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.1])
        audio.emit([0.2])
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(transcriber.session.appended == [[0.1], [0.2]])
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func showsPreparingModelWhenTranscriberIsNotReady() async {
        transcriber.isReady = false
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(recorder.states.contains(.preparingModel))
    }

    @Test func maxDurationAutoFinishes() async throws {
        let controller = makeController(maxDuration: .milliseconds(50))
        controller.handle(en)
        audio.emit([0.4])
        try await Task.sleep(for: .milliseconds(150))
        await controller.currentTask?.value
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func finishOrCancelWhenIdleIsIgnored() {
        let controller = makeController()
        controller.handle(.finish)
        controller.handle(.cancel)
        #expect(controller.state == .idle)
        #expect(audio.startCount == 0)
    }

    @Test func strayCancelAndStartRightAfterFinishCannotStartSecondRecording() async {
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.finish)
        controller.handle(.cancel)
        controller.handle(en)
        await controller.currentTask?.value
        #expect(audio.startCount == 1)
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func captureEndingUnexpectedlyFinishesDictation() async throws {
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.3])
        audio.stop()
        try await Task.sleep(for: .milliseconds(50))
        await controller.currentTask?.value
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func startPrewarmsTheCleaner() async {
        let controller = makeController()
        controller.handle(en)
        #expect(cleaner.prewarmCount == 1)
        controller.handle(.cancel)
        await controller.currentTask?.value
    }

    @Test func cleanupLeavingNothingIsNoSpeech() async {
        // Review I1: saying only "scratch that" must not paste an empty string.
        cleaner.output = "  \n"
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))
        #expect(injector.injected.isEmpty)
    }

    func recording(_ controller: DictationController) -> Box<[DictationRecord]> {
        let records = Box<[DictationRecord]>([])
        controller.onDictationFinished = { records.value.append($0) }
        return records
    }

    @Test func successfulDictationIsRecorded() async {
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.count == 1)
        let record = records.value[0]
        #expect(record.rawText == "hello world")
        #expect(record.finalText == "cleaned: hello world")
        #expect(record.pasted)
        #expect(record.appBundleID == "com.apple.TextEdit")
        #expect(record.language == .english)
        #expect(record.engine == .apple)
    }

    @Test func failedPasteIsRecordedForRescue() async {
        injector.error = .eventCreationFailed
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.map(\.pasted) == [false])
        #expect(records.value.first?.finalText == "cleaned: hello world")
    }

    @Test func secureInputNoSpeechAndCancelAreNotRecorded() async {
        let controller = makeController()
        let records = recording(controller)

        injector.error = .secureInputActive
        controller.handle(en); controller.handle(.finish); await controller.currentTask?.value

        injector.error = nil
        transcriber.session.result = .success("")
        controller.handle(en); controller.handle(.finish); await controller.currentTask?.value

        controller.handle(en); controller.handle(.cancel); await controller.currentTask?.value
        #expect(records.value.isEmpty)
    }

    @Test func recordCallbackDoesNotAffectState() async {
        let controller = makeController()
        controller.onDictationFinished = { _ in }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .idle)
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func recordCarriesSpokenDuration() async {
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        audio.emit(Array(repeating: 0, count: 16_000))
        audio.emit(Array(repeating: 0, count: 8_000))
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.first?.duration == 1.5)
    }
}
