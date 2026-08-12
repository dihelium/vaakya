import Foundation
import Testing
@testable import VaakyaCore

@Suite struct SpeechRecognitionProfileTests {
    @Test func dictationMeetingsAndImportsShareOneParakeetProfile() {
        #expect(SpeechRecognitionProfile.dictation == SpeechRecognitionProfile.meeting)
        #expect(SpeechRecognitionProfile.meeting == SpeechRecognitionProfile.importedAudio)
        #expect(SpeechRecognitionProfile.shared.id == "parakeet-tdt-0.6b-v2")
        #expect(SpeechRecognitionProfile.shared.fluidAudioVersionName == "v2")
        #expect(SpeechRecognitionProfile.shared.displayName == "Parakeet TDT v2")
    }

    @Test func newTranscriptionJobsDefaultToTheSharedParakeetModel() throws {
        let db = try VaakyaDatabase()
        let job = TranscriptionJobRecord(
            id: "job-asr",
            sourceName: "Meeting 2026-08-12 10:00",
            managedAudioPath: "x",
            sourceSHA256: "s",
            fileSizeBytes: 1,
            durationSeconds: 1,
            createdAt: "t0",
            updatedAt: "t0")
        try db.insertTranscriptionJob(job)
        let stored = try #require(try db.transcriptionJob(id: "job-asr"))
        #expect(stored.asrModel == SpeechRecognitionProfile.shared.id)
        #expect(stored.asrModel == SpeechRecognitionProfile.dictation.id)
    }
}
