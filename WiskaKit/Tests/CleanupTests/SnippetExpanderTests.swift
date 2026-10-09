import Core
import Testing
@testable import Cleanup

struct SnippetExpanderTests {
    static let signature = Snippet(name: "signature", aliases: ["signatur"], text: "Best regards,\nJohan")
    static let address = Snippet(name: "address", aliases: ["adress"], text: "Storgatan 1, 111 22 Stockholm")
    static let mailSignature = Snippet(name: "mail signature", text: "— J")
    let english = Language.english.formatRules

    func expand(_ text: String, _ snippets: [Snippet] = [signature, address],
                rules: FormatRules = Language.english.formatRules) -> String {
        let extracted = SnippetExpander.extract(text, snippets: snippets, rules: rules)
        return SnippetExpander.fill(extracted.text, slots: extracted.slots)
    }

    @Test func singleLineSnippetGoesInline() {
        #expect(expand("send it to insert my address") == "send it to Storgatan 1, 111 22 Stockholm")
        #expect(expand("send it to insert my address.") == "send it to Storgatan 1, 111 22 Stockholm.")
    }

    @Test func multiLineSnippetGetsItsOwnLines() {
        #expect(expand("thanks for the help insert my signature") == "thanks for the help\nBest regards,\nJohan")
        #expect(expand("insert my signature") == "Best regards,\nJohan")
    }

    @Test func swedishTrigger() {
        #expect(expand("tack för hjälpen infoga min signatur", rules: Language.swedish.formatRules)
                == "tack för hjälpen\nBest regards,\nJohan")
    }

    @Test func wholeDictationIsTheName() {
        #expect(expand("my address") == "Storgatan 1, 111 22 Stockholm")
        #expect(expand("My address.") == "Storgatan 1, 111 22 Stockholm")
    }

    @Test func proseDoesNotTrigger() {
        #expect(expand("my address changed last week") == "my address changed last week")
        #expect(expand("insert my poem here") == "insert my poem here")
    }

    @Test func closeMishearingsMatch() {
        #expect(expand("insert my signatre") == "Best regards,\nJohan")
        #expect(expand("insert my signatures") == "Best regards,\nJohan")
        #expect(expand("insert addres") == "Storgatan 1, 111 22 Stockholm")
    }

    @Test func longestNameWins() {
        #expect(expand("insert my mail signature", [Self.signature, Self.mailSignature]) == "— J")
    }

    @Test func keepsExistingLines() {
        #expect(expand("first line\nsend it to insert my address") == "first line\nsend it to Storgatan 1, 111 22 Stockholm")
    }

    @Test func placeholderLinesAreRecognised() {
        let extracted = SnippetExpander.extract("thanks insert my signature", snippets: [Self.signature], rules: english)
        #expect(extracted.text == "thanks\nwiskasnippet1")
        #expect(SnippetExpander.isPlaceholderLine("wiskasnippet1"))
        #expect(SnippetExpander.isPlaceholderLine(" Wiskasnippet1. "))
        #expect(!SnippetExpander.isPlaceholderLine("thanks wiskasnippet1"))
        #expect(SnippetExpander.placeholders(in: "Send to Wiskasnippet2.") == ["wiskasnippet2"])
    }

    @Test func noSnippetsLeavesTheTextAlone() {
        #expect(expand("insert my signature", []) == "insert my signature")
    }

    /// A snippet that ends in punctuation keeps exactly its own: no "!." or "..".
    @Test func snippetsOwnPunctuationWins() {
        let closing = Snippet(name: "closing", text: "See you soon!")
        #expect(expand("insert my closing.", [closing]) == "See you soon!")
        #expect(expand("thanks insert my closing.", [closing]) == "thanks See you soon!")
        let short = Snippet(name: "address", text: "Storgatan 1.")
        #expect(expand("send it to insert my address.", [short]) == "send it to Storgatan 1.")
        let filled = SnippetExpander.fill("Thanks wiskasnippet1.", slots: ["wiskasnippet1": closing])
        #expect(filled == "Thanks See you soon!")
    }
}
