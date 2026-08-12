import Foundation
import VaakyaCore

@MainActor
@Observable
final class AudioTranscriptionJobRunner {
    enum RunnerError: LocalizedError {
        case diarizationConsentRequired
        case missingWordTimings
        case invalidWordTimings
        var errorDescription: String? {
            switch self {
            case .diarizationConsentRequired:
                return "Speaker diarization needs a one-time download consent before this job can run."
            case .missingWordTimings:
                return "The ASR result did not contain word timings needed for speaker attribution."
            case .invalidWordTimings:
                return "The ASR returned invalid or out-of-order word timings."
            }
        }
    }

    private let db: VaakyaDatabase
    private let asr: any FileTranscriber
    private let diarizer: any FileDiarizer
    private let store = ManagedAudioStore()
    private let diarizationConsent: @MainActor () -> Bool
    private var task: Task<Void, Never>?
    private(set) var jobs: [TranscriptionJobRecord] = []
    private(set) var activeJobID: String?
    private(set) var lastError: String?

    init(db: VaakyaDatabase, asr: any FileTranscriber, diarizer: any FileDiarizer,
         diarizationConsent: @escaping @MainActor () -> Bool) {
        self.db = db
        self.asr = asr
        self.diarizer = diarizer
        self.diarizationConsent = diarizationConsent
        refresh()
    }

    func refresh() {
        jobs = (try? db.transcriptionJobs()) ?? []
    }

    func enqueue(url: URL, expectedSpeakerCount: Int? = nil, securityScoped: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            defer {
                if securityScoped { url.stopAccessingSecurityScopedResource() }
                self.refresh()
            }
            do {
                _ = try self.createJob(url: url, sourceName: nil,
                                       expectedSpeakerCount: expectedSpeakerCount)
                self.startNextIfIdle()
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Adopts a finalized local capture and returns the new job id so navigation
    /// can open it directly. Runs import off the main actor so the session UI
    /// can keep animating while large files copy.
    @discardableResult
    func enqueueCapturedAudio(url: URL, sourceName: String) async throws -> String {
        let id = UUID()
        let sourcePath = url.path
        let managed = try await Task.detached(priority: .userInitiated) {
            try ManagedAudioStore().importAudio(
                from: URL(fileURLWithPath: sourcePath),
                jobID: id
            )
        }.value
        let now = ISO8601DateFormatter().string(from: Date())
        let relative = managed.url.path.replacingOccurrences(of: Paths.transcriptionJobsDirectory.path + "/", with: "")
        let job = TranscriptionJobRecord(id: id.uuidString, sourceName: sourceName,
                                         managedAudioPath: relative, sourceSHA256: managed.sha256,
                                         fileSizeBytes: managed.fileSizeBytes, durationSeconds: managed.durationSeconds,
                                         expectedSpeakerCount: nil, createdAt: now, updatedAt: now,
                                         asrModel: asr.modelID)
        do {
            try db.insertTranscriptionJob(job)
        } catch {
            try? FileManager.default.removeItem(at: managed.url.deletingLastPathComponent())
            throw error
        }
        refresh()
        startNextIfIdle()
        return id.uuidString
    }

    func resumePendingJobs() {
        _ = try? db.recoverInterruptedTranscriptionJobs(updatedAt: timestamp())
        startNextIfIdle()
    }

    func retry(jobID: String) {
        guard let job = try? db.transcriptionJob(id: jobID) else { return }
        try? db.updateTranscriptionJobState(id: jobID, status: "queued",
                                            activeStage: job.activeStage,
                                            completedStage: job.completedStage,
                                            progress: job.progress,
                                            updatedAt: timestamp())
        refresh()
        startNextIfIdle()
    }

    func pause(jobID: String) {
        guard activeJobID == jobID else { return }
        task?.cancel()
        setStoppedStatus(jobID: jobID, status: "paused")
    }

    func cancel(jobID: String) {
        if activeJobID == jobID { task?.cancel() }
        setStoppedStatus(jobID: jobID, status: "cancelled")
    }

    private func startNextIfIdle() {
        guard task == nil else { return }
        guard let job = try? db.transcriptionJobs().reversed().first(where: { $0.status == "queued" }) else { return }
        activeJobID = job.id
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(job: job)
            } catch is CancellationError {
                // Pause/cancel already persisted the user's chosen state.
            } catch {
                self.markFailure(jobID: job.id, error: error)
            }
            self.task = nil
            self.activeJobID = nil
            self.refresh()
            self.startNextIfIdle()
        }
    }

    private func createJob(url: URL, sourceName: String?, expectedSpeakerCount: Int?) throws -> String {
        let id = UUID()
        let managed = try store.importAudio(from: url, jobID: id)
        let now = ISO8601DateFormatter().string(from: Date())
        let relative = managed.url.path.replacingOccurrences(of: Paths.transcriptionJobsDirectory.path + "/", with: "")
        let job = TranscriptionJobRecord(id: id.uuidString, sourceName: sourceName ?? managed.sourceName,
                                         managedAudioPath: relative, sourceSHA256: managed.sha256,
                                         fileSizeBytes: managed.fileSizeBytes, durationSeconds: managed.durationSeconds,
                                         expectedSpeakerCount: expectedSpeakerCount, createdAt: now, updatedAt: now,
                                         asrModel: asr.modelID)
        try db.insertTranscriptionJob(job)
        return id.uuidString
    }

    private func run(job: TranscriptionJobRecord) async throws {
        var record = try db.transcriptionJob(id: job.id) ?? job
        let url = try store.managedURL(relativePath: record.managedAudioPath)
        let jobID = record.id
        let asrResult: FileASRResult
        if record.completedStage == TranscriptCompletedStage.alignment.rawValue { return }
        let hasASR = [TranscriptCompletedStage.asr.rawValue,
                      TranscriptCompletedStage.diarization.rawValue].contains(record.completedStage)
        if !hasASR {
            try update(record, status: "running", active: .preparingASR, completed: .none, progress: 0)
            try await asr.prepare()
            try Task.checkCancellation()
            try update(record, status: "running", active: .transcribing, completed: .none, progress: 0)
            asrResult = try await asr.transcribeFile(url) { [weak self] progress in
                Task { @MainActor in self?.persistProgress(jobID, active: .transcribing, completed: .none, progress: progress) }
            }
            try Task.checkCancellation()
            guard !asrResult.words.isEmpty else { throw RunnerError.missingWordTimings }
            guard validTimings(asrResult.words, duration: record.durationSeconds) else {
                throw RunnerError.invalidWordTimings
            }
            let data = try JSONEncoder().encode(asrResult)
            try data.write(to: url.deletingLastPathComponent().appendingPathComponent("asr-result.json"), options: [.atomic])
            try update(record, status: "queued", active: .idle, completed: .asr, progress: 1, rawText: asrResult.text)
            record.completedStage = TranscriptCompletedStage.asr.rawValue
            record.rawText = asrResult.text
        } else {
            let artifact = url.deletingLastPathComponent().appendingPathComponent("asr-result.json")
            asrResult = try JSONDecoder().decode(FileASRResult.self, from: Data(contentsOf: artifact))
        }

        guard diarizationConsent() else { throw RunnerError.diarizationConsentRequired }
        let segments: [SpeakerInterval]
        if record.completedStage == TranscriptCompletedStage.diarization.rawValue {
            let artifact = url.deletingLastPathComponent().appendingPathComponent("diarization-result.json")
            segments = try JSONDecoder().decode([SpeakerInterval].self, from: Data(contentsOf: artifact))
        } else {
            try Task.checkCancellation()
            try update(record, status: "running", active: .preparingDiarizer, completed: .asr, progress: 0)
            try await diarizer.prepare()
            try Task.checkCancellation()
            try update(record, status: "running", active: .diarizing, completed: .asr, progress: 0)
            segments = try await diarizer.diarizeFile(url) { [weak self] progress in
                Task { @MainActor in self?.persistProgress(jobID, active: .diarizing, completed: .asr, progress: progress) }
            }
            try Task.checkCancellation()
            let data = try JSONEncoder().encode(segments)
            try data.write(to: url.deletingLastPathComponent().appendingPathComponent("diarization-result.json"), options: [.atomic])
            try update(record, status: "queued", active: .idle, completed: .diarization, progress: 1)
            record.completedStage = TranscriptCompletedStage.diarization.rawValue
        }
        try update(record, status: "running", active: .aligning, completed: .diarization, progress: 0)
        let turns = SpeakerAttribution.makeTurns(words: asrResult.words, segments: segments)
        let keys = Array(Set(turns.map(\.speakerKey))).sorted()
        let speakers = keys.enumerated().map { TranscriptSpeakerRecord(jobID: record.id, speakerKey: $0.element,
                                                                         displayName: $0.element == SpeakerAttribution.unknownSpeakerKey ? "Unknown Speaker" : "Speaker \($0.offset + 1)",
                                                                         sortOrder: $0.offset) }
        try db.replaceTranscript(jobID: record.id, speakers: speakers, turns: turns)
        let finalText = TranscriptFormatter.plainText(turns)
        try update(record, status: "completed", active: .idle, completed: .alignment, progress: 1,
                   finalText: finalText)
    }

    private func update(_ record: TranscriptionJobRecord, status: String, active: TranscriptActiveStage,
                        completed: TranscriptCompletedStage, progress: Double, rawText: String? = nil,
                        finalText: String? = nil) throws {
        try db.updateTranscriptionJobState(id: record.id, status: status, activeStage: active.rawValue,
                                           completedStage: completed.rawValue, progress: progress,
                                           rawText: rawText, finalText: finalText,
                                           updatedAt: ISO8601DateFormatter().string(from: Date()))
    }

    private func persistProgress(_ id: String, active: TranscriptActiveStage, completed: TranscriptCompletedStage, progress: Double) {
        guard let job = try? db.transcriptionJob(id: id), job.status == "running" else { return }
        try? db.updateTranscriptionJobState(id: id, status: "running", activeStage: active.rawValue,
                                            completedStage: completed.rawValue, progress: progress,
                                            updatedAt: ISO8601DateFormatter().string(from: Date()))
    }

    private func setStoppedStatus(jobID: String, status: String) {
        guard let job = try? db.transcriptionJob(id: jobID) else { return }
        try? db.updateTranscriptionJobState(id: jobID, status: status,
                                            activeStage: job.activeStage,
                                            completedStage: job.completedStage,
                                            progress: job.progress,
                                            updatedAt: timestamp())
        refresh()
    }

    private func validTimings(_ words: [TimedWord], duration: Double) -> Bool {
        var lastStart = -Double.infinity
        for word in words {
            guard word.startSeconds >= 0, word.endSeconds >= word.startSeconds,
                  word.startSeconds >= lastStart,
                  word.endSeconds <= duration + 1 else { return false }
            lastStart = word.startSeconds
        }
        return true
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func markFailure(jobID: String?, error: Error) {
        guard let jobID else { return }
        let existing = try? db.transcriptionJob(id: jobID)
        try? db.updateTranscriptionJobState(id: jobID, status: "failed",
                                            activeStage: existing?.activeStage ?? "idle",
                                            completedStage: existing?.completedStage ?? "none",
                                            progress: existing?.progress ?? 0,
                                            errorMessage: error.localizedDescription,
                                            updatedAt: ISO8601DateFormatter().string(from: Date()))
    }
}
