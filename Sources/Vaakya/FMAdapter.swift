import Foundation
import VaakyaCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Stage 2 adapter over macOS 26 Foundation Models (`SystemLanguageModel`),
/// plan §5.2 / task 4.3. Thin, guarded shell — the guards themselves live and
/// are tested in VaakyaCore's `LLMCleanup`.
@available(macOS 26.0, *)
final class FMAdapter: CleanupModel {
    static var isAvailable: Bool {
#if canImport(FoundationModels)
        SystemLanguageModel.default.isAvailable
#else
        false
#endif
    }

    private let session: LanguageModelSession

    init(instructions: String = "You are a dictation post-processor.") {
        session = LanguageModelSession(model: .default, instructions: instructions)
    }

    func complete(prompt: String) async throws -> String {
#if canImport(FoundationModels)
        let response = try await session.respond(to: prompt)
        return response.content
#else
        throw FMError.unavailable
#endif
    }

    enum FMError: Error {
        case unavailable
    }
}
