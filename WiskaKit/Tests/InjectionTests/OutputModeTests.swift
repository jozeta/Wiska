import AppKit
import Core
import Testing
@testable import Injection

@MainActor
final class RecordingInjector: TextInjector {
    private(set) var texts: [String] = []
    func inject(_ text: String) async throws { texts.append(text) }
}

@MainActor
struct OutputModeTests {
    let pasteboard = NSPasteboard(name: .init("WiskaOutputTests-\(UUID().uuidString)"))

    @Test func clipboardCopierLeavesTheTextOnTheClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        try await ClipboardCopier(pasteboard: pasteboard).inject("dictated text")
        #expect(pasteboard.string(forType: .string) == "dictated text")
        // A normal copy: clipboard managers may keep it, unlike the transient paste.
        #expect(pasteboard.types?.contains(.init("org.nspasteboard.TransientType")) != true)
    }

    @Test func switchingInjectorFollowsTheMode() async throws {
        let insert = RecordingInjector(), copy = RecordingInjector()
        var mode = OutputMode.insert
        let injector = SwitchingInjector(mode: { mode }, insert: insert, copy: copy)
        try await injector.inject("one")
        mode = .clipboard
        try await injector.inject("two")
        #expect(insert.texts == ["one"])
        #expect(copy.texts == ["two"])
    }

    @Test func modeNames() {
        #expect(OutputMode.insert.displayName == "Insert into the app")
        #expect(OutputMode.clipboard.displayName == "Copy to clipboard only")
    }
}
