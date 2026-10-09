import AppKit
import Testing
@testable import Injection

@MainActor
struct AXSelectionReaderTests {
    let pasteboard = NSPasteboard(name: .init("WiskaSelectionTests-\(UUID().uuidString)"))

    func reader(ax: String?, copies: String?) -> AXSelectionReader {
        AXSelectionReader(pasteboard: pasteboard, accessibilitySelection: { ax }, sendCopy: { [pasteboard] in
            guard let copies else { return }
            pasteboard.clearContents()
            pasteboard.setString(copies, forType: .string)
        }, copyTimeout: .milliseconds(100))
    }

    @Test func accessibilityAnswerWins() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: "selected", copies: "copied").selectedText() == "selected")
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    @Test func copyFallbackReturnsTextAndRestoresTheClipboard() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: nil, copies: "copied").selectedText() == "copied")
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    @Test func noChangeRestoresAndReturnsNil() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: nil, copies: nil).selectedText() == nil)
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    @Test func whitespaceIsNoSelection() async {
        #expect(await reader(ax: "  \n ", copies: nil).selectedText() == nil)
        #expect(await reader(ax: nil, copies: "   ").selectedText() == nil)
    }

    /// An app that copies after Wiska stopped waiting must not leave the selection on the clipboard.
    @Test func lateCopyIsUndone() async throws {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        let reader = AXSelectionReader(pasteboard: pasteboard, accessibilitySelection: { nil }, sendCopy: { [pasteboard] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                pasteboard.clearContents()
                pasteboard.setString("late selection", forType: .string)
            }
        }, copyTimeout: .milliseconds(100))
        #expect(await reader.selectedText() == nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    /// Nothing copied: the clipboard is left exactly as it was (not rewritten).
    @Test func noCopyLeavesTheClipboardUntouched() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        let before = pasteboard.changeCount
        #expect(await reader(ax: nil, copies: nil).selectedText() == nil)
        #expect(pasteboard.changeCount == before)
    }

    /// VS Code (and Cursor) copy the whole line when nothing is selected; they mark it inside
    /// Chromium's custom clipboard data (UTF-16) — that's no selection.
    @Test func editorLineCopyIsNoSelection() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        let marker = #"vscode-editor-data{"version":1,"isFromEmptySelection":true,"mode":"swift"}"#
        let reader = AXSelectionReader(pasteboard: pasteboard, accessibilitySelection: { "" }, sendCopy: { [pasteboard] in
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString("let x = 1\n", forType: .string)
            item.setData(marker.data(using: .utf16LittleEndian)!, forType: .init("org.chromium.web-custom-data"))
            pasteboard.writeObjects([item])
        }, copyTimeout: .milliseconds(100))
        #expect(await reader.selectedText() == nil)
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    /// Wiska's own paste right after a failed command must not be undone by the late-copy watch.
    @Test func wiskasOwnWriteStopsTheLateCopyWatch() async throws {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: nil, copies: nil).selectedText() == nil)   // starts the watch
        try await ClipboardCopier(pasteboard: pasteboard).inject("dictated text")
        try await Task.sleep(for: .milliseconds(300))
        #expect(pasteboard.string(forType: .string) == "dictated text")
    }
}
