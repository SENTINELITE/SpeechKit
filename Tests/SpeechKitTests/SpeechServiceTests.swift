import Foundation
import Testing
@testable import SpeechKit

@Suite("SpeechService")
struct SpeechServiceTests {
    @MainActor
    @Test("startListening surfaces missing ElevenLabs configuration")
    func startListeningWithoutElevenLabsConfigurationSetsFallbackError() async {
        let service = SpeechService()

        await service.startListening()

        #expect(service.connectionState == .error("ElevenLabs is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.elevenLabs))
    }

    @MainActor
    @Test("routing rejects mismatched provider options")
    func transcribeRejectsMismatchedOptions() async {
        let service = SpeechService(
            elevenLabs: ElevenLabsConfiguration(apiKey: "eleven"),
            cohere: CohereConfiguration(apiKey: "cohere"),
            grok: GrokConfiguration(apiKey: "xai"),
            aqua: AquaConfiguration(apiKey: "aqua"),
            openAI: OpenAIConfiguration(apiKey: "openai")
        )
        let fileURL = temporaryAudioFileURL()

        await #expect(throws: SpeechError.invalidOptionsForProvider(expected: .openAI, received: .elevenLabs)) {
            _ = try await service.transcribeAudioFile(
                provider: .openAI,
                file: fileURL,
                options: .elevenLabs(modelID: .scribeV1)
            )
        }
    }

    @MainActor
    @Test("startListening surfaces missing OpenAI configuration")
    func startListeningWithoutOpenAIConfigurationSetsFallbackError() async {
        let service = SpeechService()

        await service.startListening(provider: .openAI)

        #expect(service.connectionState == .error("OpenAI is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.openAI))
    }

    @Test("provider configurations support raw language codes")
    func providerConfigurationsSupportRawLanguageCodes() throws {
        let cohere = try CohereConfiguration(apiKey: "cohere", languageCode: "de")
        let grok = try GrokConfiguration(apiKey: "xai", languageCode: "fil")
        let aqua = try AquaConfiguration(apiKey: "aqua", languageCode: "ja")

        #expect(cohere.language == .german)
        #expect(grok.language == .filipino)
        #expect(aqua.language == .japanese)
    }

    @MainActor
    @Test("ElevenLabs configuration applies realtime and file defaults")
    func elevenLabsConfigurationAppliesDefaults() {
        let service = SpeechService(elevenLabs: ElevenLabsConfiguration(apiKey: "eleven"))

        #expect(service.elevenLabs?.apiKey == "eleven")
        #expect(service.elevenLabs?.realtimeModelID == .scribeV2Realtime)
        #expect(service.elevenLabs?.fileTranscriptionModelID == .scribeV1)
    }

    @MainActor
    @Test("OpenAI configuration applies file and realtime defaults")
    func openAIConfigurationAppliesDefaults() {
        let service = SpeechService(openAI: OpenAIConfiguration(apiKey: "openai"))

        #expect(service.openAI?.apiKey == "openai")
        #expect(service.openAI?.fileTranscriptionModelID == .gpt4oTranscribe)
        #expect(service.openAI?.realtimeSessionModelID == .gptRealtime)
        #expect(service.openAI?.realtimeTranscriptionModelID == .gpt4oTranscribe)
        #expect(service.openAI?.realtimeCommitInterval == 1)
    }

    @MainActor
    @Test("OpenAI provider-neutral options resolve diarization controls")
    func openAIProviderNeutralOptionsResolveDiarizationControls() {
        let knownSpeaker = OpenAIKnownSpeaker(name: "agent", referenceDataURL: "data:audio/wav;base64,AAA")
        let config = OpenAIConfiguration(
            apiKey: "openai",
            fileTranscriptionModelID: .gpt4oTranscribeDiarize,
            diarizationChunkingStrategy: .serverVAD(OpenAIDiarizationVADOptions(threshold: 0.3)),
            knownSpeakers: [knownSpeaker]
        )
        let service = SpeechService(openAI: config)

        let resolved = service.resolvedOpenAIOptions(
            from: .openAI(language: "en", knownSpeakers: []),
            config: config
        )

        #expect(resolved.modelID == .gpt4oTranscribeDiarize)
        #expect(resolved.language == "en")
        #expect(resolved.diarizationChunkingStrategy == .serverVAD(OpenAIDiarizationVADOptions(threshold: 0.3)))
        #expect(resolved.knownSpeakers == [])
    }

    @MainActor
    @Test("Grok configuration applies realtime defaults")
    func grokConfigurationAppliesRealtimeDefaults() {
        let service = SpeechService(grok: GrokConfiguration(apiKey: "xai"))

        #expect(service.grok?.apiKey == "xai")
        #expect(service.grok?.modelID == .stt)
        #expect(service.grok?.realtimeOptions.sampleRate == 16000)
        #expect(service.grok?.realtimeOptions.encoding == .pcm)
        #expect(service.grok?.realtimeOptions.interimResults == true)
    }

    @MainActor
    @Test("startListening surfaces missing Grok configuration")
    func startListeningWithoutGrokConfigurationSetsFallbackError() async {
        let service = SpeechService()

        await service.startListening(provider: .grok)

        #expect(service.realtimeConnectionState == .error("Grok is not configured"))
        #expect(service.connectionState == .error("Grok is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.grok))
    }

    @MainActor
    @Test("same-provider start is a no-op while lifecycle is active")
    func sameProviderStartIsNoOpWhileLifecycleIsActive() async {
        let service = SpeechService()
        service.activeRealtimeProvider = .elevenLabs
        service.elevenLabsRealtimeService.setLifecycleStateForTesting(.connecting)

        await service.startListening(provider: .elevenLabs)

        #expect(service.connectionState == .connecting)
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("provider switch stops previous provider while connecting")
    func providerSwitchStopsPreviousProviderWhileConnecting() async {
        let service = SpeechService()
        service.activeRealtimeProvider = .elevenLabs
        service.elevenLabsRealtimeService.setLifecycleStateForTesting(.connecting)

        await service.startListening(provider: .openAI)

        #expect(service.activeRealtimeProvider == .openAI)
        #expect(service.elevenLabsRealtimeService.connectionState == .disconnected)
        #expect(service.connectionState == .error("OpenAI is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.openAI))
    }

    @MainActor
    @Test("stopListening is idempotent")
    func stopListeningIsIdempotent() async {
        let service = SpeechService()

        await service.stopListening()
        await service.stopListening()

        #expect(service.connectionState == .disconnected)
        #expect(service.lastError == nil)
    }

    @Test("connecting and stopping count as active lifecycle states")
    func connectingAndStoppingCountAsLifecycleActive() {
        #expect(SpeechRealtimeConnectionState.connecting.isLifecycleActive)
        #expect(SpeechRealtimeConnectionState.stopping.isLifecycleActive)
        #expect(!SpeechRealtimeConnectionState.disconnected.isLifecycleActive)
    }

    @Test("OpenAI realtime session update encodes transcription session")
    func openAIRealtimeSessionUpdateEncodesTranscriptionSession() throws {
        let message = OpenAIRealtimeSessionUpdateMessage(
            options: OpenAIRealtimeSessionOptions(
                language: "en",
                delay: .milliseconds(300),
                commitInterval: 1
            )
        )
        let data = try JSONEncoder().encode(message)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"type\":\"session.update\""))
        #expect(json.contains("\"type\":\"transcription\""))
        #expect(json.contains("\"model\":\"gpt-4o-transcribe\""))
        #expect(json.contains("\"language\":\"en\""))
        #expect(json.contains("\"rate\":24000"))
        #expect(json.contains("\"type\":\"audio\\/pcm\"") || json.contains("\"type\":\"audio/pcm\""))
        #expect(json.contains("\"milliseconds\":300"))
    }

    @Test("OpenAI realtime audio append encodes base64 audio")
    func openAIRealtimeAudioAppendEncodesBase64Audio() throws {
        let message = OpenAIInputAudioBufferAppendMessage(audioData: Data([1, 2, 3]))
        let data = try JSONEncoder().encode(message)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"type\":\"input_audio_buffer.append\""))
        #expect(json.contains("\"audio\":\"AQID\""))
    }

    @Test("Grok realtime options encode query items")
    func grokRealtimeOptionsEncodeQueryItems() throws {
        let options = GrokRealtimeOptions(
            language: .english,
            sampleRate: 16000,
            interimResults: true,
            endpointingMilliseconds: 250,
            multichannel: true,
            channels: 2,
            diarize: true,
            fillerWords: true,
            keyTerms: ["SpeechKit", "Kirkland"]
        )

        let items = try options.queryItems()

        #expect(options.keyTerms == ["SpeechKit", "Kirkland"])
        #expect(items.contains(URLQueryItem(name: "language", value: "en")))
        #expect(items.contains(URLQueryItem(name: "sample_rate", value: "16000")))
        #expect(items.contains(URLQueryItem(name: "encoding", value: "pcm")))
        #expect(items.contains(URLQueryItem(name: "interim_results", value: "true")))
        #expect(items.contains(URLQueryItem(name: "endpointing", value: "250")))
        #expect(items.contains(URLQueryItem(name: "multichannel", value: "true")))
        #expect(items.contains(URLQueryItem(name: "channels", value: "2")))
        #expect(items.contains(URLQueryItem(name: "diarize", value: "true")))
        #expect(items.contains(URLQueryItem(name: "filler_words", value: "true")))
        #expect(items.filter { $0.name == "keyterm" }.map(\.value) == ["SpeechKit", "Kirkland"])
    }

    @Test("Grok realtime options reject invalid endpointing")
    func grokRealtimeOptionsRejectInvalidEndpointing() throws {
        let options = GrokRealtimeOptions(endpointingMilliseconds: 5001)

        #expect(throws: SpeechError.providerFailure(provider: .grok, reason: "endpointingMilliseconds must be between 0 and 5000.")) {
            try options.validate()
        }
    }

    @Test("Grok realtime transcript partial decodes")
    func grokRealtimeTranscriptPartialDecodes() throws {
        let data = Data("""
        {
          "type": "transcript.partial",
          "text": "hello world",
          "is_final": true,
          "speech_final": false,
          "start": 1.25,
          "duration": 0.5,
          "channel_index": 1,
          "speaker": "0",
          "words": [
            { "text": "hello", "start": 1.25, "end": 1.45, "speaker": "0", "confidence": 0.9 }
          ]
        }
        """.utf8)

        let message = try JSONDecoder().decode(GrokRealtimeMessage.self, from: data)

        guard case .transcriptPartial(let transcript) = message else {
            Issue.record("Expected transcript partial")
            return
        }
        #expect(transcript.text == "hello world")
        #expect(transcript.isFinal == true)
        #expect(transcript.speechFinal == false)
        #expect(transcript.channelIndex == 1)
        #expect(transcript.words?.first?.text == "hello")
    }
}

private func temporaryAudioFileURL() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    try? Data("test".utf8).write(to: url)
    return url
}
