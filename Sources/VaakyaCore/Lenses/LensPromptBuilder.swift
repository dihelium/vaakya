import CryptoKit
import Foundation

public enum LensPromptBuilder {
    /// Build OpenAI-style chat messages. Returns empty when the lens does not require an LLM (L0).
    public static func buildMessages(lens: LensSpec, input: LensPromptInput) -> [LensChatMessage] {
        guard lens.requiresLLM else { return [] }

        let system = [lens.systemTrust.trimmingCharacters(in: .whitespacesAndNewlines),
                      lens.body.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let notes = input.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = input.transcriptMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = input.contextMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)

        let user = """
        [NOTES]
        \(notes.isEmpty ? "(none)" : notes)

        [TRANSCRIPT]
        \(transcript)

        [CONTEXT]
        \(context.isEmpty ? "(none)" : context)
        """

        return [
            LensChatMessage(role: "system", content: system),
            LensChatMessage(role: "user", content: user),
        ]
    }

    /// Stable hash of the prompt inputs used for draft front matter / idempotency.
    public static func inputSHA256(lensID: String, input: LensPromptInput) -> String {
        let payload = [
            lensID,
            input.notesMarkdown,
            input.transcriptMarkdown,
            input.contextMarkdown,
        ].joined(separator: "\u{1e}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Wrap model body with draft front matter. Forces status=draft.
    public static func wrapDraft(body: String, meta: LensDraftFrontMatter) -> String {
        var m = meta
        m.status = "draft"
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip model-emitted front matter if present so we own status.
        let bare: String
        if cleaned.hasPrefix("---") {
            bare = (try? LensFrontMatter.parse(cleaned).body) ?? cleaned
        } else {
            bare = cleaned
        }
        return m.renderYAML() + "\n\n" + bare.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
