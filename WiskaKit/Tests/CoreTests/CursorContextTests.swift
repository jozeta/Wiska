import Testing
@testable import Core

struct CursorContextTests {
    @Test func marksTheCursor() {
        #expect(CursorContext.window(text: "one two three", cursor: 4) == "one [cursor]two three")
        #expect(CursorContext.window(text: "Hi Anna,\n\n", cursor: 10) == "Hi Anna,\n\n[cursor]")
        #expect(CursorContext.window(text: "Hello", cursor: 0) == "[cursor]Hello")
    }

    @Test func emptyOrBlankTextHasNoContext() {
        #expect(CursorContext.window(text: "", cursor: 0) == "")
        #expect(CursorContext.window(text: " \n ", cursor: 1) == "")
    }

    @Test func cutsAtWordBoundaries() {
        // 7 characters before the cursor: "a delta" would cut "gamma" mid-word, so only "delta" stays.
        #expect(CursorContext.window(text: "alpha beta gamma delta", cursor: 22, limit: 8) == "delta[cursor]")
        // After the cursor: "alpha beta" fits in 12; "gamma" would be cut, so it goes.
        #expect(CursorContext.window(text: "alpha beta gamma delta", cursor: 0, limit: 12) == "[cursor]alpha beta")
        // A cut exactly at a space keeps the whole word.
        #expect(CursorContext.window(text: "aa bb cc", cursor: 8, limit: 2) == "cc[cursor]")
    }

    @Test func limitDefaultsTo1500EachSide() {
        let side = String(repeating: "word ", count: 1_000)   // 5,000 characters
        let window = CursorContext.window(text: side + side, cursor: side.utf16.count)
        let parts = window.components(separatedBy: CursorContext.marker)
        #expect(parts.count == 2)
        #expect(parts[0].count <= 1_500 && parts[0].count > 1_400)
        #expect(parts[1].count <= 1_500 && parts[1].count > 1_400)
    }

    /// AX reports the cursor in UTF-16 units: an emoji (2 units) or å before it must not shift it.
    @Test func cursorIsAUTF16Offset() {
        let text = "Hej 👋 på dig"
        let cursor = "Hej 👋 ".utf16.count
        #expect(CursorContext.window(text: text, cursor: cursor) == "Hej 👋 [cursor]på dig")
        #expect(CursorContext.window(text: text, cursor: 999) == "Hej 👋 på dig[cursor]")   // clamped
    }
}

struct CursorContextReadRangeTests {
    /// Only the part of a long document around the cursor is fetched (UTF-16 units).
    @Test func readsAMarginAroundTheCursor() {
        #expect(CursorContext.readRange(cursor: 10_000, length: 0, count: 1_000_000) == (8_400, 3_200))
        #expect(CursorContext.readRange(cursor: 100, length: 0, count: 500) == (0, 500))
        #expect(CursorContext.readRange(cursor: 900, length: 50, count: 1_000) == (0, 1_000))
        #expect(CursorContext.readRange(cursor: 5_000, length: 0, count: 2_000) == (400, 1_600))   // stale cursor: clamped
    }
}
