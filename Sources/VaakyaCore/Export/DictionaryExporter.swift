import Foundation

/// One JSON-able snapshot of the dictionary + rules for backup / move-to-new-machine
/// (plan §5.7 / task 4.4).
public struct DictionarySnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let exportedAt: String
    public let entries: [DictionaryEntryRecord]
    public let rules: [ReplacementRuleRecord]

    public init(version: Int = DictionarySnapshot.currentVersion,
                exportedAt: String = ISO8601DateFormatter().string(from: Date()),
                entries: [DictionaryEntryRecord],
                rules: [ReplacementRuleRecord]) {
        self.version = version
        self.exportedAt = exportedAt
        self.entries = entries
        self.rules = rules
    }
}

public enum DictionaryExporter {
    /// Capture the current dictionary + rules (any status) from a database.
    public static func snapshot(from db: VaakyaDatabase) throws -> DictionarySnapshot {
        let entries = try db.dictionaryEntries()
        let rules = try db.rules()
        return DictionarySnapshot(entries: entries, rules: rules)
    }

    public static func encode(_ snapshot: DictionarySnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> DictionarySnapshot {
        try JSONDecoder().decode(DictionarySnapshot.self, from: data)
    }

    /// Replace the dictionary + rules with the snapshot's contents (approval assumed —
    /// this is the "restore from backup" path). Existing rows are wiped first.
    public static func importSnapshot(_ snapshot: DictionarySnapshot, into db: VaakyaDatabase) throws {
        try db.queue.write { d in
            try d.execute(sql: "DELETE FROM dictionary_entries")
            try d.execute(sql: "DELETE FROM replacement_rules")
            for entry in snapshot.entries {
                var entry = entry
                try entry.insert(d)
            }
            for rule in snapshot.rules {
                var rule = rule
                try rule.insert(d)
            }
        }
    }
}
