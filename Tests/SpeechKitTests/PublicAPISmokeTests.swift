import SpeechKit
import Testing

@Suite("Public API Smoke Tests")
struct PublicAPISmokeTests {
    @Test("OpenAI diarization public options are constructible")
    func openAIDiarizationPublicOptionsAreConstructible() {
        let speaker = OpenAIKnownSpeaker(
            name: "agent",
            referenceDataURL: "data:audio/wav;base64,AAA"
        )
        let options = OpenAIFileTranscriptionOptions(
            modelID: .gpt4oTranscribeDiarize,
            diarizationChunkingStrategy: .serverVAD(
                OpenAIDiarizationVADOptions(
                    threshold: 0.4,
                    prefixPaddingMilliseconds: 250,
                    silenceDurationMilliseconds: 600
                )
            ),
            knownSpeakers: [speaker]
        )
        let config = OpenAIConfiguration(
            apiKey: "openai",
            fileTranscriptionModelID: .gpt4oTranscribeDiarize,
            diarizationChunkingStrategy: .auto,
            knownSpeakers: [speaker]
        )
        let providerOptions: SpeechFileTranscriptionOptions = .openAI(
            modelID: .gpt4oTranscribeDiarize,
            diarizationChunkingStrategy: .auto,
            knownSpeakers: [speaker]
        )

        #expect(options.modelID == .gpt4oTranscribeDiarize)
        #expect(options.knownSpeakers == [speaker])
        #expect(config.diarizationChunkingStrategy == .auto)
        #expect(providerOptions == .openAI(
            modelID: .gpt4oTranscribeDiarize,
            diarizationChunkingStrategy: .auto,
            knownSpeakers: [speaker]
        ))
    }
}
