import Foundation
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

    @Test("OpenAI latest transcription models and context options are constructible")
    func openAILatestTranscriptionPublicOptionsAreConstructible() {
        let fileOptions = OpenAIFileTranscriptionOptions(
            modelID: .gptTranscribe,
            languages: ["en", "fr"],
            keywords: ["SpeechKit", "AC-42"]
        )
        let realtimeOptions = OpenAIRealtimeSessionOptions(
            transcriptionModelID: .gptLiveTranscribe,
            languages: ["en", "fr"],
            keywords: ["SpeechKit"],
            delay: .low
        )
        let config = OpenAIConfiguration(
            apiKey: "openai",
            fileTranscriptionModelID: .gptTranscribe,
            realtimeTranscriptionModelID: .gptLiveTranscribe,
            languages: ["en", "fr"],
            keywords: ["SpeechKit"]
        )

        #expect(fileOptions.modelID == .gptTranscribe)
        #expect(realtimeOptions.transcriptionModelID == .gptLiveTranscribe)
        #expect(config.languages == ["en", "fr"])
    }

    #if !os(watchOS)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @Test("Apple Speech public options are constructible")
    func appleSpeechPublicOptionsAreConstructible() {
        let locale = Locale(identifier: "en-US")
        let config = AppleSpeechConfiguration(
            locale: locale,
            preparesAssetsAutomatically: false,
            contextualStrings: ["SpeechKit"],
            modelRetention: .lingering
        )
        let fileOptions = AppleSpeechFileTranscriptionOptions(
            locale: locale,
            preparesAssetsAutomatically: false
        )
        let providerOptions: SpeechFileTranscriptionOptions = .apple(
            locale: locale,
            preparesAssetsAutomatically: false
        )

        #expect(config.locale == locale)
        #expect(config.preparesAssetsAutomatically == false)
        #expect(config.contextualStrings == ["SpeechKit"])
        #expect(config.modelRetention == .lingering)
        #expect(fileOptions.locale == locale)
        #expect(fileOptions.preparesAssetsAutomatically == false)
        #expect(providerOptions == .apple(locale: locale, preparesAssetsAutomatically: false))
    }
    #endif
}
