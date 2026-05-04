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
            grok: GrokConfig(apiKey: "xai"),
            aqua: AquaConfig(apiKey: "aqua")
        )
        let fileURL = temporaryAudioFileURL()

        await #expect(throws: SpeechError.invalidOptionsForProvider(expected: .grok, received: .elevenLabs)) {
            _ = try await service.transcribeAudioFile(
                provider: .grok,
                file: fileURL,
                options: .elevenLabs(modelID: .scribeV1)
            )
        }
    }

    @Test("provider configs support raw language codes")
    func providerConfigsSupportRawLanguageCodes() throws {
        let cohere = try CohereConfig(apiKey: "cohere", languageCode: "de")
        let grok = try GrokConfig(apiKey: "xai", languageCode: "fil")
        let aqua = try AquaConfig(apiKey: "aqua", languageCode: "ja")

        #expect(cohere.language == .german)
        #expect(grok.language == .filipino)
        #expect(aqua.language == .japanese)
    }

    @MainActor
    @Test("ElevenLabs config applies realtime and file defaults")
    func elevenLabsConfigAppliesDefaults() {
        let service = SpeechService(elevenLabs: ElevenLabsConfig(apiKey: "eleven"))

        #expect(service.elevenLabs?.apiKey == "eleven")
        #expect(service.elevenLabs?.realtimeModelID == .scribeV2Realtime)
        #expect(service.elevenLabs?.fileModelID == .scribeV1)
    }
}

private func temporaryAudioFileURL() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    try? Data("test".utf8).write(to: url)
    return url
}
