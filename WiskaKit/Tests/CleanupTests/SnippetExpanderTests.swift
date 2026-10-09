import Core
import Testing
@testable import Cleanup

struct SnippetExpanderTests {
    static let signature = Snippet(phrases: ["insert my signature", "infoga min signatur"], text: "Best regards,\nJohan")
    static let address = Snippet(phrases: ["insert my address"], text: "Storgatan 1, 111 22 Stockholm")
    static let mailSignature = Snippet(phrases: ["insert my mail signature"], text: "— J")

    func expand(_ text: String, _ snippets: [Snippet] = [signature, address]) -> String {
        SnippetPreview.expand(text, snippets: snippets)
    }

    @Test func singleLineSnippetGoesInline() {
        #expect(expand("send it to insert my address") == "send it to Storgatan 1, 111 22 Stockholm")
        #expect(expand("Send it to: Insert my address.") == "Send it to: Storgatan 1, 111 22 Stockholm.")
    }

    @Test func multiLineSnippetGetsItsOwnLines() {
        #expect(expand("thanks for the help, insert my signature") == "thanks for the help,\nBest regards,\nJohan")
        #expect(expand("Insert my signature.") == "Best regards,\nJohan")
    }

    @Test func anotherPhraseForTheSameSnippet() {
        #expect(expand("tack för hjälpen infoga min signatur") == "tack för hjälpen\nBest regards,\nJohan")
    }

    @Test func onlyTheExactPhraseTriggers() {
        #expect(expand("my address changed last week") == "my address changed last week")
        #expect(expand("insert the address here") == "insert the address here")
        #expect(expand("insert my poem here") == "insert my poem here")
    }

    @Test func closeMishearingsMatch() {
        #expect(expand("insert my signatre") == "Best regards,\nJohan")
        #expect(expand("insert my signatures") == "Best regards,\nJohan")
        #expect(expand("insert my adress") == "Storgatan 1, 111 22 Stockholm")
    }

    @Test func longestPhraseWins() {
        #expect(expand("insert my mail signature", [Self.signature, Self.mailSignature]) == "— J")
    }

    @Test func keepsExistingLines() {
        #expect(expand("first line\nsend it to insert my address") == "first line\nsend it to Storgatan 1, 111 22 Stockholm")
    }

    @Test func placeholderLinesAreRecognised() {
        let extracted = SnippetExpander.extract("thanks insert my signature", snippets: [Self.signature])
        #expect(extracted.text == "thanks\nwiskasnippet1")
        #expect(SnippetExpander.isPlaceholderLine("wiskasnippet1"))
        #expect(SnippetExpander.isPlaceholderLine(" Wiskasnippet1. "))
        #expect(!SnippetExpander.isPlaceholderLine("thanks wiskasnippet1"))
        #expect(SnippetExpander.placeholders(in: "Send to Wiskasnippet2.") == ["wiskasnippet2"])
    }

    @Test func snippetsWithoutPhraseOrTextNeverTrigger() {
        #expect(expand("insert my name", [Snippet(phrases: [], text: "insert my name")]) == "insert my name")
        #expect(expand("insert my name", [Snippet(phrases: ["insert my name"], text: "")]) == "insert my name")
        #expect(expand("insert my signature", []) == "insert my signature")
    }

    /// A snippet that ends in punctuation keeps exactly its own: no "!." or "..".
    @Test func snippetsOwnPunctuationWins() {
        let closing = Snippet(phrases: ["insert my closing"], text: "See you soon!")
        #expect(expand("insert my closing.", [closing]) == "See you soon!")
        #expect(expand("thanks insert my closing.", [closing]) == "thanks See you soon!")
        let short = Snippet(phrases: ["insert my address"], text: "Storgatan 1.")
        #expect(expand("send it to insert my address.", [short]) == "send it to Storgatan 1.")
        let filled = SnippetExpander.fill("Thanks wiskasnippet1.", slots: ["wiskasnippet1": closing])
        #expect(filled == "Thanks See you soon!")
    }

    /// Without a trigger the text is returned untouched (spacing included).
    @Test func noTriggerLeavesTheTextExactly() {
        #expect(expand("a  b\tc") == "a  b\tc")
    }
}
