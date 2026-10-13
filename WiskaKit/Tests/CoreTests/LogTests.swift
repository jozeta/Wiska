import Foundation
import Testing
@testable import Core

struct LogTests {
    private enum Plain: Error { case timedOut }
    private enum Carrying: Error { case failed(String) }
    private struct Described: Error, CustomStringConvertible {
        var description: String { "the dictated words" }
    }
    private enum DescribedCase: Error, CustomStringConvertible {
        case oops
        var description: String { "the dictated words" }
    }

    @Test func aPlainCaseIsNamed() {
        #expect(Log.summary(Plain.timedOut) == "Plain.timedOut")
    }

    @Test func aCaseWithAValueIsNamedWithoutTheValue() {
        #expect(Log.summary(Carrying.failed("the dictated words")) == "Carrying.failed")
    }

    @Test func aDescriptionIsNeverUsed() {
        #expect(!Log.summary(Described()).contains("dictated"))
        #expect(!Log.summary(DescribedCase.oops).contains("dictated"))
        #expect(Log.summary(Described()).hasPrefix("Described"))
    }

    @Test func aFoundationErrorGivesItsDomainAndCode() {
        #expect(Log.summary(URLError(.timedOut)) == "NSURLErrorDomain -1001")
    }

    @Test func wordCountsSplitOnWhitespace() {
        #expect(Log.words("one two\nthree  four") == 4)
        #expect(Log.words(nil) == 0)
    }
}
