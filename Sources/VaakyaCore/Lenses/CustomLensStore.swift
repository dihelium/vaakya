import Foundation

/// File-backed user lenses stored as Markdown with the same front matter as
/// bundled lenses. Never overwrites a bundled id.
public struct CustomLensStore: Sendable {
    public let directory: URL
    public let reservedIDs: Set<String>

    public init(directory: URL, reservedIDs: Set<String> = Set(LensCatalog.bundledIDs)) {
        self.directory = directory
        self.reservedIDs = reservedIDs
    }

    public func allSpecs() throws -> [LensSpec] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var specs: [LensSpec] = []
        var seen = Set<String>()
        for url in urls {
            guard let spec = try? parseFile(url) else { continue }
            if reservedIDs.contains(spec.id) { continue }
            if seen.contains(spec.id) { continue }
            seen.insert(spec.id)
            specs.append(spec)
        }
        return specs
    }

    public func load(id: String) throws -> LensSpec {
        let direct = fileURL(for: id)
        if FileManager.default.fileExists(atPath: direct.path) {
            let spec = try parseFile(direct)
            if reservedIDs.contains(spec.id) {
                throw LensCatalogError.reservedLensID(spec.id)
            }
            return spec
        }
        let matches = try allSpecs().filter { $0.id == id }
        guard let spec = matches.first else {
            throw LensCatalogError.missingLens(id)
        }
        return spec
    }

    @discardableResult
    public func save(id: String? = nil, title: String, body: String,
                     requiresLLM: Bool = true) throws -> LensSpec {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw LensCatalogError.emptyTitle }
        guard !trimmedBody.isEmpty else { throw LensCatalogError.emptyBody }

        let resolvedID: String
        if let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let candidate = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if reservedIDs.contains(candidate) {
                throw LensCatalogError.reservedLensID(candidate)
            }
            try Self.validateID(candidate)
            resolvedID = candidate
        } else {
            resolvedID = try uniqueID(from: trimmedTitle)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let spec = LensSpec(
            id: resolvedID,
            title: trimmedTitle,
            requiresLLM: requiresLLM,
            minFidelity: "A1",
            defaultEgress: "B1",
            body: trimmedBody,
            systemTrust: (try? LensCatalog.systemTrust()) ?? "",
            origin: .custom
        )
        try render(spec).write(to: fileURL(for: resolvedID), atomically: true, encoding: .utf8)
        return spec
    }

    public func delete(id: String) throws {
        if reservedIDs.contains(id) {
            throw LensCatalogError.reservedLensID(id)
        }
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            return
        }
        throw LensCatalogError.missingLens(id)
    }

    public static func makeSlug(from title: String) -> String {
        let lowered = title.lowercased()
        var chars: [Character] = []
        var lastUnderscore = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                chars.append(character)
                lastUnderscore = false
            } else if !chars.isEmpty && !lastUnderscore {
                chars.append("_")
                lastUnderscore = true
            }
        }
        while chars.last == "_" { chars.removeLast() }
        var slug = String(chars)
        if slug.isEmpty { slug = "custom_lens" }
        if let first = slug.first, first.isNumber {
            slug = "l_" + slug
        }
        if slug.count > 64 {
            slug = String(slug.prefix(64))
            while slug.last == "_" { slug.removeLast() }
        }
        return slug
    }

    public static func validateID(_ id: String) throws {
        guard id.wholeMatch(of: /^[A-Za-z][A-Za-z0-9_]{1,63}$/) != nil else {
            throw LensCatalogError.invalidLensID(id)
        }
    }

    public static let defaultInstructions = """
        # Instructions

        Rewrite this completed transcript for later reading. Use only [NOTES], [TRANSCRIPT], and [CONTEXT]. Do not invent people, decisions, or dates.

        # Output

        ## Summary
        - …

        ## Decisions
        - …

        ## Actions
        - **Who:** … — **What:** … — **Evidence:** …

        ## Open questions
        - …
        """

    // MARK: - internals

    private func uniqueID(from title: String) throws -> String {
        var slug = Self.makeSlug(from: title)
        if reservedIDs.contains(slug) {
            slug = "custom_" + slug
        }
        try Self.validateID(slug)
        if !FileManager.default.fileExists(atPath: fileURL(for: slug).path) {
            return slug
        }
        for index in 2...99 {
            let candidate = "\(slug)_\(index)"
            if reservedIDs.contains(candidate) { continue }
            if !FileManager.default.fileExists(atPath: fileURL(for: candidate).path) {
                return candidate
            }
        }
        throw LensCatalogError.invalidLensID(slug)
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("md")
    }

    private func parseFile(_ url: URL) throws -> LensSpec {
        let text = try String(contentsOf: url, encoding: .utf8)
        let (fields, body) = try LensFrontMatter.parse(text)
        let id = fields["id"] ?? url.deletingPathExtension().lastPathComponent
        try Self.validateID(id)
        let requires: Bool = {
            if let raw = fields["requires_llm"]?.lowercased() {
                return raw == "true" || raw == "1" || raw == "yes"
            }
            return true
        }()
        return LensSpec(
            id: id,
            title: fields["title"] ?? id,
            requiresLLM: requires,
            minFidelity: fields["min_fidelity"] ?? "A1",
            defaultEgress: fields["default_egress"] ?? "B1",
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            systemTrust: (try? LensCatalog.systemTrust()) ?? "",
            origin: .custom
        )
    }

    private func render(_ spec: LensSpec) -> String {
        """
        ---
        id: \(spec.id)
        title: \(spec.title)
        requires_llm: \(spec.requiresLLM ? "true" : "false")
        min_fidelity: \(spec.minFidelity)
        default_egress: \(spec.defaultEgress)
        origin: custom
        ---

        \(spec.body)

        """
    }
}
