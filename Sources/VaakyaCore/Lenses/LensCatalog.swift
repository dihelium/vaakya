import Foundation

/// Loads lens Markdown from the app bundle, the source tree during tests,
/// and optional user-defined lenses under Application Support.
public enum LensCatalog {
    public static let bundledIDs = [
        "L0_raw_transcript",
        "L1_strict_decisions",
        "L2_actions_strict",
        "L5_technical_interview",
        "L5b_interview_self_debrief",
    ]

    public static func systemTrust() throws -> String {
        try loadResource(named: "_system_trust", subdirectory: nil)
            ?? loadResource(named: "_system_trust", subdirectory: "Lenses")
            ?? { throw LensCatalogError.missingSystemTrust }()
    }

    public static func allSpecs(userDirectory: URL? = nil) throws -> [LensSpec] {
        let trust = try systemTrust()
        let bundled = try bundledIDs.map { try loadBundledSpec(id: $0, systemTrust: trust) }
        let custom = try userDirectory.map { try CustomLensStore(directory: $0).allSpecs() } ?? []
        return bundled + custom
    }

    public static func loadSpec(id: String, userDirectory: URL? = nil) throws -> LensSpec {
        let trust = try systemTrust()
        if bundledIDs.contains(id) {
            return try loadBundledSpec(id: id, systemTrust: trust)
        }
        if let userDirectory {
            return try CustomLensStore(directory: userDirectory).load(id: id)
        }
        throw LensCatalogError.missingLens(id)
    }

    public static func defaultContextMarkdown() -> String {
        (try? loadResource(named: "interview_default", subdirectory: nil))
            ?? (try? loadResource(named: "interview_default", subdirectory: "Context"))
            ?? ""
    }

    public static func contextMarkdown(named name: String) -> String? {
        (try? loadResource(named: name, subdirectory: nil))
            ?? (try? loadResource(named: name, subdirectory: "Context"))
    }

    // MARK: - internals

    private static func loadBundledSpec(id: String, systemTrust: String) throws -> LensSpec {
        guard let text = try loadResource(named: id, subdirectory: nil)
                ?? loadResource(named: id, subdirectory: "Lenses") else {
            throw LensCatalogError.missingLens(id)
        }
        let (fields, body) = try LensFrontMatter.parse(text)
        let requires: Bool = {
            if let raw = fields["requires_llm"]?.lowercased() {
                return raw == "true" || raw == "1" || raw == "yes"
            }
            return true
        }()
        return LensSpec(
            id: fields["id"] ?? id,
            title: fields["title"] ?? id,
            requiresLLM: requires,
            minFidelity: fields["min_fidelity"] ?? "A1",
            defaultEgress: fields["default_egress"] ?? "B1",
            body: body,
            systemTrust: systemTrust,
            origin: .bundled)
    }

    private static func loadResource(named name: String, subdirectory: String?) throws -> String? {
        let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
            ?? sourceResourceURL(named: name, subdirectory: subdirectory)
        guard let url else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func sourceResourceURL(named name: String, subdirectory: String?) -> URL? {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Sources/VaakyaCore/Resources", isDirectory: true)
        if let subdirectory {
            url.appendPathComponent(subdirectory, isDirectory: true)
        }
        url.appendPathComponent(name)
        url.appendPathExtension("md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
