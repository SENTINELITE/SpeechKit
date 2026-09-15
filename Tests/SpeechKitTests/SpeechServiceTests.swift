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
                options: .elevenLabs(modelID: .scribeV2)
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
        #expect(service.elevenLabs?.fileTranscriptionModelID == .scribeV2)
    }

    @MainActor
    @Test("OpenAI configuration applies file and realtime defaults")
    func openAIConfigurationAppliesDefaults() {
        let service = SpeechService(openAI: OpenAIConfiguration(apiKey: "openai"))

        #expect(service.openAI?.apiKey == "openai")
        #expect(service.openAI?.fileTranscriptionModelID == .gptTranscribe)
        #expect(service.openAI?.realtimeSessionModelID == .gptRealtime)
        #expect(service.openAI?.realtimeTranscriptionModelID == .gptLiveTranscribe)
        #expect(service.openAI?.realtimeDelay == .low)
        #expect(service.openAI?.realtimeCommitInterval == 1)
    }

    @MainActor
    @Test("OpenAI provider-neutral options resolve diarization controls")
    @available(*, deprecated, message: "Covers OpenAI models scheduled for shutdown.")
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
    @Test("Meta configuration applies file and realtime defaults")
    func metaConfigurationAppliesDefaults() {
        let service = SpeechService(meta: MetaConfiguration(apiKey: "meta"))

        #expect(service.meta?.apiKey == "meta")
        #expect(service.meta?.modelID == .museVoiceTranscribe1)
        #expect(service.meta?.mode == .endpointing)
        #expect(service.meta?.languageBias == [])
        #expect(service.meta?.realtimeOptions.audioEncoding == .pcm24kHz)
        #expect(service.meta?.realtimeOptions.partialMode == .cumulative)
        #expect(service.meta?.realtimeOptions.sampleRate == 24000)
    }

    @MainActor
    @Test("Gemini configuration applies file and realtime defaults")
    func geminiConfigurationAppliesDefaults() {
        let service = SpeechService(gemini: GeminiConfiguration(apiKey: "gemini"))

        #expect(service.gemini?.apiKey == "gemini")
        #expect(service.gemini?.fileTranscriptionModelID == .transcribe35)
        #expect(service.gemini?.realtimeModelID == .transcribeLive35)
        #expect(service.gemini?.mode == .verbatim)
        #expect(service.gemini?.diarize == false)
        #expect(service.gemini?.uploadStrategy == .automatic)
        #expect(service.gemini?.processingMode == .synchronous)
        #expect(service.gemini?.realtimeOptions.sampleRate == 16000)
        #expect(service.gemini?.realtimeOptions.automaticActivityDetection == true)
    }

    @Test("Meta configuration supports raw language names")
    func metaConfigurationSupportsRawLanguageNames() throws {
        let meta = try MetaConfiguration(apiKey: "meta", languageNames: ["English", "Mandarin Chinese"])

        #expect(meta.languageBias == [.english, .mandarinChinese])
    }

    @Test("Meta configuration rejects unknown language names")
    func metaConfigurationRejectsUnknownLanguageNames() {
        #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "Unsupported language: Klingon.")) {
            _ = try MetaConfiguration(apiKey: "meta", languageNames: ["Klingon"])
        }
    }

    @MainActor
    @Test("startListening surfaces missing Meta configuration")
    func startListeningWithoutMetaConfigurationSetsFallbackError() async {
        let service = SpeechService()

        await service.startListening(provider: .meta)

        #expect(service.realtimeConnectionState == .error("Meta is not configured"))
        #expect(service.connectionState == .error("Meta is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.meta))
    }

    @MainActor
    @Test("startListening surfaces missing Gemini configuration")
    func startListeningWithoutGeminiConfigurationSetsFallbackError() async {
        let service = SpeechService()

        await service.startListening(provider: .gemini)

        #expect(service.realtimeConnectionState == .error("Gemini is not configured"))
        #expect(service.connectionState == .error("Gemini is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.gemini))
    }

    @MainActor
    @Test("routing rejects Gemini options for Meta")
    func metaRoutingRejectsGeminiOptions() async {
        let service = SpeechService(
            meta: MetaConfiguration(apiKey: "meta"),
            gemini: GeminiConfiguration(apiKey: "gemini")
        )
        let fileURL = temporaryAudioFileURL()

        await #expect(throws: SpeechError.invalidOptionsForProvider(expected: .meta, received: .gemini)) {
            _ = try await service.transcribeAudioFile(
                provider: .meta,
                file: fileURL,
                options: .gemini(diarize: true)
            )
        }
    }

    @Test("Meta handshake message encodes session configuration")
    func metaHandshakeMessageEncodesSessionConfiguration() throws {
        let options = MetaRealtimeOptions(
            mode: .diarization,
            audioEncoding: .pcm24kHz,
            partialMode: .delta,
            emitAudioProgress: true,
            languageBias: [.english],
            keywords: ["SpeechKit"]
        )

        let data = try JSONEncoder().encode(options.handshakeMessage(secret: "meta-key"))
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"accessToken\":\"Bearer meta-key\""))
        #expect(json.contains("\"audioEncoding\":\"PCM_24KHZ\""))
        #expect(json.contains("\"model\":\"muse-voice-transcribe-1.0\""))
        #expect(json.contains("\"mode\":\"DIARIZATION\""))
        #expect(json.contains("\"partialMode\":\"DELTA\""))
        #expect(json.contains("\"emitAudioProgress\":true"))
        #expect(json.contains("\"languageBias\":[\"English\"]"))
        #expect(json.contains("\"keywords\":[\"SpeechKit\"]"))
    }

    @Test("Meta realtime options reject WAV encoding")
    func metaRealtimeOptionsRejectWAVEncoding() {
        let options = MetaRealtimeOptions(audioEncoding: .wav)

        #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "Realtime transcription requires a raw PCM audio encoding.")) {
            try options.validate()
        }
    }

    @Test("Meta realtime session acknowledgement decodes")
    func metaRealtimeSessionAcknowledgementDecodes() throws {
        let data = Data("""
        {"sessionId":"9f1c"}
        """.utf8)

        let message = try JSONDecoder().decode(MetaRealtimeMessage.self, from: data)

        guard case .sessionCreated(let sessionID) = message else {
            Issue.record("Expected a session acknowledgement.")
            return
        }
        #expect(sessionID == "9f1c")
    }

    @Test("Meta realtime events decode by type")
    func metaRealtimeEventsDecodeByType() throws {
        let decoder = JSONDecoder()

        let transcript = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"transcript","transcript":"how is the weather","final":false,"audioProcessedMs":3200}
        """.utf8))
        guard case .transcript(let partial) = transcript else {
            Issue.record("Expected a transcript event.")
            return
        }
        #expect(partial.transcript == "how is the weather")
        #expect(partial.final == false)
        #expect(partial.audioProcessedMs == 3200)

        let speaker = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"speaker","label":"A","audioProcessedMs":2480}
        """.utf8))
        guard case .speaker(let label, _) = speaker else {
            Issue.record("Expected a speaker event.")
            return
        }
        #expect(label == "A")

        let complete = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"speechComplete","turnId":1,"transcript":"How is the weather?","audioProcessedMs":3600}
        """.utf8))
        guard case .speechComplete(let turnID, let text, _) = complete else {
            Issue.record("Expected a speech complete event.")
            return
        }
        #expect(turnID == 1)
        #expect(text == "How is the weather?")

        let failure = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"error","message":"Bad audio","sessionId":"9f1c"}
        """.utf8))
        guard case .error(let message) = failure else {
            Issue.record("Expected an error event.")
            return
        }
        #expect(message == "Bad audio")
    }

    @Test("Gemini setup message encodes the live session")
    func geminiSetupMessageEncodesLiveSession() throws {
        let options = GeminiRealtimeOptions(
            languageCodes: ["en-US"],
            customVocabulary: ["SpeechKit"],
            mode: .verbatim,
            automaticActivityDetection: false
        )

        let data = try JSONEncoder().encode(options.setupMessage())
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"model\":\"models\\/gemini-3.5-transcribe-live\"") || json.contains("\"model\":\"models/gemini-3.5-transcribe-live\""))
        #expect(json.contains("\"responseModalities\":[\"TEXT\"]"))
        #expect(json.contains("\"languageCodes\":[\"en-US\"]"))
        #expect(json.contains("\"customVocabulary\":[\"SpeechKit\"]"))
        #expect(json.contains("\"mode\":\"VERBATIM\""))
        #expect(json.contains("\"disabled\":true"))
    }

    @Test("Gemini realtime audio message encodes base64 PCM")
    func geminiRealtimeAudioMessageEncodesBase64PCM() throws {
        let message = GeminiRealtimeAudioMessage(audioData: Data([1, 2, 3]))
        let data = try JSONEncoder().encode(message)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"data\":\"AQID\""))
        #expect(json.contains("\"mimeType\":\"audio\\/pcm;rate=16000\"") || json.contains("\"mimeType\":\"audio/pcm;rate=16000\""))
    }

    @Test("Gemini live messages decode by top-level key")
    func geminiLiveMessagesDecodeByTopLevelKey() throws {
        let decoder = JSONDecoder()

        let setup = try decoder.decode(GeminiLiveMessage.self, from: Data("""
        {"setupComplete":{}}
        """.utf8))
        guard case .setupComplete = setup else {
            Issue.record("Expected a setup complete event.")
            return
        }

        let interim = try decoder.decode(GeminiLiveMessage.self, from: Data("""
        {"serverContent":{"interimInputTranscription":{"text":"partial"}}}
        """.utf8))
        guard case .interimTranscription(let interimText) = interim else {
            Issue.record("Expected an interim transcription event.")
            return
        }
        #expect(interimText == "partial")

        let final = try decoder.decode(GeminiLiveMessage.self, from: Data("""
        {"serverContent":{"inputTranscription":{"text":"final"}}}
        """.utf8))
        guard case .finalTranscription(let finalText) = final else {
            Issue.record("Expected a final transcription event.")
            return
        }
        #expect(finalText == "final")

        let goAway = try decoder.decode(GeminiLiveMessage.self, from: Data("""
        {"goAway":{"timeLeft":"10s"}}
        """.utf8))
        guard case .goAway(let timeLeft) = goAway else {
            Issue.record("Expected a go away event.")
            return
        }
        #expect(timeLeft == "10s")
    }

    @Test("Gemini word info decodes duration offsets")
    func geminiWordInfoDecodesDurationOffsets() throws {
        let data = Data("""
        {"type":"word_info","text":"Hello","speaker":"spk_1","start_offset":"0.100s","end_offset":"0.450s","start_index":0,"end_index":5}
        """.utf8)

        let word = try JSONDecoder().decode(GeminiWordInfo.self, from: data)

        #expect(word.text == "Hello")
        #expect(word.speaker == "spk_1")
        #expect(word.start == 0.1)
        #expect(word.end == 0.45)
        #expect(word.startIndex == 0)
        #expect(word.endIndex == 5)
        #expect(GeminiWordInfo.seconds(fromOffset: "12s") == 12)
        #expect(GeminiWordInfo.seconds(fromOffset: nil) == nil)
    }

    #if !os(watchOS)
    @Test("Apple providers are gated from allCases until OS 26")
    func appleProvidersAreGatedFromAllCasesUntilOS26() {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            #expect(SpeechRealtimeProvider.allCases.contains(.apple))
            #expect(SpeechFileTranscriptionProvider.allCases.contains(.apple))
        } else {
            #expect(!SpeechRealtimeProvider.allCases.contains { $0.rawValue == "apple" })
            #expect(!SpeechFileTranscriptionProvider.allCases.contains { $0.rawValue == "apple" })
        }
    }

    @MainActor
    @Test("startListening surfaces Apple OS availability before configuration on older OS versions")
    func startListeningWithAppleBeforeOS26SurfacesAvailabilityError() async {
        guard #unavailable(iOS 26.0, macOS 26.0, visionOS 26.0) else { return }

        let service = SpeechService()

        await service.startListening(provider: .apple)

        #expect(service.realtimeConnectionState == .error(SpeechError.appleSpeechUnavailable.localizedDescription))
        #expect(service.lastError as? SpeechError == .appleSpeechUnavailable)
    }
    #endif

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
    @available(*, deprecated, message: "Covers OpenAI models scheduled for shutdown.")
    func openAIRealtimeSessionUpdateEncodesTranscriptionSession() throws {
        let message = OpenAIRealtimeSessionUpdateMessage(
            options: OpenAIRealtimeSessionOptions(
                transcriptionModelID: .gpt4oTranscribe,
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
        #expect(json.contains("\"turn_detection\":null"))
    }

    @Test("OpenAI live transcription session encodes plural context and a named delay")
    func openAILiveRealtimeSessionUpdateEncodesNewModelFields() throws {
        let message = OpenAIRealtimeSessionUpdateMessage(
            options: OpenAIRealtimeSessionOptions(
                transcriptionModelID: .gptLiveTranscribe,
                languages: ["en", "fr"],
                prompt: "A billing support call.",
                keywords: ["AC-42", "SpeechKit"],
                delay: .low
            )
        )
        let data = try JSONEncoder().encode(message)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"model\":\"gpt-live-transcribe\""))
        #expect(json.contains("\"languages\":[\"en\",\"fr\"]"))
        #expect(!json.contains("\"language\":"))
        #expect(json.contains("\"prompt\":\"A billing support call.\""))
        #expect(json.contains("\"keywords\":[\"AC-42\",\"SpeechKit\"]"))
        #expect(json.contains("\"delay\":\"low\""))
        #expect(json.contains("\"turn_detection\":null"))
    }

    @Test("OpenAI committed realtime transcript decodes detected languages")
    func openAIRealtimeCompletionDecodesDetectedLanguages() throws {
        let data = Data("""
        {"type":"conversation.item.input_audio_transcription.completed","item_id":"item_003","transcript":"Bonjour","languages":[{"code":"fr"}]}
        """.utf8)

        let message = try JSONDecoder().decode(OpenAIRealtimeMessage.self, from: data)

        guard case .transcriptionCompleted(let completed) = message else {
            Issue.record("Expected a completed transcription event.")
            return
        }
        #expect(completed.itemID == "item_003")
        #expect(completed.languages == [OpenAITranscriptionLanguage(code: "fr")])
    }

    @Test("OpenAI realtime audio append encodes base64 audio")
    func openAIRealtimeAudioAppendEncodesBase64Audio() throws {
        let message = OpenAIInputAudioBufferAppendMessage(audioData: Data([1, 2, 3]))
        let data = try JSONEncoder().encode(message)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"type\":\"input_audio_buffer.append\""))
        #expect(json.contains("\"audio\":\"AQID\""))
    }

    @Test("OpenAI realtime only commits after 100 ms of 24 kHz PCM")
    func openAIRealtimeCommitGateRequiresMinimumAudio() {
        var gate = OpenAIInputAudioCommitGate()

        gate.append(OpenAIInputAudioCommitGate.minimumAudioBytes - 1)
        #expect(!gate.isReady)

        gate.append(1)
        #expect(gate.isReady)

        gate.markCommitted()
        #expect(!gate.isReady)
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

/// A freshly created temporary directory, unique to this call.
private func uniqueTemporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Writes a stub audio file into a fresh per-call temporary directory.
///
/// Tests run in parallel, so each call gets its own directory rather than
/// sharing one path in the process-wide temporary directory.
private func temporaryAudioFileURL() -> URL {
    let url = uniqueTemporaryDirectory().appendingPathComponent("sample.wav")
    try? speechServiceMinimalWAVData().write(to: url)
    return url
}

/// A valid 16 kHz, 16-bit, mono PCM WAV holding 0.1 seconds of silence.
private func speechServiceMinimalWAVData() -> Data {
    var data = Data([
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0xA4, 0x0C, 0x00, 0x00, // chunk size: 36 + 3200
        0x57, 0x41, 0x56, 0x45, // "WAVE"
        0x66, 0x6D, 0x74, 0x20, // "fmt "
        0x10, 0x00, 0x00, 0x00, // fmt chunk size: 16
        0x01, 0x00,             // PCM
        0x01, 0x00,             // 1 channel
        0x80, 0x3E, 0x00, 0x00, // 16000 Hz
        0x00, 0x7D, 0x00, 0x00, // 32000 bytes per second
        0x02, 0x00,             // block align: 2
        0x10, 0x00,             // 16 bits per sample
        0x64, 0x61, 0x74, 0x61, // "data"
        0x80, 0x0C, 0x00, 0x00  // data chunk size: 3200
    ])
    data.append(Data(repeating: 0, count: 3_200))
    return data
}
