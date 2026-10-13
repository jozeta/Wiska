import AppKit
import Audio
import Core
import Dictation
import SwiftUI
import UniformTypeIdentifiers

enum TranscribeFileWindow {
    static let id = "transcribe-file"
    static let title = "Transcribe"

    static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: id)
        DispatchQueue.main.async {
            NSApp.windows.first { $0.title == title }?.orderFrontRegardless()
        }
    }
}

/// A recording (voice memo, meeting, interview) to text, with the speech engine dictation uses.
/// Everything runs on this Mac; nothing is kept in History.
struct TranscribeFileView: View {
    let model: AppModel

    private enum Phase: Equatable {
        case idle
        case recording
        case loading
        case transcribing(Double)
        case cleaningUp(Double)
        case done
        case failed(String)
    }

    @State private var phase = Phase.idle
    @State private var file: URL?
    @State private var language = LanguageChoice.automatic
    @State private var text = ""
    @State private var summary = ""
    @State private var task: Task<Void, Never>?
    @State private var dropTargeted = false
    @State private var permissionMissing = false
    @AppStorage("transcribeFileCleanUp") private var cleanUp = true

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Picker("Transcribe", selection: $model.transcribeMode) {
                Text("Audio File").tag(AppModel.TranscribeMode.file)
                Text("Meeting").tag(AppModel.TranscribeMode.meeting)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .disabled(isBusy || phase == .recording)
            HStack {
                if model.transcribeMode == .file {
                    Button("Choose File…", action: choose)
                        .disabled(isBusy)
                    Text(file?.lastPathComponent ?? "or drop an audio file here")
                        .foregroundStyle(file == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    meetingControls
                }
                Spacer()
                Toggle("Clean up", isOn: $cleanUp)
                    .help("Remove fillers and fix punctuation, as for a dictation (words like “new line” stay words)")
                    .disabled(isBusy)
                Picker("Language", selection: $language) {
                    Text("Auto-detect").tag(LanguageChoice.automatic)
                    ForEach(model.settings.enabledLanguages, id: \.self) { language in
                        Text("\(language.flag) \(language.displayName)").tag(LanguageChoice.fixed(language))
                    }
                }
                .fixedSize()
                .disabled(isBusy)
            }
            status
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if text.isEmpty && !isBusy && phase != .recording {
                        Text(model.transcribeMode == .file
                             ? "The text appears here. Audio up to three hours: m4a, mp3, wav, aiff, caf…"
                             : "Records a call or meeting: your microphone is “You”, the Mac’s sound (Zoom, Teams, FaceTime…) is “Others”. Use headphones for a clean split. Tell the others you’re recording.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: dropTargeted ? 2 : 0))
            HStack {
                Text("Uses your speech engine settings; runs on this Mac and isn't saved in History.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)
                Button("Save…", action: save)
                    .disabled(text.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 380)
        .dropDestination(for: URL.self) { urls, _ in
            guard !isBusy, phase != .recording, let url = urls.first else { return false }
            model.transcribeMode = .file
            start(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .onDisappear {
            task?.cancel()
            if phase == .recording { Task { await model.discardMeeting() } }
        }
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .idle, .recording:
            if permissionMissing {
                HStack {
                    Label("Wiska needs Screen & System Audio Recording to hear the call.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
            }
        case .loading:
            HStack { ProgressView().controlSize(.small); Text("Reading the file…") }
        case .transcribing(let fraction):
            progressRow("Transcribing", fraction)
        case .cleaningUp(let fraction):
            progressRow("Cleaning up", fraction)
        case .done:
            Text(summary).font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private func progressRow(_ title: String, _ fraction: Double) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            ProgressView(value: fraction)
            Text("\(Int(fraction * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            Button("Stop") { task?.cancel() }
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .loading, .transcribing, .cleaningUp: true
        default: false
        }
    }

    /// Start / stop, the time so far, and a meter for each side.
    @ViewBuilder private var meetingControls: some View {
        if phase == .recording {
            Button("Stop & Transcribe", action: stopMeeting)
                .keyboardShortcut(.defaultAction)
            Button("Discard") {
                phase = .idle
                Task { await model.discardMeeting() }
            }
            TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                let started = model.meetingRecorder.startedAt ?? timeline.date
                let levels = model.meetingRecorder.levels
                HStack(spacing: 10) {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                    Text(Duration.seconds(timeline.date.timeIntervalSince(started))
                        .formatted(.time(pattern: .hourMinuteSecond)))
                        .monospacedDigit()
                    meter("You", levels.you)
                    meter("Others", levels.others)
                }
            }
        } else {
            Button("Start Recording", action: startMeeting)
                .disabled(isBusy)
        }
    }

    private func meter(_ label: String, _ level: Float) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Capsule().fill(.quaternary).frame(width: 50, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.accentColor).frame(width: 50 * CGFloat(level), height: 5)
                }
        }
    }

    private func startMeeting() {
        permissionMissing = false
        text = ""
        Task {
            do {
                try await model.meetingRecorder.start()
                phase = .recording
            } catch {
                permissionMissing = true
                phase = .idle
            }
        }
    }

    private func stopMeeting() {
        phase = .loading
        let language = language
        let cleanUp = cleanUp
        task = Task {
            let started = ContinuousClock.now
            do {
                // Work in progress: speaker naming UI still to come; notes go above the transcript.
                let result = try await model.finishMeeting(language: language, cleanUp: cleanUp,
                                                           identifySpeakers: model.speakerModel.isInstalled,
                                                           writeNotes: true) { step, fraction in
                    phase = step == .cleaningUp ? .cleaningUp(fraction) : .transcribing(fraction)
                }
                let transcript = MeetingTranscription.transcript(result.segments)
                text = result.notes.map { "Notes\n\n\($0)\n\nTranscript\n\n\(transcript)" } ?? transcript
                let seconds = Int((ContinuousClock.now - started).seconds.rounded())
                summary = text.isEmpty ? "No speech found." : "\(Log.words(text).formatted()) words in \(seconds) s"
                phase = .done
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(TranscribeFileView.message(for: error))
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(url)
    }

    private func start(_ url: URL) {
        file = url
        text = ""
        phase = .loading
        let language = language
        let cleanUp = cleanUp
        task = Task {
            let started = ContinuousClock.now
            do {
                let result = try await model.transcribeFile(url, language: language, cleanUp: cleanUp) { step, fraction in
                    phase = step == .transcribing ? .transcribing(fraction) : .cleaningUp(fraction)
                }
                text = result.text
                let seconds = Int((ContinuousClock.now - started).seconds.rounded())
                let heard = result.language.map { " · \($0.flag) \($0.displayName)" } ?? ""
                summary = result.text.isEmpty ? "No speech found."
                    : "\(Log.words(result.text).formatted()) words in \(seconds) s\(heard)"
                phase = .done
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(TranscribeFileView.message(for: error))
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = model.transcribeMode == .meeting
            ? "Meeting \(Date().formatted(.iso8601.year().month().day())).txt"
            : (file?.deletingPathExtension().lastPathComponent ?? "Transcript") + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed("Couldn't save: \(error.localizedDescription)")
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case AudioFileLoader.LoadError.tooLong: "The recording is longer than three hours."
        case let error as NSError where error.domain == NSOSStatusErrorDomain || error.domain == "com.apple.coreaudio.avfaudio":
            "That file isn't audio Wiska can read."
        default: "Couldn't transcribe: \(error.localizedDescription)"
        }
    }
}
