import Foundation
import Testing
@testable import SpeechKit

@Suite("Realtime session acknowledgements")
struct RealtimeSessionAcknowledgementTests {
    // MARK: - Grok

    @MainActor
    @Test("Grok service connects when the transcript created acknowledgement arrives")
    func grokServiceConnectsOnTranscriptCreated() {
        let service = GrokRealtimeService(apiKey: "xai-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.transcriptCreated(GrokTranscriptCreated(sessionID: "grok-1")))

        #expect(service.connectionState == .connected(sessionID: "grok-1"))
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("Grok service ignores a duplicate transcript created acknowledgement")
    func grokServiceIgnoresDuplicateTranscriptCreated() {
        let service = GrokRealtimeService(apiKey: "xai-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.transcriptCreated(GrokTranscriptCreated(sessionID: "grok-1")))
        service.handleMessageForTesting(.transcriptCreated(GrokTranscriptCreated(sessionID: "grok-2")))

        #expect(service.connectionState == .connected(sessionID: "grok-1"))
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("Grok service ignores a transcript created acknowledgement while disconnected")
    func grokServiceIgnoresTranscriptCreatedWhileDisconnected() {
        let service = GrokRealtimeService(apiKey: "xai-key")

        service.handleMessageForTesting(.transcriptCreated(GrokTranscriptCreated(sessionID: "grok-1")))

        #expect(service.connectionState == .disconnected)
        #expect(service.lastError == nil)
    }

    // MARK: - ElevenLabs

    @MainActor
    @Test("ElevenLabs service connects when the session started acknowledgement arrives")
    func elevenLabsServiceConnectsOnSessionStarted() {
        let service = ElevenLabsService(apiKey: "eleven-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionStarted(elevenLabsSessionStarted(sessionID: "eleven-1")))

        #expect(service.connectionState == .connected(sessionID: "eleven-1"))
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("ElevenLabs service ignores a duplicate session started acknowledgement")
    func elevenLabsServiceIgnoresDuplicateSessionStarted() {
        let service = ElevenLabsService(apiKey: "eleven-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionStarted(elevenLabsSessionStarted(sessionID: "eleven-1")))
        service.handleMessageForTesting(.sessionStarted(elevenLabsSessionStarted(sessionID: "eleven-2")))

        #expect(service.connectionState == .connected(sessionID: "eleven-1"))
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("ElevenLabs service ignores a session started acknowledgement while disconnected")
    func elevenLabsServiceIgnoresSessionStartedWhileDisconnected() {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(.sessionStarted(elevenLabsSessionStarted(sessionID: "eleven-1")))

        #expect(service.connectionState == .disconnected)
        #expect(service.lastError == nil)
    }
}

private func elevenLabsSessionStarted(sessionID: String) -> SessionStarted {
    SessionStarted(
        sessionID: sessionID,
        config: SessionConfig(
            sampleRate: 16_000,
            audioFormat: "pcm_s16le_16",
            languageCode: nil,
            modelID: "scribe_v2_realtime",
            vadCommitStrategy: true,
            vadSilenceThresholdSecs: 0.5,
            vadThreshold: 0.5,
            includeTimestamps: false
        )
    )
}
