import Testing
@testable import VaakyaCore

@Suite struct DictionaryExporterTests {
    @Test func encodeDecodeRoundTrip() throws {
        let snapshot = DictionarySnapshot(
            entries: [DictionaryEntryRecord(term: "Ananya", kind: "name", source: "manual", timesSeen: 1)],
            rules: [ReplacementRuleRecord(match: "vakya", replacement: "vaakya",
                                          matchKind: "exact_ci", source: "manual",
                                          status: "active")])
        let data = try DictionaryExporter.encode(snapshot)
        let decoded = try DictionaryExporter.decode(data)
        #expect(decoded == snapshot)
    }

    @Test func exportThenWipeThenImportYieldsIdenticalBehavior() throws {
        let source = try VaakyaDatabase()
        try source.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "vaakya"),
                                         source: "manual", status: "active")
        try source.upsertDictionaryEntry(term: "Ananya", kind: "name", source: "manual", status: "active")
        try source.insertDictation(timestamp: "t", rawText: "hi", finalText: "hi")

        let snapshot = try DictionaryExporter.snapshot(from: source)
        let data = try DictionaryExporter.encode(snapshot)

        // Fresh DB, import snapshot.
        let restored = try VaakyaDatabase()
        try DictionaryExporter.importSnapshot(try DictionaryExporter.decode(data), into: restored)

        let restoredRules = try restored.activeRules()
        let sourceRules = try source.activeRules()
        let restoredEntries = try restored.dictionaryEntries()
        let sourceEntries = try source.dictionaryEntries()
        #expect(restoredRules == sourceRules)
        #expect(restoredEntries == sourceEntries)
        // Dictations are NOT part of the vocabulary export (plan §5.7 scope).
        #expect(try restored.dictations().isEmpty)
    }
}
