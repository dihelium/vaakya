import Foundation

/// Loads bundled lens Markdown from `VaakyaCore` resources.
public enum LensCatalog {
    public static func systemTrust() throws -> String {
        try loadResource(named: "_system_trust", subdirectory: nil)
            ?? loadResource(named: "_system_trust", subdirectory: "Lenses")
            ?? { throw LensCatalogError.missingSystemTrust }()
    }

    public static func allSpecs() throws -> [LensSpec] {
        let trust = try systemTrust()
        let ids = ["L0_raw_transcript", "L1_strict_decisions", "L2_actions_strict",
                   "L5_technical_interview", "L5b_interview_self_debrief"]
        return try ids.map { try loadSpec(id: $0, systemTrust: trust) }
    }

    public static func loadSpec(id: String) throws -> LensSpec {
        try loadSpec(id: id, systemTrust: try systemTrust())
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

    private static func loadSpec(id: String, systemTrust: String) throws -> LensSpec {
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
            systemTrust: systemTrust)
    }

    private static func loadResource(named name: String, subdirectory: String?) throws -> String? {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "md")
        guard let url else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
