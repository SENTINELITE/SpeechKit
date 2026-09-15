import Foundation
import SpeechKit
import Testing

@Suite("Public API Smoke Tests")
struct PublicAPISmokeTests {
    @Test("OpenAI diarization public options are constructible")
    @available(*, deprecated, message: "Covers OpenAI models scheduled for shutdown.")
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

    @Test("Model allCases keep deprecated models in declaration order")
    func modelAllCasesIncludeDeprecatedModels() {
        #expect(OpenAIFileTranscriptionModelID.allCases.map(\.rawValue) == [
            "whisper-1",
            "gpt-4o-transcribe",
            "gpt-4o-mini-transcribe",
            "gpt-4o-mini-transcribe-2025-12-15",
            "gpt-transcribe",
            "gpt-4o-transcribe-diarize",
        ])
        #expect(OpenAIRealtimeTranscriptionModelID.allCases.map(\.rawValue) == [
            "gpt-live-transcribe",
            "gpt-transcribe",
            "gpt-4o-transcribe",
            "gpt-4o-mini-transcribe",
            "gpt-4o-transcribe-latest",
            "whisper-1",
        ])
        #expect(ElevenLabsModelID.allCases.map(\.rawValue) == [
            "scribe_v2_realtime",
            "scribe_v1",
            "scribe_v2",
        ])
    }

    @Test("ElevenLabs detailed file transcription response is public")
    func elevenLabsDetailedResponseIsPublic() throws {
        let data = Data(
            """
            {"text":"hello","language_code":"en","words":[{"text":"hello","start":0.0,"end":0.5,"type":"word"}]}
            """.utf8
        )

        let response: ElevenLabsFileTranscriptionResponse = try JSONDecoder().decode(
            ElevenLabsFileTranscriptionResponse.self,
            from: data
        )
        let words: [ElevenLabsWordTimestamp] = response.words ?? []

        #expect(response.text == "hello")
        #expect(response.languageCode == "en")
        #expect(words.first?.text == "hello")
        #expect(words.first?.start == 0.0)
        #expect(words.first?.end == 0.5)
    }

    @Test("Meta public options are constructible")
    func metaPublicOptionsAreConstructible() {
        let realtimeOptions = MetaRealtimeOptions(
            mode: .diarization,
            audioEncoding: .pcm16kHz,
            partialMode: .delta,
            emitAudioProgress: true,
            languageBias: [.english, .mandarinChinese],
            keywords: ["SpeechKit"]
        )
        let fileOptions = MetaFileTranscriptionOptions(
            mode: .endpointing,
            audioEncoding: .wav,
            languageBias: [.english],
            keywords: ["SpeechKit"],
            sessionID: "session-1"
        )
        let config = MetaConfiguration(
            apiKey: "meta",
            mode: .diarization,
            languageBias: [.english],
            keywords: ["SpeechKit"],
            realtimeOptions: realtimeOptions
        )
        let providerOptions: SpeechFileTranscriptionOptions = .meta(
            mode: .endpointing,
            languageBias: [.english],
            keywords: ["SpeechKit"]
        )

        #expect(realtimeOptions.sampleRate == 16000)
        #expect(fileOptions.modelID == .museVoiceTranscribe1)
        #expect(fileOptions.sessionID == "session-1")
        #expect(config.realtimeOptions == realtimeOptions)
        #expect(providerOptions == .meta(
            mode: .endpointing,
            languageBias: [.english],
            keywords: ["SpeechKit"]
        ))
    }

    @Test("Gemini public options are constructible")
    func geminiPublicOptionsAreConstructible() {
        let realtimeOptions = GeminiRealtimeOptions(
            languageCodes: ["en-US"],
            mode: .verbatim,
            automaticActivityDetection: false
        )
        let fileOptions = GeminiFileTranscriptionOptions(
            languageCodes: ["en-US"],
            diarize: true,
            timestampGranularities: [.word],
            uploadStrategy: .filesAPI,
            processingMode: .background(pollInterval: 5)
        )
        let config = GeminiConfiguration(
            apiKey: "gemini",
            languageCodes: ["en-US"],
            diarize: true,
            timestampGranularities: [.word],
            realtimeOptions: realtimeOptions
        )
        let providerOptions: SpeechFileTranscriptionOptions = .gemini(
            languageCodes: ["en-US"],
            diarize: true,
            timestampGranularities: [.word]
        )
        let word = GeminiWordInfo(text: "Hello", speaker: "spk_1", start: 0.1, end: 0.45)

        #expect(realtimeOptions.sampleRate == 16000)
        #expect(fileOptions.uploadStrategy == .filesAPI)
        #expect(fileOptions.processingMode == .background(pollInterval: 5))
        #expect(fileOptions.inlineUploadThresholdBytes == 20 * 1024 * 1024)
        #expect(config.realtimeOptions == realtimeOptions)
        #expect(providerOptions == .gemini(
            languageCodes: ["en-US"],
            diarize: true,
            timestampGranularities: [.word]
        ))
        #expect(word.start == 0.1)
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
