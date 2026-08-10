import Testing
@testable import Vaakya

@Suite("Codex inference safety")
struct CodexSafetyTests {
    @Test func executionIsEphemeralToolDisabledAndReadOnly() {
        let args = CodexLensClient.safeExecArguments(
            cwd: "/tmp/vaakya-staging",
            outputPath: "/tmp/vaakya-staging/result.md")

        #expect(args.contains("--ephemeral"))
        #expect(args.contains("--ignore-user-config"))
        #expect(args.contains("--ignore-rules"))
        #expect(args.contains("--strict-config"))
        #expect(args.contains("features.shell_tool=false"))
        #expect(args.contains("features.unified_exec=false"))
        #expect(args.contains("web_search=\"disabled\""))
        #expect(args.contains("project_doc_max_bytes=0"))
        #expect(args.contains("history.persistence=\"none\""))
        #expect(args.contains("memories.generate_memories=false"))
        #expect(args.contains("analytics.enabled=false"))
        #expect(args.contains("read-only"))
        #expect(args.last == "-")
        #expect(!args.contains("workspace-write"))
        #expect(!args.contains("danger-full-access"))
        #expect(!args.contains("--full-auto"))
        #expect(!args.contains("--dangerously-bypass-approvals-and-sandbox"))
    }
}
