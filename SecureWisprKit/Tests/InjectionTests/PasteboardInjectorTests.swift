import AppKit
import Testing
@testable import Core
@testable import Injection

@MainActor
final class RecordingKeySender: KeySender {
    let pasteboard: NSPasteboard
    var onPaste: (NSPasteboard) -> Void = { _ in }
    private(set) var seenAtPaste: [String?] = []
    private(set) var transientAtPaste: [Bool] = []

    init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    func sendPaste() throws {
        seenAtPaste.append(pasteboard.string(forType: .string))
        transientAtPaste.append(pasteboard.types?.contains(.init("org.nspasteboard.TransientType")) ?? false)
        onPaste(pasteboard)
    }
}

@MainActor
struct PasteboardInjectorTests {
    let pasteboard = NSPasteboard(name: .init("SecureWisprTests-\(UUID().uuidString)"))

    private func injector(_ sender: RecordingKeySender, secure: Bool = false) -> PasteboardInjector {
        PasteboardInjector(pasteboard: pasteboard, keySender: sender,
                           restoreDelay: .milliseconds(20), isSecureInputActive: { secure })
    }

    @Test func pastesTextThenRestoresPreviousClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let sender = RecordingKeySender(pasteboard: pasteboard)

        try await injector(sender).inject("dictated text")

        #expect(sender.seenAtPaste == ["dictated text"])
        #expect(sender.transientAtPaste == [true])
        #expect(pasteboard.string(forType: .string) == "previous")
    }

    @Test func skipsRestoreWhenSomethingElseWroteToClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let sender = RecordingKeySender(pasteboard: pasteboard)
        sender.onPaste = { pb in
            pb.clearContents()
            pb.setString("copied by user", forType: .string)
        }

        try await injector(sender).inject("dictated text")

        #expect(pasteboard.string(forType: .string) == "copied by user")
    }

    @Test func refusesSecureInputAndLeavesClipboardUntouched() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let sender = RecordingKeySender(pasteboard: pasteboard)

        await #expect(throws: InjectionError.secureInputActive) {
            try await injector(sender, secure: true).inject("secret")
        }
        #expect(sender.seenAtPaste.isEmpty)
        #expect(pasteboard.string(forType: .string) == "previous")
    }

    @Test func restoresNonTextContentExactly() async throws {
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(Data("custom".utf8), forType: custom)
        pasteboard.writeObjects([item])
        let before = PasteboardSnapshot.capture(pasteboard)

        try await injector(RecordingKeySender(pasteboard: pasteboard)).inject("text")

        #expect(PasteboardSnapshot.capture(pasteboard) == before)
        #expect(pasteboard.data(forType: .png) == png)
    }

    @Test func emptyClipboardStaysEmptyAfterPaste() async throws {
        pasteboard.clearContents()
        try await injector(RecordingKeySender(pasteboard: pasteboard)).inject("text")
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func pastesSwedishCharactersExactly() async throws {
        pasteboard.clearContents()
        let sender = RecordingKeySender(pasteboard: pasteboard)
        let text = "Hej! Kan du skicka rapporten – på fredag? Åsa, Ärla & Örjan."
        try await injector(sender).inject(text)
        #expect(sender.seenAtPaste == [text])
    }
}
