import Foundation
import Testing
@testable import SpeechKit

@Suite("SpeechService")
struct SpeechServiceTests {
    @MainActor
    @Test("startListening surfaces missing ElevenLabs config")
    func startListeningWithoutElevenLabsConfigSetsFallbackError() async {
        let service = SpeechService()

        await service.startListening()

        #expect(service.connectionState == .error("ElevenLabs is not configured"))
        #expect(service.lastError as? SpeechError == .providerNotConfigured(.elevenLabs))
    }

    @MainActor
    @Test("routing rejects mismatched provider options")
    func transcribeRejectsMismatchedOptions() async {
        let service = SpeechService(
            elevenLabs: ElevenLabsConfig(apiKey: "eleven"),
            cohere: CohereConfig(apiKey: "cohere"),
            grok: GrokConfig(apiKey: "xai")
        )
        let fileURL = temporaryAudioFileURL()

        await #expect(throws: SpeechError.invalidOptionsForProvider(expected: .grok, received: .elevenLabs)) {
            _ = try await service.transcribeAudioFile(
                provider: .grok,
                file: fileURL,
                options: .elevenLabs(modelId: .scribeV1)
            )
        }
    }

    @MainActor
    @Test("deprecated initializer configures ElevenLabs defaults")
    func deprecatedInitializerConfiguresElevenLabs() {
        let service = SpeechService(apiKey: "legacy-key", modelId: .scribeV2Realtime)

        #expect(service.elevenLabs?.apiKey == "legacy-key")
        #expect(service.elevenLabs?.realtimeModelId == .scribeV2Realtime)
        #expect(service.elevenLabs?.fileModelId == .scribeV1)
    }
}

private func temporaryAudioFileURL() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    try? Data("test".utf8).write(to: url)
    return url
}
