import Testing
@testable import Core

struct AppCatalogTests {
    @Test func builtInAppsHaveTheirCategory() {
        #expect(AppCatalog.category(for: "com.apple.MobileSMS") == .personal)
        #expect(AppCatalog.category(for: "com.tinyspeck.slackmacgap") == .work)
        #expect(AppCatalog.category(for: "com.apple.mail") == .email)
        #expect(AppCatalog.category(for: "com.apple.Terminal") == .code)
        #expect(AppCatalog.category(for: "com.mitchellh.ghostty") == .code)
    }

    @Test func unknownOrMissingAppIsOther() {
        #expect(AppCatalog.category(for: "com.example.unknown") == .other)
        #expect(AppCatalog.category(for: nil) == .other)
    }

    @Test func theUsersChoiceWins() {
        let overrides: [String: AppCategory] = ["com.apple.mail": .work, "com.example.notes": .personal]
        #expect(AppCatalog.category(for: "com.apple.mail", overrides: overrides) == .work)
        #expect(AppCatalog.category(for: "com.example.notes", overrides: overrides) == .personal)
    }

    @Test func defaultStyles() {
        #expect(AppCategory.personal.defaultStyle == .casual)
        #expect(AppCategory.work.defaultStyle == .casual)
        #expect(AppCategory.email.defaultStyle == .formal)
        #expect(AppCategory.other.defaultStyle == .formal)
        #expect(AppCategory.code.defaultStyle == nil)
    }

    @Test func contextDefaultsToOther() {
        #expect(DictationContext().category == .other)
        #expect(DictationContext(appBundleID: "x", category: .email).category == .email)
    }
}
