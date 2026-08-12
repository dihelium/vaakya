import Foundation
import VaakyaCore

/// Orchestrates lens runs for completed transcription jobs: build prompt,
/// call OpenAI-compatible API or Codex CLI, write Markdown under the job
/// directory, and persist a `lens_runs` row.
@MainActor
final class LensService {
    private let db: VaakyaDatabase
    private let config: () -> AppConfig
    private let apiKeyProvider: () -> String?

    init(db: VaakyaDatabase,
         config: @escaping () -> AppConfig,
         apiKeyProvider: @escaping () -> String? = { KeychainStore.load(account: "openai_lens") }) {
        self.db = db
        self.config = config
        self.apiKeyProvider = apiKeyProvider
    }

    func availableLenses() throws -> [LensSpec] {
        try Paths.ensureCustomLensesDirectory()
        return try LensCatalog.allSpecs(userDirectory: Paths.customLensesDirectory)
    }

    func customStore() throws -> CustomLensStore {
        try Paths.ensureCustomLensesDirectory()
        return CustomLensStore(directory: Paths.customLensesDirectory)
    }

    @discardableResult
    func saveCustomLens(id: String? = nil, title: String, body: String) throws -> LensSpec {
        try customStore().save(id: id, title: title, body: body)
    }

    func deleteCustomLens(id: String) throws {
        try customStore().delete(id: id)
    }

    func notesURL(jobID: String) -> URL {
        Paths.jobDirectory(jobID: jobID).appendingPathComponent("notes.md")
    }

    func contextURL(jobID: String) -> URL {
        Paths.jobDirectory(jobID: jobID).appendingPathComponent("context.md")
    }

    func ensureSidecarFiles(jobID: String) throws {
        try Paths.ensureJobDirectories(jobID: jobID)
        let notes = notesURL(jobID: jobID)
        if !FileManager.default.fileExists(atPath: notes.path) {
            let stub = "<!-- User notes (privileged over transcript). Edit freely. -->\n"
            try stub.write(to: notes, atomically: true, encoding: .utf8)
        }
        let context = contextURL(jobID: jobID)
        if !FileManager.default.fileExists(atPath: context.path) {
            let seed = LensCatalog.defaultContextMarkdown()
            try seed.write(to: context, atomically: true, encoding: .utf8)
        }
    }

    func loadNotes(jobID: String) -> String {
        (try? String(contentsOf: notesURL(jobID: jobID), encoding: .utf8)) ?? ""
    }

    func loadContext(jobID: String) -> String {
        (try? String(contentsOf: contextURL(jobID: jobID), encoding: .utf8)) ?? ""
    }

    func saveNotes(jobID: String, text: String) throws {
        try Paths.ensureJobDirectories(jobID: jobID)
        try text.write(to: notesURL(jobID: jobID), atomically: true, encoding: .utf8)
    }

    func saveContext(jobID: String, text: String) throws {
        try Paths.ensureJobDirectories(jobID: jobID)
        try text.write(to: contextURL(jobID: jobID), atomically: true, encoding: .utf8)
    }

    func buildTranscriptMarkdown(jobID: String) throws -> String {
        let speakers = try db.transcriptSpeakers(jobID: jobID)
        let turns = try db.transcriptTurns(jobID: jobID)
        let names = Dictionary(uniqueKeysWithValues: speakers.map { ($0.speakerKey, $0.displayName) })
        return TranscriptFormatter.markdown(turns.map(\.asTurn), speakerNames: names)
    }

    /// Run a lens. `allowEgress` must be true for OpenAI or Codex paths.
    /// `extraContext` is merged into the prompt for this run only (not saved to context.md unless the user also edits that file).
    /// `onCodexLog` receives live CLI stdout/stderr chunks (may be off main actor).
    @discardableResult
    func run(jobID: String,
             lensID: String,
             allowEgress: Bool,
             extraContext: String = "",
             onCodexLog: CodexLensClient.LogHandler? = nil) async throws -> LensRunRecord {
        guard let job = try db.transcriptionJob(id: jobID), job.status == "completed" else {
            throw OpenAILensError.jobNotCompleted
        }
        let lens = try LensCatalog.loadSpec(id: lensID, userDirectory: Paths.customLensesDirectory)
        try ensureSidecarFiles(jobID: jobID)

        let transcript = try buildTranscriptMarkdown(jobID: jobID)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAILensError.emptyTranscript
        }
        // Always refresh transcript.md for Codex/file consumers.
        let transcriptURL = Paths.jobDirectory(jobID: jobID).appendingPathComponent("transcript.md")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let notes = loadNotes(jobID: jobID)
        let baseContext = loadContext(jobID: jobID)
        let extra = extraContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedContext = Self.mergeContext(base: baseContext, extra: extra)
        let input = LensPromptInput(notesMarkdown: notes,
                                    transcriptMarkdown: transcript,
                                    contextMarkdown: mergedContext)
        let version = try db.nextLensVersion(jobID: jobID, lensID: lens.id)
        let now = ISO8601DateFormatter().string(from: Date())
        let sha = LensPromptBuilder.inputSHA256(lensID: lens.id, input: input)
        let fileName = "\(lens.id).v\(version).md"
        let fileURL = Paths.jobLensesDirectory(jobID: jobID).appendingPathComponent(fileName)
        try Paths.ensureJobDirectories(jobID: jobID)

        let body: String
        let via: String
        let egress: String
        let modelName: String

        if !lens.requiresLLM {
            body = transcript
            via = "local"
            egress = "B0"
            modelName = "none"
        } else {
            let cfg = config()
            let runner = cfg.runnerKind
            if runner.isB1 {
                guard cfg.lensEgressEnabled, allowEgress else {
                    throw OpenAILensError.egressNotAllowed
                }
            }
            let messages = LensPromptBuilder.buildMessages(lens: lens, input: input)

            switch runner {
            case .codex:
                onCodexLog?("$ lens \(lens.id) v\(version) via ephemeral Codex inference\n")
                let result = try await CodexLensClient.complete(
                    messages: messages,
                    lensID: lens.id,
                    packageID: jobID,
                    fidelity: "A1",
                    egress: "B1",
                    createdAt: now,
                    inputSHA256: sha,
                    codexPath: cfg.lensCodexPath.isEmpty ? nil : cfg.lensCodexPath,
                    onLog: onCodexLog,
                    cancelKey: "lens:\(jobID):\(lens.id):v\(version)")
                body = result.content
                via = "codex"
                egress = "B1"
                modelName = result.model
                try appendEgressLog(jobID: jobID, lensID: lens.id, version: version,
                                    model: modelName, via: via, bytes: body.utf8.count)
            case .local:
                let client = OpenAILensClient(
                    baseURL: cfg.localBaseURL,
                    apiKey: "",
                    model: cfg.localModel,
                    mode: .local)
                let result = try await client.complete(messages: messages)
                body = result.content
                via = "local"
                egress = "B0"
                modelName = result.model
            case .remote:
                guard let key = apiKeyProvider(), !key.isEmpty else {
                    throw OpenAILensError.missingAPIKey
                }
                let client = OpenAILensClient(
                    baseURL: cfg.remoteBaseURL,
                    apiKey: key,
                    model: cfg.remoteModel,
                    mode: .remote)
                let result = try await client.complete(messages: messages)
                body = result.content
                via = "remote"
                egress = "B1"
                modelName = result.model
                try appendEgressLog(jobID: jobID, lensID: lens.id, version: version,
                                    model: modelName, via: via, bytes: body.utf8.count)
            }
        }

        let meta = LensDraftFrontMatter(
            lensID: lens.id,
            model: modelName,
            via: via,
            createdAt: now,
            packageID: jobID,
            fidelity: "A1",
            egress: egress,
            inputSHA256: sha)
        let markdown = LensPromptBuilder.wrapDraft(body: body, meta: meta)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let relative = "transcription-jobs/\(jobID)/lenses/\(fileName)"
        let run = LensRunRecord(
            id: UUID().uuidString,
            jobID: jobID,
            lensID: lens.id,
            version: version,
            status: "draft",
            via: via,
            egress: egress,
            model: modelName,
            markdownPath: relative,
            inputSHA256: sha,
            createdAt: now,
            updatedAt: now)
        try db.insertLensRun(run)
        return run
    }

    func promote(runID: String, to status: String) throws {
        guard let run = try db.lensRun(id: runID) else { return }
        let url = Paths.appSupport.appendingPathComponent(run.markdownPath)
        let existing = try String(contentsOf: url, encoding: .utf8)
        let updated = try LensFrontMatter.promoteStatus(in: existing, to: status)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        let now = ISO8601DateFormatter().string(from: Date())
        try db.updateLensRunStatus(id: runID, status: status, updatedAt: now)
    }

    func loadMarkdown(run: LensRunRecord) throws -> String {
        let url = Paths.appSupport.appendingPathComponent(run.markdownPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Merge durable context pack with one-shot run context for the prompt.
    static func mergeContext(base: String, extra: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { return b }
        if b.isEmpty {
            return """
            ## Additional context (this run only)

            \(e)
            """
        }
        return """
        \(b)

        ---

        ## Additional context (this run only)

        \(e)
        """
    }

    private func appendEgressLog(jobID: String, lensID: String, version: Int,
                                 model: String, via: String, bytes: Int) throws {
        let url = Paths.jobDirectory(jobID: jobID).appendingPathComponent("egress_log.jsonl")
        let line = """
        {"ts":"\(ISO8601DateFormatter().string(from: Date()))","lens_id":"\(lensID)","version":\(version),"via":"\(via)","model":"\(model)","bytes":\(bytes),"payload":"transcript+notes+context","audio":false}
        """
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = (line + "\n").data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }
}
