import Foundation
import Testing
@testable import SpeechKit

@Suite("Mistral Provider")
struct MistralProviderTests {
    // MARK: - File transcription

    @Test("Mistral multipart request carries model, options, and the audio file")
    func mistralRequestCarriesFields() async throws {
        let client = MistralFileTranscriptionClient(apiKey: "mistral-key")
        let fileURL = mistralTemporaryAudioFileURL(named: "call.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: MistralFileTranscriptionOptions(
                modelID: .voxtralSmallTranscribe3,
                language: "fr",
                contextBias: ["Northwind", "Alder Creek Design"],
                temperature: 0.2
            )
        )
        let body = try #require(request.httpBody).mistralUTF8String

        #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 10 * 60)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mistral-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(body.contains(mistralTextPart("model", "voxtral-small-transcribe-3")))
        #expect(body.contains(mistralTextPart("language", "fr")))
        #expect(body.contains(mistralTextPart("temperature", "0.2")))
        #expect(body.contains(mistralTextPart("context_bias", "Northwind")))
        #expect(body.contains(mistralTextPart("context_bias", "Alder Creek Design")))
        #expect(body.contains("name=\"file\"; filename=\"call.wav\""))
        #expect(body.contains("Content-Type: audio/wav\r\n\r\n"))
        #expect(!body.contains("name=\"diarize\""))
        #expect(!body.contains("name=\"timestamp_granularities\""))
    }

    @Test("Mistral request defaults to Voxtral Mini Transcribe 3 with no optional fields")
    func mistralRequestDefaults() async throws {
        let client = MistralFileTranscriptionClient(apiKey: "mistral-key")
        let fileURL = mistralTemporaryAudioFileURL(named: "call.wav")

        let request = try await client.makeRequest(file: fileURL)
        let body = try #require(request.httpBody).mistralUTF8String

        #expect(body.contains(mistralTextPart("model", "voxtral-mini-transcribe-3")))
        #expect(!body.contains("name=\"language\""))
        #expect(!body.contains("name=\"temperature\""))
        #expect(!body.contains("name=\"context_bias\""))
        #expect(!body.contains("name=\"diarize\""))
    }

    @Test("Mistral diarization requests segment timestamps automatically")
    func mistralDiarizationAddsSegmentTimestamps() async throws {
        let client = MistralFileTranscriptionClient(apiKey: "mistral-key")
        let fileURL = mistralTemporaryAudioFileURL(named: "call.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: MistralFileTranscriptionOptions(diarize: true)
        )
        let body = try #require(request.httpBody).mistralUTF8String

        #expect(body.contains(mistralTextPart("diarize", "true")))
        #expect(body.components(separatedBy: "name=\"timestamp_granularities\"").count == 2)
        #expect(body.contains(mistralTextPart("timestamp_granularities", "segment")))
    }

    @Test("Mistral diarization does not duplicate an explicit segment granularity")
    func mistralDiarizationKeepsSingleSegmentGranularity() {
        let options = MistralFileTranscriptionOptions(diarize: true, timestampGranularities: [.segment])

        #expect(options.resolvedTimestampGranularities == [.segment])
        #expect(MistralFileTranscriptionOptions(timestampGranularities: [.segment]).resolvedTimestampGranularities == [.segment])
        #expect(MistralFileTranscriptionOptions().resolvedTimestampGranularities == [])
    }

    @Test("Mistral rejects invalid languages, blank context bias, and non-positive timeouts")
    func mistralRejectsInvalidFileOptions() async {
        let client = MistralFileTranscriptionClient(apiKey: "mistral-key")
        let fileURL = mistralTemporaryAudioFileURL(named: "call.wav")

        await #expect(throws: SpeechError.providerFailure(
            provider: .mistral,
            reason: .requestFailed)) {
            _ = try await client.makeRequest(file: fileURL, options: MistralFileTranscriptionOptions(language: "en-US"))
        }

        await #expect(throws: SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)) {
            _ = try await client.makeRequest(file: fileURL, options: MistralFileTranscriptionOptions(contextBias: [" "]))
        }

        await #expect(throws: SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)) {
            _ = try await client.makeRequest(file: fileURL, options: MistralFileTranscriptionOptions(timeoutInterval: 0))
        }
    }

    @Test("Mistral requires an API key before request creation")
    func mistralRequiresAPIKey() async {
        let client = MistralFileTranscriptionClient(apiKey: "")
        let fileURL = mistralTemporaryAudioFileURL(named: "call.wav")

        await #expect(throws: SpeechError.providerNotConfigured(.mistral)) {
            _ = try await client.makeRequest(file: fileURL)
        }
    }

    @Test("Mistral file transcription sends a resolved token as a bearer token")
    func mistralSendsResolvedTokenAsBearer() async throws {
        let client = MistralFileTranscriptionClient(credential: .bearer(SpeechTokenResolver { _ in "mistral-token" }), endpoint: URL(string: "https://proxy.example.com/mistral"))
        let fileURL = mistralTemporaryAudioFileURL(named: "call.wav")

        let request = try await client.makeRequest(file: fileURL)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mistral-token")
    }

    @Test("Mistral file transcription honors an endpoint override")
    func mistralFileHonorsEndpointOverride() async throws {
        let endpoint = try #require(URL(string: "https://proxy.example.com/mistral/transcriptions"))
        let client = MistralFileTranscriptionClient(apiKey: "mistral-key", endpoint: endpoint)

        let request = try await client.makeRequest(file: mistralTemporaryAudioFileURL(named: "call.wav"))

        #expect(request.url == endpoint)
    }

    @Test("Mistral file response decodes diarized segments and usage")
    func mistralFileResponseDecodesSegments() throws {
        let data = Data("""
        {
          "model": "voxtral-mini-transcribe-3",
          "text": "Thanks for calling Northwind Support. Hi Daniel.",
          "language": null,
          "segments": [
            { "type": "transcription_segment", "text": "Thanks for calling Northwind Support.", "start": 0.0, "end": 1.6, "speaker_id": "speaker_1" },
            { "type": "transcription_segment", "text": " Hi Daniel.", "start": 4.2, "end": 5.0, "speaker_id": "speaker_2" }
          ],
          "usage": {
            "prompt_audio_seconds": 34,
            "prompt_tokens": 3,
            "total_tokens": 879,
            "completion_tokens": 126,
            "prompt_tokens_details": { "cached_tokens": 1, "audio_tokens": 750 },
            "service_tier": "standard"
          },
          "finish_reason": null
        }
        """.utf8)

        let response = try JSONDecoder().decode(MistralFileTranscriptionResponse.self, from: data)

        #expect(response.model == "voxtral-mini-transcribe-3")
        #expect(response.text == "Thanks for calling Northwind Support. Hi Daniel.")
        #expect(response.language == nil)
        #expect(response.segments == [
            MistralTranscriptionSegment(text: "Thanks for calling Northwind Support.", start: 0.0, end: 1.6, speakerID: "speaker_1"),
            MistralTranscriptionSegment(text: " Hi Daniel.", start: 4.2, end: 5.0, speakerID: "speaker_2")
        ])
        #expect(response.usage?.promptAudioSeconds == 34)
        #expect(response.usage?.totalTokens == 879)
    }

    @Test("Mistral file response tolerates missing segments and usage")
    func mistralFileResponseToleratesMissingFields() throws {
        let data = Data(#"{ "text": "Hello." }"#.utf8)

        let response = try JSONDecoder().decode(MistralFileTranscriptionResponse.self, from: data)

        #expect(response.text == "Hello.")
        #expect(response.segments.isEmpty)
        #expect(response.usage == nil)
    }

    // MARK: - Facade

    @MainActor
    @Test("Mistral configuration resolves per-request options over configuration defaults")
    func mistralFacadeResolvesOptions() throws {
        let service = SpeechService(
            mistral: MistralConfiguration(
                apiKey: "mistral",
                fileTranscriptionModelID: .voxtralSmallTranscribe3,
                language: "en",
                contextBias: ["SpeechKit"],
                diarize: false,
                timeoutInterval: 30
            )
        )
        let config = try #require(service.mistral)

        let defaults = service.resolvedMistralOptions(from: nil, config: config)
        #expect(defaults == MistralFileTranscriptionOptions(
            modelID: .voxtralSmallTranscribe3,
            language: "en",
            contextBias: ["SpeechKit"],
            diarize: false,
            timeoutInterval: 30
        ))

        let overridden = service.resolvedMistralOptions(
            from: .mistral(modelID: .voxtralMiniTranscribe3, diarize: true),
            config: config
        )
        #expect(overridden.modelID == .voxtralMiniTranscribe3)
        #expect(overridden.diarize == true)
        #expect(overridden.language == "en")
        #expect(overridden.contextBias == ["SpeechKit"])
    }

    @MainActor
    @Test("routing rejects Gemini options for Mistral")
    func mistralRoutingRejectsGeminiOptions() async {
        let service = SpeechService(mistral: MistralConfiguration(apiKey: "mistral"))

        await #expect(throws: SpeechError.invalidOptionsForProvider(expected: .mistral, received: .gemini)) {
            _ = try await service.transcribeAudioFile(
                provider: .mistral,
                file: mistralTemporaryAudioFileURL(named: "call.wav"),
                options: .gemini()
            )
        }
    }

    @MainActor
    @Test("Mistral file transcription requires configuration")
    func mistralFileTranscriptionRequiresConfiguration() async {
        let service = SpeechService()

        await #expect(throws: SpeechError.providerNotConfigured(.mistral)) {
            _ = try await service.transcribeMistralAudioFile(file: mistralTemporaryAudioFileURL(named: "call.wav"))
        }
    }

    @MainActor
    @Test("startListening surfaces missing Mistral configuration")
    func startListeningWithoutMistralConfiguration() async {
        let service = SpeechService()

        await service.startListening(provider: .mistral)

        #expect(service.connectionState == .error("Mistral is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.mistral))
    }

    @MainActor
    @Test("Mistral configuration applies realtime options to the realtime service")
    func mistralConfigurationAppliesRealtimeOptions() {
        let realtimeOptions = MistralRealtimeOptions(targetStreamingDelayMilliseconds: 240, diarize: true)
        let service = SpeechService(mistral: MistralConfiguration(apiKey: "mistral", realtimeOptions: realtimeOptions))

        #expect(service.mistralRealtimeService.credentialKind == .apiKey)
        #expect(service.mistralRealtimeService.options == realtimeOptions)
        #expect(SpeechRealtimeProvider.allCases.contains(.mistral))
        #expect(SpeechFileTranscriptionProvider.allCases.contains(.mistral))
    }

    // MARK: - Realtime messages

    @Test("Mistral realtime connect request carries the model and bearer token")
    func mistralConnectRequest() throws {
        let request = try MistralRealtimeWebSocket.makeConnectRequest(
            credential: .apiKey("mistral-key"),
            options: MistralRealtimeOptions()
        )

        #expect(request.url?.absoluteString == "wss://api.mistral.ai/v1/audio/transcriptions/realtime?model=voxtral-mini-transcribe-realtime-3")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mistral-key")
    }

    @Test("Mistral realtime honors an endpoint override")
    func mistralRealtimeHonorsEndpointOverride() throws {
        let endpoint = try #require(URL(string: "wss://proxy.example.com/mistral/realtime?region=eu"))
        let request = try MistralRealtimeWebSocket.makeConnectRequest(
            credential: .bearer("mistral-token"),
            options: MistralRealtimeOptions(),
            endpoint: endpoint
        )
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })

        #expect(components.host == "proxy.example.com")
        #expect(components.path == "/mistral/realtime")
        #expect(components.queryItems == [
            URLQueryItem(name: "region", value: "eu"),
            URLQueryItem(name: "model", value: "voxtral-mini-transcribe-realtime-3")
        ])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mistral-token")
    }

    @Test("Mistral session update encodes defaults with turn detection")
    func mistralSessionUpdateEncodesDefaults() throws {
        let json = try mistralJSONObject(MistralRealtimeOptions().sessionUpdateMessage())
        let session = try #require(json["session"] as? [String: Any])
        let audioFormat = try #require(session["audio_format"] as? [String: Any])

        #expect(json["type"] as? String == "session.update")
        #expect(audioFormat["encoding"] as? String == "pcm_s16le")
        #expect(audioFormat["sample_rate"] as? Int == 16000)
        #expect(session["diarize"] as? Bool == false)
        #expect((session["turn_detection"] as? [String: Any])?.isEmpty == true)
        #expect(session["target_streaming_delay_ms"] == nil)
        #expect(session["language"] == nil)
        #expect(session["context_bias"] == nil)
        #expect(session["speaker_references"] == nil)
    }

    @Test("Mistral session update encodes every configured field")
    func mistralSessionUpdateEncodesConfiguredFields() throws {
        let options = MistralRealtimeOptions(
            sampleRate: 24000,
            targetStreamingDelayMilliseconds: 480,
            language: "en",
            contextBias: ["Northwind", "Quillara"],
            turnDetection: MistralTurnDetection(endThreshold: 0.25, minSilenceMilliseconds: 700)
        )
        let json = try mistralJSONObject(options.sessionUpdateMessage())
        let session = try #require(json["session"] as? [String: Any])
        let turnDetection = try #require(session["turn_detection"] as? [String: Any])

        #expect((session["audio_format"] as? [String: Any])?["sample_rate"] as? Int == 24000)
        #expect(session["target_streaming_delay_ms"] as? Int == 480)
        #expect(session["language"] as? String == "en")
        #expect(session["context_bias"] as? [String] == ["Northwind", "Quillara"])
        #expect(turnDetection["end_threshold"] as? Double == 0.25)
        #expect(turnDetection["min_silence_ms"] as? Int == 700)
        #expect(turnDetection["start_threshold"] == nil)
    }

    @Test("Mistral diarized session drops turn detection and sends speaker references")
    func mistralDiarizedSessionDropsTurnDetection() throws {
        let clip = Data([0x01, 0x02, 0x03])
        let options = MistralRealtimeOptions(
            diarize: true,
            speakerReferences: [MistralSpeakerReference(name: "agent", audio: clip)]
        )
        let json = try mistralJSONObject(options.sessionUpdateMessage())
        let session = try #require(json["session"] as? [String: Any])

        #expect(session["diarize"] as? Bool == true)
        #expect(session["turn_detection"] == nil)
        #expect(session["speaker_references"] as? [String: String] == ["agent": clip.base64EncodedString()])
        #expect(options.effectiveTurnDetection == nil)
    }

    @Test("Mistral audio messages encode base64 PCM and the end marker")
    func mistralAudioMessagesEncode() throws {
        let append = try mistralJSONObject(MistralInputAudioAppendMessage(audioData: Data([0x00, 0xFF])))
        let end = try mistralJSONObject(MistralInputAudioEndMessage())

        #expect(append["type"] as? String == "input_audio.append")
        #expect(append["audio"] as? String == "AP8=")
        #expect(end["type"] as? String == "input_audio.end")
    }

    @Test("Mistral realtime options validate delay, language, and speaker references")
    func mistralRealtimeOptionsValidate() throws {
        try MistralRealtimeOptions(targetStreamingDelayMilliseconds: 80).validate()
        try MistralRealtimeOptions(targetStreamingDelayMilliseconds: 1200).validate()
        try MistralRealtimeOptions(targetStreamingDelayMilliseconds: 2400).validate()

        #expect(throws: SpeechError.providerFailure(
            provider: .mistral,
            reason: .requestFailed)) {
            try MistralRealtimeOptions(targetStreamingDelayMilliseconds: 1300).validate()
        }
        #expect(throws: SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)) {
            try MistralRealtimeOptions(sampleRate: 4000).validate()
        }
        #expect(throws: SpeechError.providerFailure(
            provider: .mistral,
            reason: .requestFailed)) {
            try MistralRealtimeOptions(language: "eng").validate()
        }
        #expect(throws: SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)) {
            try MistralRealtimeOptions(speakerReferences: [MistralSpeakerReference(name: "a", audio: Data([1]))]).validate()
        }
        #expect(throws: SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)) {
            let references = (0..<9).map { MistralSpeakerReference(name: "speaker-\($0)", audio: Data([1])) }
            try MistralRealtimeOptions(diarize: true, speakerReferences: references).validate()
        }
        #expect(throws: SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)) {
            let references = [MistralSpeakerReference(name: "a", audio: Data([1])), MistralSpeakerReference(name: "a", audio: Data([2]))]
            try MistralRealtimeOptions(diarize: true, speakerReferences: references).validate()
        }
    }

    @Test("Mistral realtime events decode")
    func mistralRealtimeEventsDecode() throws {
        #expect(try mistralMessage(#"{"type":"session.created","session":{"request_id":"req-1","model":"voxtral"}}"#)
            == .sessionCreated(requestID: "req-1"))
        #expect(try mistralMessage(#"{"type":"session.updated","session":{}}"#) == .sessionUpdated)
        #expect(try mistralMessage(#"{"type":"transcription.text.delta","text":" for"}"#) == .textDelta(" for"))
        #expect(try mistralMessage(#"{"type":"transcription.segment","text":" Hi,","start":null,"end":null,"speaker_id":"speaker_2"}"#)
            == .segment(text: " Hi,", speakerID: "speaker_2"))
        #expect(try mistralMessage(#"{"type":"turn.start","time_s":0.0}"#) == .turnStart(timeSeconds: 0))
        #expect(try mistralMessage(#"{"type":"turn.eager_end","time_s":1.36}"#) == .turnEagerEnd(timeSeconds: 1.36))
        #expect(try mistralMessage(#"{"type":"turn.resume","time_s":1.44}"#) == .turnResume(timeSeconds: 1.44))
        #expect(try mistralMessage(#"{"type":"turn.end","time_s":35.12,"end_reason":"threshold"}"#)
            == .turnEnd(timeSeconds: 35.12, endReason: "threshold"))
        #expect(try mistralMessage(#"{"type":"transcription.done","text":"Hello.","segments":[],"language":null}"#)
            == .done(text: "Hello."))
        #expect(try mistralMessage(#"{"type":"error","error":{"message":"Bad delay","code":3051}}"#) == .error("Bad delay"))
        #expect(try mistralMessage(#"{"type":"input_audio.committed"}"#) == .unknown("input_audio.committed"))
    }

    // MARK: - Realtime service state machine

    @MainActor
    @Test("Mistral service connects on session.created and waits for session.updated")
    func mistralServiceConnectsOnSessionCreated() {
        let service = MistralRealtimeService(apiKey: "mistral-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionCreated(requestID: "req-1"))
        service.handleMessageForTesting(.sessionCreated(requestID: "req-2"))

        #expect(service.connectionState == .connected(sessionID: "req-1"))
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("Mistral service appends deltas as a growing partial")
    func mistralServiceAppendsDeltas() {
        let service = MistralRealtimeService(apiKey: "mistral-key")

        service.handleMessageForTesting(.turnStart(timeSeconds: 0.5))
        service.handleMessageForTesting(.textDelta("Thanks"))
        service.handleMessageForTesting(.textDelta(" for"))
        service.handleMessageForTesting(.textDelta(" calling."))

        #expect(service.partialTranscriptText == "Thanks for calling.")
        let partial = service.partialTranscriptEntry
        #expect(partial?.provider == .mistral)
        #expect(partial?.start == 0.5)
        #expect(partial?.isUtteranceFinal == false)
        #expect(service.transcriptEntries.isEmpty)
    }

    @MainActor
    @Test("Mistral service commits a turn when the next turn starts")
    func mistralServiceCommitsTurnOnNextTurnStart() {
        let service = MistralRealtimeService(apiKey: "mistral-key")

        service.handleMessageForTesting(.turnStart(timeSeconds: 0))
        service.handleMessageForTesting(.textDelta("How can I help"))
        service.handleMessageForTesting(.turnEnd(timeSeconds: 1.5, endReason: "threshold"))
        // The last words of a turn arrive after its turn.end.
        service.handleMessageForTesting(.textDelta(" you today?"))
        service.handleMessageForTesting(.turnStart(timeSeconds: 2))
        service.handleMessageForTesting(.textDelta(" Hi."))

        #expect(service.transcriptEntries.count == 1)
        let entry = service.transcriptEntries.first
        #expect(entry?.text == "How can I help you today?")
        #expect(entry?.start == 0)
        #expect(entry?.duration == 1.5)
        #expect(entry?.isUtteranceFinal == true)
        #expect(service.partialTranscriptText == "Hi.")
        #expect(service.partialTranscriptEntry?.start == 2)
    }

    @MainActor
    @Test("Mistral service commits an ended turn after the streaming delay")
    func mistralServiceCommitsEndedTurnAfterDelay() async throws {
        let service = MistralRealtimeService(
            apiKey: "mistral-key",
            options: MistralRealtimeOptions(targetStreamingDelayMilliseconds: 80)
        )

        service.handleMessageForTesting(.turnStart(timeSeconds: 0))
        service.handleMessageForTesting(.textDelta("Hello there."))
        service.handleMessageForTesting(.turnEnd(timeSeconds: 1, endReason: "threshold"))
        #expect(service.transcriptEntries.isEmpty)

        for _ in 0..<40 where service.transcriptEntries.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(service.transcriptText == "Hello there.")
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Mistral service splits diarized segments into entries on speaker change")
    func mistralServiceSplitsOnSpeakerChange() {
        let service = MistralRealtimeService(apiKey: "mistral-key", options: MistralRealtimeOptions(diarize: true))

        service.handleMessageForTesting(.segment(text: "How can I help", speakerID: "speaker_1"))
        service.handleMessageForTesting(.segment(text: " you today?", speakerID: "speaker_1"))
        service.handleMessageForTesting(.segment(text: " Hi,", speakerID: "speaker_2"))
        service.handleMessageForTesting(.segment(text: " Daniel.", speakerID: "speaker_2"))

        #expect(service.transcriptEntries.count == 1)
        #expect(service.transcriptEntries.first?.text == "How can I help you today?")
        #expect(service.transcriptEntries.first?.speaker == "speaker_1")
        #expect(service.partialTranscriptText == "Hi, Daniel.")
        #expect(service.partialTranscriptEntry?.speaker == "speaker_2")

        service.handleMessageForTesting(.done(text: "How can I help you today? Hi, Daniel."))

        #expect(service.transcriptEntries.map(\.speaker) == ["speaker_1", "speaker_2"])
        #expect(service.transcriptText == "How can I help you today? Hi, Daniel.")
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Mistral service surfaces realtime error events")
    func mistralServiceSurfacesErrors() {
        let service = MistralRealtimeService(apiKey: "mistral-key")

        service.handleMessageForTesting(.error("Diarization is not compatible with turn detection."))

        #expect(service.connectionState == .error("The realtime session failed."))
        #expect(service.lastError as? SpeechFailure == SpeechFailure(.server))
    }

    @MainActor
    @Test("Mistral service commits the pending text when stopping")
    func mistralServiceCommitsPendingTextWhenStopping() async {
        let service = MistralRealtimeService(apiKey: "mistral-key")
        service.setLifecycleStateForTesting(.listening)

        service.handleMessageForTesting(.textDelta("half a sentence"))
        await service.stopListening()

        #expect(service.connectionState == .disconnected)
        #expect(service.transcriptEntries.map(\.text) == ["half a sentence"])
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Mistral service clears committed and partial transcripts")
    func mistralServiceClearsTranscripts() {
        let service = MistralRealtimeService(apiKey: "mistral-key")

        service.handleMessageForTesting(.textDelta("Hello."))
        service.handleMessageForTesting(.done(text: "Hello."))
        service.handleMessageForTesting(.textDelta("Next"))
        service.clearTranscript()

        #expect(service.transcriptEntries.isEmpty)
        #expect(service.partialTranscriptText.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Mistral service reports a missing API key and invalid options before connecting")
    func mistralServiceRejectsBeforeConnecting() async {
        let missingKey = MistralRealtimeService()
        await missingKey.startListening()
        #expect(missingKey.connectionState == .error("Mistral is not configured"))
        #expect(missingKey.lastError as? MistralRealtimeError == .apiKeyMissing)

        let invalid = MistralRealtimeService(
            apiKey: "mistral-key",
            options: MistralRealtimeOptions(targetStreamingDelayMilliseconds: 50)
        )
        await invalid.startListening()
        #expect(invalid.lastError as? SpeechError == .providerFailure(
            provider: .mistral,
            reason: .requestFailed))
        #expect(invalid.connectionState.isLifecycleActive == false)
    }
}

private func mistralTextPart(_ name: String, _ value: String) -> String {
    "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
}

private func mistralMessage(_ json: String) throws -> MistralRealtimeMessage {
    try JSONDecoder().decode(MistralRealtimeMessage.self, from: Data(json.utf8))
}

private func mistralJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Writes a stub audio file into a fresh per-call temporary directory.
private func mistralTemporaryAudioFileURL(named fileName: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(fileName)
    try? Data("RIFF".utf8).write(to: url)
    return url
}

private extension Data {
    var mistralUTF8String: String {
        String(decoding: self, as: UTF8.self)
    }
}
