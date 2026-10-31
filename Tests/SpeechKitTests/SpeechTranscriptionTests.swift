import Foundation
import Observation
import SwiftUI
import Synchronization
import Testing
@testable import SpeechKit

@Suite("Narrow transcription capability")
@MainActor
struct SpeechTranscriptionTests {
    @Test func capabilityForwardsStateAndListeningWithoutConfigurationAccess() async {
        let service = SpeechService()
        let transcriber = service.transcriber
        await transcriber.startListening(provider: .openAI)
        #expect(transcriber.connectionState == service.connectionState)
        #expect(transcriber.lastError as? SpeechError == .realtimeProviderNotConfigured(.openAI))
        #expect(transcriber.transcriptText == service.transcriptText)
        #expect(transcriber.partialTranscriptText == service.partialTranscriptText)
        #expect(transcriber.transcriptEntries.isEmpty)
        await transcriber.stopListening()
        #expect(transcriber.connectionState == service.connectionState)
        await transcriber.startListening()
        #expect(transcriber.lastError as? SpeechError == .realtimeProviderNotConfigured(.elevenLabs))
    }

    @Test func fileTranscriptionReturnsServiceResult() async throws {
        let fixture = SecurityHTTPFixture { _ in .init(body: Data(#"{"text":"synthetic transcript"}"#.utf8)) }
        let service = SpeechService(
            openAI: OpenAIConfiguration(credential: .bearer(SpeechTokenResolver { _ in "synthetic" }), fileEndpoint: fixture.endpoint("transcribe")),
            urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        let transcriber = service.transcriber
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try await transcriber.transcribeAudioFile(provider: .openAI, file: file) == "synthetic transcript")
        #expect(fixture.requests.count == 1)
        await #expect(throws: SpeechError.providerNotConfigured(.cohere)) {
            try await transcriber.transcribeAudioFile(provider: .cohere, file: file)
        }
    }

    @Test func capabilityReadsParticipateInObservation() {
        let service = SpeechService()
        let transcriber = service.transcriber
        let changed = Mutex(false)
        withObservationTracking {
            _ = transcriber.connectionState
        } onChange: {
            changed.withLock { $0 = true }
        }
        service.fallbackConnectionState = .connecting
        #expect(changed.withLock { $0 })
        #expect(transcriber.connectionState == .connecting)
    }

    @Test func narrowEnvironmentIsAdditiveAndDefaultsToExistingService() async {
        let service = SpeechService()
        var environment = EnvironmentValues()
        environment.speechService = service
        #expect(environment.speechService === service)
        await environment.speechTranscriber.startListening(provider: .grok)
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.grok))
        let other = SpeechService()
        environment.speechTranscriber = other.transcriber
        await environment.speechTranscriber.startListening(provider: .meta)
        #expect(other.lastError as? SpeechError == .realtimeProviderNotConfigured(.meta))
        #expect(environment.speechService === service)
    }

    @Test func reflectionDoesNotExposeOwningService() {
        let transcriber = SpeechService().transcriber
        #expect(Mirror(reflecting: transcriber).children.isEmpty)
        #expect(String(reflecting: transcriber) == "SpeechTranscription(<redacted>)")
    }
}
