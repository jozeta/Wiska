import Audio
import Core
import Dictation
import SwiftUI

/// Settings → Speech → Compare on my voice: read the sentences once, every installed engine
/// transcribes the same recording. Nothing is stored.
struct VoiceCompareView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = MicrophoneRecorder()
    @State private var samples: [Float] = []
    @State private var recording = false
    @State private var running = false
    @State private var collect: Task<Void, Never>?
    @State private var results: [(name: String, text: String, wer: Double, time: Duration)] = []
    @State private var micError: String?

    private static let maxSamples = 60 * 16_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare on my voice").font(.headline)
            Text("Press Record, read these sentences aloud at your normal pace, then press Stop.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(VoiceBenchmark.sentences.enumerated()), id: \.offset) { index, sentence in
                    Text("\(index + 1). \(sentence)")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(recording ? "Stop" : "Record") { recording ? stop() : start() }
                    .disabled(running)
                if recording { Text("Recording… \(samples.count / 16_000) s").font(.caption).foregroundStyle(.secondary) }
                if running { ProgressView().controlSize(.small); Text("Transcribing…").font(.caption) }
            }
            if let micError {
                Text(micError).font(.caption).foregroundStyle(.red)
            }
            List(results, id: \.name) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(result.name).bold()
                        Spacer()
                        Text("\(Int((result.wer * 100).rounded())) % word errors · \(result.time.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(result.text).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("Nothing is saved. Lower word errors is better.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { stopRecording(); dismiss() }
            }
        }
        .padding(16)
        .frame(width: 680, height: 600)
        .onDisappear { stopRecording() }
    }

    private func start() {
        samples = []
        results = []
        micError = nil
        guard let capture = try? recorder.start() else {
            micError = "Couldn't start the microphone. Allow Wiska in System Settings → Privacy & Security → Microphone."
            return
        }
        recording = true
        collect = Task { @MainActor in
            for await chunk in capture.chunks {
                samples += chunk.samples
                if samples.count >= Self.maxSamples { stop(); break }
            }
        }
    }

    private func stopRecording() {
        recorder.stop()
        collect?.cancel()
        recording = false
    }

    private func stop() {
        stopRecording()
        guard !samples.isEmpty else { return }
        let recorded = samples
        running = true
        Task { @MainActor in
            for engine in model.voiceEngines() {
                let start = ContinuousClock.now
                let text = (try? await engine.transcribe(recorded)) ?? "(failed)"
                results.append((engine.name, text,
                                VoiceBenchmark.wordErrorRate(reference: VoiceBenchmark.reference, hypothesis: text),
                                ContinuousClock.now - start))
            }
            running = false
            // Compare ran KB-Whisper with the toggle off: don't keep ~1.5 GB loaded for 30 minutes.
            if !model.settings.useKBWhisper { model.kbWhisper.unload() }
        }
    }
}
