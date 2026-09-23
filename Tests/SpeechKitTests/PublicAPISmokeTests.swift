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

    @Test("Speech-to-speech conversation public types are constructible")
    func conversationPublicTypesAreConstructible() {
        let entry = SpeechConversationTranscriptEntry(
            provider: .openAI,
            role: .user,
            text: " Hello there ",
            startMilliseconds: 600,
            endMilliseconds: 1200
        )
        let responses = OpenAILiveResponsesDelegation(
            model: "gpt-5.6-luna",
            instructions: "Use the tools.",
            tools: [["type": "function", "name": "lookup_weather"]],
            toolChoice: .function(name: "lookup_weather"),
            parallelToolCalls: true,
            maxOutputTokens: 256,
            serviceTier: "auto"
        )
        let options = OpenAILiveSessionOptions(
            modelID: .gptLive1,
            instructions: "Be brief.",
            voice: .cedar,
            audioFormat: .pcm16k,
            delegation: .responses(responses),
            closeTimeout: 10,
            turnGapMilliseconds: 900
        )
        let info = OpenAILiveSessionInfo(
            id: "live_1",
            expiresAt: Date(timeIntervalSince1970: 1789518426),
            model: "gpt-live-1",
            voice: .marin,
            status: "active"
        )
        let usage = OpenAILiveUsage(seconds: 7, contextWindowUsageRatio: 0.5)
        let delegationRequest = OpenAILiveDelegationRequest(id: "del_1", target: "client")
        let responseEvent = OpenAILiveResponseEvent(
            delegationID: "del_1",
            eventType: "response.completed",
            raw: ["type": "response.completed", "done": true]
        )
        let conversationError = SpeechConversationError.commandRejected(code: "invalid_value", message: "Too long.")

        #expect(SpeechConversationProvider.allCases == [.openAI])
        #expect(SpeechConversationRole.assistant.rawValue == "assistant")
        #expect(entry.displayText == "Hello there")
        #expect(entry.isOpen)
        #expect(SpeechConversationState.active(sessionID: "live_1").isActive)
        #expect(SpeechConversationState.ended(reason: .closeRequested, seconds: 7).isActive == false)
        #expect(SpeechConversationEndReason(providerRawValue: "remote_hangup") == .remoteHangup)
        #expect(SpeechConversationEndReason(providerRawValue: "supernova") == .unknown)
        #expect(options.modelID == .gptLive1)
        #expect(options.delegation == .responses(responses))
        #expect(options.audioFormat.mimeType == "audio/pcm")
        #expect(options.audioFormat.sampleRate == 16000)
        #expect(OpenAILiveAudioFormat.pcmu8k.mimeType == "audio/pcmu")
        #expect(OpenAILiveAudioFormat.pcma8k.sampleRate == 8000)
        #expect(OpenAILiveVoice.knownVoices == [.marin, .cedar, .alloy])
        #expect(options.voice == "cedar")
        #expect(info.voice == .marin)
        #expect(usage.contextWindowUsageRatio == 0.5)
        #expect(delegationRequest.target == "client")
        #expect(responseEvent.raw.objectValue?["done"] == .bool(true))
        #expect(conversationError.errorDescription == "Too long. (invalid_value)")
        #expect(OpenAILiveError.closeTimedOut.errorDescription == "Timed out waiting for the session to close")
    }

    @Test("Conversation service and configuration surfaces are constructible")
    @MainActor
    func conversationPublicSurfacesAreConstructible() {
        let options = OpenAILiveSessionOptions(
            instructions: "Be brief.",
            voice: .cedar,
            audioFormat: .pcm16k,
            delegation: .client,
            closeTimeout: 5,
            turnGapMilliseconds: 900
        )
        let liveEndpoint = URL(string: "wss://proxy.example.com/live")
        let service = OpenAILiveService(
            credential: .apiKey("proxy-key"),
            options: options,
            liveEndpoint: liveEndpoint
        )
        let config = OpenAIConfiguration(
            apiKey: "openai",
            live: options,
            liveCredential: .apiKey("live-only"),
            liveEndpoint: liveEndpoint
        )
        let speechService = SpeechService(openAI: config)

        #expect(service.state == .idle)
        #expect(service.transcript.isEmpty)
        #expect(service.usageSeconds == 0)
        #expect(service.contextWindowUsageRatio == nil)
        #expect(service.isInputMuted == false)
        #expect(service.assistantIsSpeaking == false)
        #expect(service.liveEndpoint == liveEndpoint)
        #expect(service.options.voice == .cedar)
        #expect(config.live.turnGapMilliseconds == 900)
        #expect(config.liveCredential == .apiKey("live-only"))
        #expect(config.liveEndpoint == liveEndpoint)
        #expect(speechService.activeConversationProvider == .openAI)
        #expect(speechService.conversationState == .idle)
        #expect(speechService.conversationTranscript.isEmpty)
        #expect(speechService.partialUserTranscriptText.isEmpty)
        #expect(speechService.partialAssistantTranscriptText.isEmpty)
        #expect(speechService.userTranscriptText.isEmpty)
        #expect(speechService.assistantTranscriptText.isEmpty)
        #expect(speechService.conversationInputLevel == 0)
        #expect(speechService.conversationOutputLevel == 0)
        #expect(speechService.isConversationInputMuted == false)
        #expect(speechService.assistantIsSpeaking == false)
        #expect(speechService.conversationUsageSeconds == 0)
        #expect(speechService.conversationContextUsageRatio == nil)
        #expect(speechService.conversationExpiresAt == nil)
        #expect(speechService.conversationRecordingData == nil)
        #expect(speechService.conversationLastError == nil)
        #expect(speechService.conversationPendingContextAppendIDs.isEmpty)
        #expect(speechService.openAILive === speechService.openAILive)
        #expect(speechService.openAILive.pendingContextAppendIDs.isEmpty)
    }

    @Test("Conversation delegation and context event surfaces are constructible")
    @MainActor
    func conversationDelegationPublicSurfacesAreConstructible() {
        let service = OpenAILiveService(apiKey: "openai")
        let delegationRequest = OpenAILiveDelegationRequest(
            id: "item_1",
            target: "responses",
            responseID: "resp_1",
            clientEventID: "spk_response_1",
            offsetMilliseconds: 0
        )
        let appended = OpenAILiveContextEvent.appended(
            kind: .thinking,
            clientEventID: "spk_thinking_1",
            startMilliseconds: 4200,
            endMilliseconds: 4200
        )
        let rejected = OpenAILiveContextEvent.rejected(
            clientEventID: "spk_thinking_1",
            code: "context_injection_incomplete",
            message: "Context injection did not complete."
        )

        #expect(OpenAILiveContextKind.allCases == [.instructions, .thinking, .commentary])
        #expect(OpenAILiveContextKind.commentary.clientEventType == "session.commentary.append")
        #expect(OpenAILiveContextKind.commentary.serverEventType == "session.commentary.appended")
        #expect(delegationRequest.responseID == "resp_1")
        #expect(delegationRequest.clientEventID == "spk_response_1")
        #expect(delegationRequest.offsetMilliseconds == 0)
        #expect(appended != rejected)
        #expect(SpeechConversationState.connecting.isLifecycleActive)
        #expect(SpeechConversationState.active(sessionID: "live_1").isLifecycleActive)
        #expect(SpeechConversationState.ending.isLifecycleActive)
        #expect(SpeechConversationState.idle.isLifecycleActive == false)
        #expect(SpeechConversationState.ended(reason: .expired, seconds: 7).isLifecycleActive == false)

        // Every delegation surface hands back a fresh, independent stream.
        let delegationRequests: AsyncStream<OpenAILiveDelegationRequest> = service.delegationRequests
        let responseEvents: AsyncStream<OpenAILiveResponseEvent> = service.responseEvents
        let contextEvents: AsyncStream<OpenAILiveContextEvent> = service.contextEvents
        _ = delegationRequests
        _ = responseEvents
        _ = contextEvents
    }
}
