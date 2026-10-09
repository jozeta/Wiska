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
}
