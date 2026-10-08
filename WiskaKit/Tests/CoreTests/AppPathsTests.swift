import Foundation
import Testing
@testable import Core

struct AppPathsTests {
    @Test func dataLivesInWiskaFolder() {
        #expect(AppPaths.supportDirectory.lastPathComponent == "Wiska")
        #expect(AppPaths.file("dictionary.json").path.hasSuffix("Application Support/Wiska/dictionary.json"))
    }

    @Test func logSubsystemIsWiska() {
        #expect(Log.subsystem == "Wiska")
    }
}
