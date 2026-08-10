import Testing
@testable import VaakyaCore

@Suite struct TranscriptCoreTests {
    @Test func wordsAreAssignedByMaximumTemporalOverlap() {
        let words = [
            TimedWord(text: "hello", startSeconds: 0.0, endSeconds: 0.8),
            TimedWord(text: "world", startSeconds: 1.0, endSeconds: 1.6),
        ]
        let segments = [
            SpeakerInterval(speakerKey: "S1", startSeconds: 0.0, endSeconds: 0.9, qualityScore: 0.8),
            SpeakerInterval(speakerKey: "S2", startSeconds: 0.9, endSeconds: 2.0, qualityScore: 0.8),
        ]

        let turns = SpeakerAttribution.makeTurns(words: words, segments: segments)

        #expect(turns.map(\.speakerKey) == ["S1", "S2"])
        #expect(turns.map(\.rawText) == ["hello", "world"])
    }

    @Test func overlappingSegmentsUseQualityAfterOverlapTie() {
        let words = [TimedWord(text: "word", startSeconds: 1.0, endSeconds: 2.0)]
        let segments = [
            SpeakerInterval(speakerKey: "S1", startSeconds: 0.0, endSeconds: 2.0, qualityScore: 0.4),
            SpeakerInterval(speakerKey: "S2", startSeconds: 1.0, endSeconds: 3.0, qualityScore: 0.9),
        ]

        let turns = SpeakerAttribution.makeTurns(words: words, segments: segments)

        #expect(turns.count == 1)
        #expect(turns[0].speakerKey == "S2")
    }

    @Test func gapsRemainUnknownOutsideNearestSpeakerTolerance() {
        let words = [
            TimedWord(text: "known", startSeconds: 0.0, endSeconds: 0.4),
            TimedWord(text: "gap", startSeconds: 4.0, endSeconds: 4.4),
        ]
        let segments = [
            SpeakerInterval(speakerKey: "S1", startSeconds: 0.0, endSeconds: 0.5, qualityScore: 1.0),
        ]

        let turns = SpeakerAttribution.makeTurns(
            words: words,
            segments: segments,
            nearestSpeakerToleranceSeconds: 0.5)

        #expect(turns.map(\.speakerKey) == ["S1", SpeakerAttribution.unknownSpeakerKey])
    }

    @Test func sameSpeakerSplitsAfterLongSilence() {
        let words = [
            TimedWord(text: "first", startSeconds: 0.0, endSeconds: 0.3),
            TimedWord(text: "second", startSeconds: 2.0, endSeconds: 2.3),
        ]
        let segment = SpeakerInterval(speakerKey: "S1", startSeconds: 0.0, endSeconds: 3.0, qualityScore: 1.0)

        let turns = SpeakerAttribution.makeTurns(
            words: words,
            segments: [segment],
            maximumTurnGapSeconds: 1.0)

        #expect(turns.count == 2)
    }

    @Test func punctuationIsKeptWhenFormattingTurns() {
        let turns = [
            TranscriptTurn(
                ordinal: 0,
                speakerKey: "S1",
                startSeconds: 0,
                endSeconds: 1,
                rawText: "Hello, world!",
                finalText: "Hello, world!",
                confidence: 0.9)
        ]

        #expect(TranscriptFormatter.plainText(turns) == "Speaker 1: Hello, world!")
        #expect(TranscriptFormatter.markdown(turns) == "**Speaker 1** *(0:00)*\nHello, world!")
    }

    @Test func stateMachineResumesFromLastCompletedStage() throws {
        var state = TranscriptJobState()

        try state.begin(.preparingASR)
        try state.begin(.transcribing)
        try state.finish(.transcribing)
        #expect(state.completedStage == .asr)
        #expect(state.status == .queued)

        try state.begin(.preparingDiarizer)
        try state.begin(.diarizing)
        state.pause()
        #expect(state.status == .paused)
        #expect(state.activeStage == .diarizing)

        state.recover()
        #expect(state.status == .queued)
        #expect(state.completedStage == .asr)
        #expect(state.activeStage == .diarizing)
    }

    @Test func stateMachineRejectsSkippingStages() {
        var state = TranscriptJobState()

        #expect(throws: TranscriptJobStateError.self) {
            try state.begin(.aligning)
        }
    }
}
