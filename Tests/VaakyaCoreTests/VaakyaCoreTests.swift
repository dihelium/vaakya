import Testing
@testable import VaakyaCore

@Suite struct VaakyaCoreSmokeTests {
    @Test func versionIsSet() {
        #expect(!VaakyaCore.version.isEmpty)
    }
}
