import Foundation

/// A chat message used when composing lens prompts (JSON tags match OpenAI wire format).
public struct LensChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum LensOrigin: String, Equatable, Sendable {
    case bundled
    case custom
}

/// Parsed lens definition (Markdown file with YAML-like front matter).
public struct LensSpec: Equatable, Sendable {
    public var id: String
    public var title: String
    public var requiresLLM: Bool
    public var minFidelity: String
    public var defaultEgress: String
    public var body: String
    /// Shared trust rules prepended into the system message when requiresLLM.
    public var systemTrust: String
    public var origin: LensOrigin

    public init(id: String,
                title: String,
                requiresLLM: Bool = true,
                minFidelity: String = "A1",
                defaultEgress: String = "B1",
                body: String,
                systemTrust: String = "",
                origin: LensOrigin = .bundled) {
        self.id = id
        self.title = title
        self.requiresLLM = requiresLLM
        self.minFidelity = minFidelity
        self.defaultEgress = defaultEgress
        self.body = body
        self.systemTrust = systemTrust
        self.origin = origin
    }

    public var isCustom: Bool { origin == .custom }
}

/// Inputs for building a lens prompt (pure; no I/O).
public struct LensPromptInput: Equatable, Sendable {
    public var notesMarkdown: String
    public var transcriptMarkdown: String
    public var contextMarkdown: String

    public init(notesMarkdown: String = "",
                transcriptMarkdown: String,
                contextMarkdown: String = "") {
        self.notesMarkdown = notesMarkdown
        self.transcriptMarkdown = transcriptMarkdown
        self.contextMarkdown = contextMarkdown
    }
}

/// Front-matter fields written onto every model draft.
public struct LensDraftFrontMatter: Equatable, Sendable {
    public var status: String
    public var lensID: String
    public var model: String
    public var via: String
    public var createdAt: String
    public var packageID: String
    public var fidelity: String
    public var egress: String
    public var inputSHA256: String

    public init(status: String = "draft",
                lensID: String,
                model: String,
                via: String,
                createdAt: String,
                packageID: String,
                fidelity: String,
                egress: String,
                inputSHA256: String) {
        self.status = status
        self.lensID = lensID
        self.model = model
        self.via = via
        self.createdAt = createdAt
        self.packageID = packageID
        self.fidelity = fidelity
        self.egress = egress
        self.inputSHA256 = inputSHA256
    }

    public func renderYAML() -> String {
        """
        ---
        status: \(status)
        lens_id: \(lensID)
        model: \(model)
        via: \(via)
        created_at: \(createdAt)
        package_id: \(packageID)
        fidelity: \(fidelity)
        egress: \(egress)
        input_sha256: \(inputSHA256)
        ---
        """
    }
}

public enum LensFrontMatter {
    /// Parse simple `---` / `key: value` front matter. Returns (fields, body).
    public static func parse(_ text: String) throws -> (fields: [String: String], body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") || normalized.hasPrefix("---\r") else {
            return ([:], text)
        }
        let rest = String(normalized.dropFirst(4))
        guard let endRange = rest.range(of: "\n---") else {
            throw LensCatalogError.unclosedFrontMatter
        }
        let fmBlock = String(rest[..<endRange.lowerBound])
        var body = String(rest[endRange.upperBound...])
        if body.hasPrefix("\n") { body = String(body.dropFirst()) }

        var fields: [String: String] = [:]
        for line in fmBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        return (fields, body)
    }

    /// Rewrite only the `status:` field in an existing draft document.
    public static func promoteStatus(in markdown: String, to newStatus: String) throws -> String {
        let allowed: Set<String> = ["draft", "reviewed", "final"]
        guard allowed.contains(newStatus) else {
            throw LensCatalogError.invalidStatus(newStatus)
        }
        let (fields, body) = try parse(markdown)
        var updated = fields
        updated["status"] = newStatus
        // Preserve known order for readability.
        let order = ["status", "lens_id", "model", "via", "created_at",
                     "package_id", "fidelity", "egress", "input_sha256"]
        var lines = ["---"]
        var seen = Set<String>()
        for key in order {
            if let v = updated[key] {
                lines.append("\(key): \(v)")
                seen.insert(key)
            }
        }
        for (k, v) in updated.sorted(by: { $0.key < $1.key }) where !seen.contains(k) {
            lines.append("\(k): \(v)")
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n") + body
    }
}

public enum LensCatalogError: Error, Equatable, Sendable, LocalizedError {
    case missingSystemTrust
    case missingLens(String)
    case unclosedFrontMatter
    case invalidStatus(String)
    case emptyTranscript
    case invalidLensID(String)
    case reservedLensID(String)
    case emptyTitle
    case emptyBody

    public var errorDescription: String? {
        switch self {
        case .missingSystemTrust:
            return "The shared lens trust file is missing."
        case .missingLens(let id):
            return "No lens named \(id)."
        case .unclosedFrontMatter:
            return "This lens file has unclosed front matter."
        case .invalidStatus(let status):
            return "Invalid lens status: \(status)."
        case .emptyTranscript:
            return "The transcript is empty."
        case .invalidLensID(let id):
            return "Lens id “\(id)” must start with a letter and use only letters, numbers, and underscores."
        case .reservedLensID(let id):
            return "“\(id)” is a bundled lens and cannot be overwritten."
        case .emptyTitle:
            return "Give the lens a title."
        case .emptyBody:
            return "Write instructions for the lens."
        }
    }
}
