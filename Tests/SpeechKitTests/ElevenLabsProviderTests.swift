import Foundation
import Testing
@testable import SpeechKit

@Suite("ElevenLabs Scribe v3")
struct ElevenLabsProviderTests {

    // MARK: - File request building

    @Test("File request emits every option as a multipart part, repeated for lists")
    func fileRequestEmitsEveryOption() async throws {
        let client = ElevenLabsFileTranscriptionClient(apiKey: "eleven-key")
        let fileURL = temporaryWAVFile(named: "sample.wav")
        let options = ElevenLabsFileTranscriptionOptions(
            modelID: .scribeV3,
            language: "en",
            secondaryLanguages: ["es", "fr"],
            numbersFormat: .digits,
            diarize: true,
            speakerCount: 4,
            diarizationThreshold: nil,
            keyterms: ["SpeechKit", "Cognition AI"],
            tagAudioEvents: true,
            noVerbatim: true,
            entityDetection: .categories([.pii, .pci])
        )

        let request = try await client.makeRequest(file: fileURL, options: options)
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "eleven-key")
        #expect(partOccurrences("model_id", in: body) == 1)
        #expect(body.contains("\r\n\r\nscribe_v3\r\n"))
        #expect(partOccurrences("language_code", in: body) == 1)
        #expect(body.contains("\r\n\r\nen\r\n"))
        #expect(partOccurrences("secondary_language_codes", in: body) == 2)
        #expect(body.contains("\r\n\r\nes\r\n"))
        #expect(body.contains("\r\n\r\nfr\r\n"))
        #expect(partOccurrences("numbers_format", in: body) == 1)
        #expect(body.contains("\r\n\r\ndigits\r\n"))
        #expect(partOccurrences("diarize", in: body) == 1)
        #expect(partOccurrences("num_speakers", in: body) == 1)
        #expect(body.contains("\r\n\r\n4\r\n"))
        #expect(partOccurrences("keyterms", in: body) == 2)
        #expect(body.contains("\r\n\r\nSpeechKit\r\n"))
        #expect(body.contains("\r\n\r\nCognition AI\r\n"))
        #expect(partOccurrences("tag_audio_events", in: body) == 1)
        #expect(partOccurrences("no_verbatim", in: body) == 1)
        #expect(partOccurrences("entity_detection", in: body) == 2)
        #expect(body.contains("\r\n\r\npii\r\n"))
        #expect(body.contains("\r\n\r\npci\r\n"))
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }

    @Test("File request emits the diarization threshold only when set")
    func fileRequestEmitsDiarizationThreshold() async throws {
        let client = ElevenLabsFileTranscriptionClient(apiKey: "eleven-key")
        let fileURL = temporaryWAVFile(named: "sample.wav")
        let options = ElevenLabsFileTranscriptionOptions(
            diarize: true,
            diarizationThreshold: 0.35
        )

        let request = try await client.makeRequest(file: fileURL, options: options)
        let body = try #require(request.httpBody).utf8String

        #expect(partOccurrences("diarization_threshold", in: body) == 1)
        #expect(body.contains("\r\n\r\n0.35\r\n"))
        #expect(partOccurrences("num_speakers", in: body) == 0)
    }

    @Test("File request emits entity detection for every supported shape")
    func fileRequestEmitsEntityDetectionShapes() async throws {
        let client = ElevenLabsFileTranscriptionClient(apiKey: "eleven-key")
        let fileURL = temporaryWAVFile(named: "sample.wav")

        let all = try await client.makeRequest(
            file: fileURL,
            options: ElevenLabsFileTranscriptionOptions(entityDetection: .all)
        )
        let allBody = try #require(all.httpBody).utf8String
        #expect(partOccurrences("entity_detection", in: allBody) == 1)
        #expect(allBody.contains("\r\n\r\nall\r\n"))

        let types = try await client.makeRequest(
            file: fileURL,
            options: ElevenLabsFileTranscriptionOptions(entityDetection: .types(["name", "location"]))
        )
        let body = try #require(types.httpBody).utf8String
        #expect(partOccurrences("entity_detection", in: body) == 2)
        #expect(body.contains("\r\n\r\nname\r\n"))
        #expect(body.contains("\r\n\r\nlocation\r\n"))
    }

    @Test("File request omits every unset field")
    func fileRequestOmitsUnsetFields() async throws {
        let client = ElevenLabsFileTranscriptionClient(apiKey: "eleven-key")
        let fileURL = temporaryWAVFile(named: "sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: ElevenLabsFileTranscriptionOptions()
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"model_id\""))
        #expect(body.contains("\r\n\r\nscribe_v3\r\n"))
        for field in [
            "language_code", "secondary_language_codes", "numbers_format",
            "diarize", "num_speakers", "diarization_threshold", "keyterms",
            "tag_audio_events", "no_verbatim", "entity_detection",
        ] {
            #expect(partOccurrences(field, in: body) == 0, "unexpected field \(field)")
        }
    }

    // MARK: - File option validation (Decision 4)

    @Test("File options reject v3-only fields on Scribe v2")
    func fileOptionsRejectV3OnlyFieldsOnV2() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(modelID: .scribeV2, numbersFormat: .digits).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(modelID: .scribeV2, secondaryLanguages: ["es"]).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(modelID: .scribeV2Medical, numbersFormat: .words).validate()
        }
        // v2 still accepts the shared fields.
        try ElevenLabsFileTranscriptionOptions(modelID: .scribeV2, diarize: true, speakerCount: 2).validate()
    }

    @Test("File options reject a realtime model")
    func fileOptionsRejectRealtimeModel() {
        #expect {
            try ElevenLabsFileTranscriptionOptions(modelID: .scribeV3Live).validate()
        } throws: { error in
            guard case ElevenLabsError.unsupportedModel = error else { return false }
            return true
        }
    }

    @Test("File options enforce the diarization threshold contract")
    func fileOptionsEnforceDiarizationThreshold() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(diarizationThreshold: 0.3).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(diarize: true, speakerCount: 2, diarizationThreshold: 0.3).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(diarize: true, diarizationThreshold: 1.5).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(diarize: true, diarizationThreshold: -0.1).validate()
        }
        try ElevenLabsFileTranscriptionOptions(diarize: true, diarizationThreshold: 0.22).validate()
    }

    @Test("File options enforce the speaker count contract")
    func fileOptionsEnforceSpeakerCount() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(speakerCount: 2).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(diarize: true, speakerCount: 0).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(diarize: true, speakerCount: 33).validate()
        }
        try ElevenLabsFileTranscriptionOptions(diarize: true, speakerCount: 32).validate()
        try ElevenLabsFileTranscriptionOptions(diarize: true, speakerCount: 1).validate()
    }

    @Test("File options reject malformed language codes")
    func fileOptionsRejectMalformedLanguageCodes() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(language: "english").validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(language: "e1").validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(secondaryLanguages: ["en", "espanol"]).validate()
        }
        try ElevenLabsFileTranscriptionOptions(language: "en", secondaryLanguages: ["es", "fra"]).validate()
    }

    @Test("File options enforce the keyterm limits")
    func fileOptionsEnforceKeytermLimits() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(
                keyterms: Array(repeating: "term", count: ElevenLabsValidation.maximumFileKeytermCount + 1)
            ).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(
                keyterms: [String(repeating: "a", count: ElevenLabsValidation.maximumFileKeytermLength + 1)]
            ).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(keyterms: ["one two three four five six"]).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(keyterms: ["bad<term"]).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(keyterms: [""]).validate()
        }
        try ElevenLabsFileTranscriptionOptions(keyterms: ["four word keyterm here", "SpeechKit"]).validate()
    }

    @Test("File options reject a non-positive timeout")
    func fileOptionsRejectNonPositiveTimeout() {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(timeoutInterval: 0).validate()
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsFileTranscriptionOptions(timeoutInterval: -5).validate()
        }
    }

    // MARK: - File response decoding

    @Test("File response decodes speakers, audio events without timestamps, entities, and language probability")
    func fileResponseDecodesV3Fields() throws {
        let data = Data(
            """
            {
              "text": "hello (laughter) world",
              "language_code": "en",
              "language_probability": 0.98,
              "audio_duration_secs": 1.7,
              "transcription_id": "trn-123",
              "words": [
                {"text":"hello","start":0.0,"end":0.5,"type":"word","logprob":-0.02,"speaker_id":"speaker_0"},
                {"text":" ","start":0.5,"end":0.5,"type":"spacing","speaker_id":"speaker_0"},
                {"text":"(laughter)","type":"audio_event","speaker_id":"speaker_1"},
                {"text":"world","start":0.9,"end":1.4,"type":"word","speaker_id":"speaker_1"}
              ],
              "entities": [
                {"text":"world","entity_type":"name","start_char":17,"end_char":22}
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(ElevenLabsFileTranscriptionResponse.self, from: data)

        #expect(response.text == "hello (laughter) world")
        #expect(response.languageCode == "en")
        #expect(response.languageProbability == 0.98)
        #expect(response.audioDurationSeconds == 1.7)
        #expect(response.transcriptionID == "trn-123")
        let words = try #require(response.words)
        #expect(words.count == 4)
        #expect(words[0].speakerID == "speaker_0")
        #expect(words[2].type == "audio_event")
        #expect(words[2].start == nil)
        #expect(words[2].end == nil)
        #expect(words[3].speakerID == "speaker_1")
        let entities = try #require(response.entities)
        #expect(entities == [ElevenLabsEntity(text: "world", entityType: "name", startChar: 17, endChar: 22)])
    }

    @Test("Captured Scribe v3 file response fixture decodes")
    func capturedV3FileResponseDecodes() throws {
        // Shaped like a real `POST /v1/speech-to-text` response for a diarized,
        // audio-event-tagged Scribe v3 request.
        let data = Data(
            """
            {
              "language_code": "eng",
              "language_probability": 0.9740000367164612,
              "text": "Thanks for joining. Let's start with the launch numbers. (applause) Over to you.",
              "transcription_id": "9f2a4d1e-0b3c-4a5e-8f6d-1c2b3a4d5e6f",
              "audio_duration_secs": 12.432,
              "words": [
                {"text":"Thanks","type":"word","start":0.04,"end":0.32,"speaker_id":"speaker_0","logprob":-0.01},
                {"text":" ","type":"spacing","start":0.32,"end":0.32,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"for","type":"word","start":0.32,"end":0.48,"speaker_id":"speaker_0","logprob":-0.03},
                {"text":" ","type":"spacing","start":0.48,"end":0.48,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"joining.","type":"word","start":0.48,"end":0.9,"speaker_id":"speaker_0","logprob":-0.05},
                {"text":" ","type":"spacing","start":0.9,"end":1.1,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"Let's","type":"word","start":1.1,"end":1.34,"speaker_id":"speaker_0","logprob":-0.02},
                {"text":" ","type":"spacing","start":1.34,"end":1.34,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"start","type":"word","start":1.34,"end":1.62,"speaker_id":"speaker_0","logprob":-0.04},
                {"text":" ","type":"spacing","start":1.62,"end":1.62,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"with","type":"word","start":1.62,"end":1.78,"speaker_id":"speaker_0","logprob":-0.01},
                {"text":" ","type":"spacing","start":1.78,"end":1.78,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"the","type":"word","start":1.78,"end":1.9,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":" ","type":"spacing","start":1.9,"end":1.9,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"launch","type":"word","start":1.9,"end":2.2,"speaker_id":"speaker_0","logprob":-0.02},
                {"text":" ","type":"spacing","start":2.2,"end":2.2,"speaker_id":"speaker_0","logprob":-0.0},
                {"text":"numbers.","type":"word","start":2.2,"end":2.7,"speaker_id":"speaker_0","logprob":-0.06},
                {"text":" ","type":"spacing","start":2.7,"end":3.0,"speaker_id":"speaker_1","logprob":-0.0},
                {"text":"(applause)","type":"audio_event","speaker_id":"speaker_1","logprob":-0.4},
                {"text":" ","type":"spacing","start":5.4,"end":5.4,"speaker_id":"speaker_1","logprob":-0.0},
                {"text":"Over","type":"word","start":5.4,"end":5.7,"speaker_id":"speaker_1","logprob":-0.02},
                {"text":" ","type":"spacing","start":5.7,"end":5.7,"speaker_id":"speaker_1","logprob":-0.0},
                {"text":"to","type":"word","start":5.7,"end":5.85,"speaker_id":"speaker_1","logprob":-0.01},
                {"text":" ","type":"spacing","start":5.85,"end":5.85,"speaker_id":"speaker_1","logprob":-0.0},
                {"text":"you.","type":"word","start":5.85,"end":6.2,"speaker_id":"speaker_1","logprob":-0.03}
              ],
              "entities": [
                {"text":"launch numbers","entity_type":"metric","start_char":40,"end_char":54}
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(ElevenLabsFileTranscriptionResponse.self, from: data)

        #expect(response.languageCode == "eng")
        #expect(response.languageProbability == 0.9740000367164612)
        #expect(response.audioDurationSeconds == 12.432)
        #expect(response.transcriptionID == "9f2a4d1e-0b3c-4a5e-8f6d-1c2b3a4d5e6f")
        let words = try #require(response.words)
        #expect(words.count == 25)
        #expect(Set(words.compactMap(\.speakerID)) == ["speaker_0", "speaker_1"])
        #expect(words.first(where: { $0.type == "audio_event" })?.text == "(applause)")
        #expect(response.entities?.count == 1)
    }

    // MARK: - Realtime option validation (Decision 4)

    @Test("Realtime options reject v3 Live-only fields on Scribe v2 Realtime")
    func realtimeOptionsRejectV3OnlyFieldsOnV2() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(diarize: true).validate(modelID: .scribeV2Realtime)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(multilingual: true).validate(modelID: .scribeV2Realtime)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(commitStrategy: .turnPrediction).validate(modelID: .scribeV2Realtime)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(keytermLibrary: ["term"]).validate(modelID: .scribeV2Realtime)
        }
        // The shared fields stay accepted on v2.
        try ElevenLabsRealtimeOptions(
            language: "en",
            commitStrategy: .manual,
            keyterms: ["term"],
            includeTimestamps: true
        ).validate(modelID: .scribeV2Realtime)
    }

    @Test("Realtime options reject a file model")
    func realtimeOptionsRejectFileModel() {
        #expect {
            try ElevenLabsRealtimeOptions().validate(modelID: .scribeV3)
        } throws: { error in
            guard case ElevenLabsError.unsupportedModel = error else { return false }
            return true
        }
    }

    @Test("Realtime options enforce VAD ranges and keyterm limits")
    func realtimeOptionsEnforceRanges() throws {
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(vadSilenceThresholdSeconds: 0.1).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(vadSilenceThresholdSeconds: 3.5).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(vadThreshold: -0.1).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(minSpeechDurationMilliseconds: -1).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(minSilenceDurationMilliseconds: -1).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(
                keyterms: Array(repeating: "t", count: ElevenLabsValidation.maximumRealtimeKeytermCount + 1)
            ).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(
                keyterms: [String(repeating: "k", count: ElevenLabsValidation.maximumRealtimeKeytermLength + 1)]
            ).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(
                keytermLibrary: Array(repeating: "t", count: ElevenLabsValidation.maximumKeytermLibraryCount + 1)
            ).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(
                keytermLibrary: [String(repeating: "t", count: ElevenLabsValidation.maximumKeytermLibraryTermLength + 1)]
            ).validate(modelID: .scribeV3Live)
        }
        #expect(throws: invalidOptionsError) {
            try ElevenLabsRealtimeOptions(language: "not-a-code").validate(modelID: .scribeV3Live)
        }
        try ElevenLabsRealtimeOptions(
            language: "en",
            secondaryLanguages: ["es", "fra"],
            multilingual: true,
            commitStrategy: .turnPrediction,
            vadSilenceThresholdSeconds: 0.5,
            diarize: true,
            keyterms: ["SpeechKit"],
            keytermLibrary: ["Cognition"],
            includeTimestamps: true,
            includeLanguageDetection: true,
            noVerbatim: true,
            entityDetection: .all
        ).validate(modelID: .scribeV3Live)
    }

    // MARK: - Realtime connection URL

    @Test("Realtime URL resolves the automatic commit strategy by model")
    func realtimeURLResolvesCommitStrategyByModel() throws {
        let v3 = try makeConnectURL(modelID: .scribeV3Live)
        #expect(queryValue("commit_strategy", in: v3) == "turn_prediction")

        let v2 = try makeConnectURL(modelID: .scribeV2Realtime)
        #expect(queryValue("commit_strategy", in: v2) == "vad")
    }

    @Test("Realtime URL sends an explicit commit strategy as given")
    func realtimeURLSendsExplicitCommitStrategy() throws {
        let manualV3 = try makeConnectURL(
            modelID: .scribeV3Live,
            options: ElevenLabsRealtimeOptions(commitStrategy: .manual)
        )
        #expect(queryValue("commit_strategy", in: manualV3) == "manual")

        let vadV3 = try makeConnectURL(
            modelID: .scribeV3Live,
            options: ElevenLabsRealtimeOptions(commitStrategy: .vad)
        )
        #expect(queryValue("commit_strategy", in: vadV3) == "vad")

        let manualV2 = try makeConnectURL(
            modelID: .scribeV2Realtime,
            options: ElevenLabsRealtimeOptions(commitStrategy: .manual)
        )
        #expect(queryValue("commit_strategy", in: manualV2) == "manual")
    }

    @Test("Realtime URL repeats list options and sends every set field")
    func realtimeURLRepeatsListOptions() throws {
        let url = try makeConnectURL(
            modelID: .scribeV3Live,
            options: ElevenLabsRealtimeOptions(
                language: "en",
                secondaryLanguages: ["es", "fr"],
                multilingual: true,
                vadSilenceThresholdSeconds: 0.5,
                vadThreshold: 0.4,
                minSpeechDurationMilliseconds: 120,
                minSilenceDurationMilliseconds: 300,
                diarize: true,
                keyterms: ["alpha", "beta"],
                includeTimestamps: true,
                includeLanguageDetection: true,
                noVerbatim: true,
                entityDetection: .types(["name", "location"])
            )
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.filter { $0.name == "model_id" }.map(\.value) == ["scribe_v3_live"])
        #expect(items.filter { $0.name == "language_code" }.map(\.value) == ["en"])
        #expect(items.filter { $0.name == "secondary_languages" }.map(\.value) == ["es", "fr"])
        #expect(items.filter { $0.name == "multilang_mode" }.map(\.value) == ["true"])
        #expect(items.filter { $0.name == "diarize" }.map(\.value) == ["true"])
        #expect(items.filter { $0.name == "vad_silence_threshold_secs" }.map(\.value) == ["0.5"])
        #expect(items.filter { $0.name == "vad_threshold" }.map(\.value) == ["0.4"])
        #expect(items.filter { $0.name == "min_speech_duration_ms" }.map(\.value) == ["120"])
        #expect(items.filter { $0.name == "min_silence_duration_ms" }.map(\.value) == ["300"])
        #expect(items.filter { $0.name == "include_timestamps" }.map(\.value) == ["true"])
        #expect(items.filter { $0.name == "include_language_detection" }.map(\.value) == ["true"])
        #expect(items.filter { $0.name == "no_verbatim" }.map(\.value) == ["true"])
        #expect(items.filter { $0.name == "keyterms" }.map(\.value) == ["alpha", "beta"])
        #expect(items.filter { $0.name == "entity_detection" }.map(\.value) == ["name", "location"])
    }

    @Test("Realtime URL omits every unset field")
    func realtimeURLOmitsUnsetFields() throws {
        let url = try makeConnectURL(modelID: .scribeV3Live)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let names = Set(items.map(\.name))

        #expect(names == ["model_id", "commit_strategy"])
    }

    @Test("Realtime connect rejects v3 Live-only fields on Scribe v2 Realtime")
    func realtimeConnectRejectsV3OnlyFieldsOnV2() {
        #expect(throws: invalidOptionsError) {
            _ = try ElevenLabsWebSocket.makeConnectRequest(
                credential: .apiKey("eleven-key"),
                modelID: .scribeV2Realtime,
                options: ElevenLabsRealtimeOptions(diarize: true)
            )
        }
        #expect(throws: invalidOptionsError) {
            _ = try ElevenLabsWebSocket.makeConnectRequest(
                credential: .apiKey("eleven-key"),
                modelID: .scribeV2Realtime,
                options: ElevenLabsRealtimeOptions(commitStrategy: .turnPrediction)
            )
        }
    }

    // MARK: - First audio chunk

    @MainActor
    @Test("The first audio chunk carries previous_text and keyterm_library once")
    func firstAudioChunkCarriesSessionFieldsOnce() throws {
        let service = ElevenLabsService(
            apiKey: "eleven-key",
            options: ElevenLabsRealtimeOptions(
                keytermLibrary: ["Cognition", "SpeechKit"],
                previousText: "Earlier context."
            )
        )

        let firstData = try JSONEncoder().encode(service.makeInputAudioChunk(audioData: Data([1, 2, 3]), isFirstChunk: true))
        let secondData = try JSONEncoder().encode(service.makeInputAudioChunk(audioData: Data([1, 2, 3]), isFirstChunk: false))
        let first = try JSONSerialization.jsonObject(with: firstData) as? [String: Any]
        let second = try JSONSerialization.jsonObject(with: secondData) as? [String: Any]

        #expect(first?["previous_text"] as? String == "Earlier context.")
        #expect(first?["keyterm_library"] as? [String] == ["Cognition", "SpeechKit"])
        #expect(first?["commit"] as? Bool == false)
        #expect(second?["previous_text"] == nil)
        #expect(second?["keyterm_library"] == nil)
    }

    @MainActor
    @Test("The first audio chunk omits unset session fields")
    func firstAudioChunkOmitsUnsetSessionFields() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        let firstData = try JSONEncoder().encode(service.makeInputAudioChunk(audioData: Data([1]), isFirstChunk: true))
        let first = try JSONSerialization.jsonObject(with: firstData) as? [String: Any]

        #expect(first?["previous_text"] == nil)
        #expect(first?["keyterm_library"] == nil)
    }

    // MARK: - Realtime transcript state machine

    @MainActor
    @Test("A committed transcript appends an entry before its diarization arrives")
    func commitAppendsEntryBeforeDiarization() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"hello there","segment_index":3}"#))

        let entry = try #require(service.transcriptEntries.first)
        #expect(service.transcriptEntries.count == 1)
        #expect(entry.text == "hello there")
        #expect(entry.sourceID == "segment:3")
        #expect(entry.speaker == nil)
    }

    @MainActor
    @Test("A diarized transcript splits its segment into speaker-run entries")
    func diarizedTranscriptSplitsIntoSpeakerRuns() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"hello there world","segment_index":3}"#))
        let committedID = try #require(service.transcriptEntries.first?.id)

        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"diarized_transcript","segment_index":3,"text":"hello there world","words":[
              {"text":"hello","type":"word","start":0.0,"end":0.4,"speaker_id":"speaker_0"},
              {"text":" ","type":"spacing","speaker_id":"speaker_0"},
              {"text":"there","type":"word","start":0.4,"end":0.8,"speaker_id":"speaker_0"},
              {"text":" ","type":"spacing","speaker_id":"speaker_1"},
              {"text":"world","type":"word","start":0.9,"end":1.3,"speaker_id":"speaker_1"}
            ]}
            """
        ))

        #expect(service.transcriptEntries.count == 2)
        let first = service.transcriptEntries[0]
        let second = service.transcriptEntries[1]
        #expect(first.id == committedID)
        #expect(first.speaker == "speaker_0")
        #expect(first.text == "hello there")
        #expect(first.sourceID == "segment:3")
        #expect(first.words.map(\.speaker) == ["speaker_0", "speaker_0", "speaker_0"])
        #expect(first.start == 0.0)
        #expect(first.duration == 0.8)
        #expect(second.id != committedID)
        #expect(second.speaker == "speaker_1")
        #expect(second.text == "world")
        #expect(second.sourceID == "segment:3")
        #expect(second.words.map(\.speaker) == ["speaker_1", "speaker_1"])
    }

    @MainActor
    @Test("A spacing token without a speaker does not split a speaker run")
    func unlabeledSpacingStaysInSpeakerRun() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"hello there world","segment_index":0}"#))
        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"diarized_transcript","segment_index":0,"text":"hello there world","words":[
              {"text":"hello","type":"word","start":0.0,"end":0.4,"speaker_id":"speaker_0"},
              {"text":" ","type":"spacing","speaker_id":null},
              {"text":"there","type":"word","start":0.4,"end":0.8,"speaker_id":"speaker_0"},
              {"text":" ","type":"spacing"},
              {"text":"world","type":"word","start":0.9,"end":1.3,"speaker_id":"speaker_1"}
            ]}
            """
        ))

        #expect(service.transcriptEntries.map(\.text) == ["hello there", "world"])
        #expect(service.transcriptEntries.map(\.speaker) == ["speaker_0", "speaker_1"])
        #expect(service.transcriptEntries[1].start == 0.9)
    }

    @MainActor
    @Test("A diarized transcript for an unknown or out-of-order segment is dropped")
    func diarizedTranscriptForUnknownSegmentIsDropped() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        // Unknown index: no commit ever registered segment 9.
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"diarized_transcript","segment_index":9,"text":"x","words":[{"text":"x","type":"word","speaker_id":"speaker_0"}]}"#
        ))
        #expect(service.transcriptEntries.isEmpty)

        // Out of order: the diarized transcript beats its commit.
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"diarized_transcript","segment_index":5,"text":"early","words":[{"text":"early","type":"word","speaker_id":"speaker_0"}]}"#
        ))
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"committed_transcript","text":"early","segment_index":5}"#
        ))

        let entry = try #require(service.transcriptEntries.first)
        #expect(service.transcriptEntries.count == 1)
        #expect(entry.speaker == nil)
        #expect(entry.sourceID == "segment:5")

        // A second diarized message for the same segment does apply.
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"diarized_transcript","segment_index":5,"text":"early","words":[{"text":"early","type":"word","speaker_id":"speaker_0"}]}"#
        ))
        #expect(service.transcriptEntries.first?.speaker == "speaker_0")
    }

    @MainActor
    @Test("A chained speakers_merged rewrites stored entries and partial words")
    func chainedSpeakersMergedRewritesSpeakers() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"one two","segment_index":0}"#))
        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"diarized_transcript","segment_index":0,"text":"one two","words":[
              {"text":"one","type":"word","speaker_id":"speaker_0"},
              {"text":" two","type":"word","speaker_id":"speaker_1"}
            ]}
            """
        ))
        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"three","segment_index":1}"#))
        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"diarized_transcript","segment_index":1,"text":"three","words":[
              {"text":"three","type":"word","speaker_id":"speaker_0"}
            ]}
            """
        ))

        // First merge: speaker_1 folds into speaker_0.
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"speakers_merged","from_speaker_id":"speaker_1","to_speaker_id":"speaker_0"}"#
        ))
        #expect(service.transcriptEntries[0].speaker == "speaker_0")
        #expect(service.transcriptEntries[1].speaker == "speaker_0")
        #expect(service.transcriptEntries[2].speaker == "speaker_0")

        // Chained merge: speaker_0 folds into speaker_9, and the earlier
        // speaker_1 alias resolves to the final target.
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"speakers_merged","from_speaker_id":"speaker_0","to_speaker_id":"speaker_9"}"#
        ))
        #expect(service.transcriptEntries.map(\.speaker) == ["speaker_9", "speaker_9", "speaker_9"])
        #expect(service.transcriptEntries[0].words.map(\.speaker) == ["speaker_9"])

        // The live partial applies the alias map to its draft words.
        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"partial_transcript","text":"four","segment_index":2,"words":[
              {"text":"four","type":"word","speaker_id":"speaker_1"}
            ]}
            """
        ))
        let partial = try #require(service.partialTranscriptEntry)
        #expect(partial.words.map(\.speaker) == ["speaker_9"])

        // A new diarized transcript resolves merged labels as it lands.
        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"five","segment_index":2}"#))
        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"diarized_transcript","segment_index":2,"text":"five","words":[
              {"text":"five","type":"word","speaker_id":"speaker_0"}
            ]}
            """
        ))
        #expect(service.transcriptEntries.last?.speaker == "speaker_9")
    }

    @MainActor
    @Test("A diarized transcript with all-null speakers stays a single entry")
    func allNullSpeakersStaySingleEntry() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"solo","segment_index":1}"#))
        let committedID = try #require(service.transcriptEntries.first?.id)
        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"diarized_transcript","segment_index":1,"text":"solo","words":[
              {"text":"solo","type":"word","start":0.0,"end":0.4}
            ]}
            """
        ))

        #expect(service.transcriptEntries.count == 1)
        let entry = service.transcriptEntries[0]
        #expect(entry.id == committedID)
        #expect(entry.speaker == nil)
        #expect(entry.words.count == 1)
        #expect(entry.words[0].speaker == nil)
    }

    @MainActor
    @Test("Clearing mid-session drops segment tracking and merges")
    func clearMidSessionResetsDiarizationState() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"one","segment_index":0}"#))
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"speakers_merged","from_speaker_id":"speaker_1","to_speaker_id":"speaker_0"}"#
        ))
        service.clearTranscript()

        #expect(service.transcriptEntries.isEmpty)

        // The cleared segment's late diarized transcript is dropped.
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"diarized_transcript","segment_index":0,"text":"one","words":[{"text":"one","type":"word","speaker_id":"speaker_0"}]}"#
        ))
        #expect(service.transcriptEntries.isEmpty)

        // The next segment starts clean: the cleared merge no longer applies.
        service.handleMessageForTesting(try realtimeMessage(#"{"message_type":"committed_transcript","text":"two","segment_index":1}"#))
        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"diarized_transcript","segment_index":1,"text":"two","words":[{"text":"two","type":"word","speaker_id":"speaker_1"}]}"#
        ))
        #expect(service.transcriptEntries.last?.speaker == "speaker_1")
    }

    @MainActor
    @Test("Turn probability updates on partials and resets on commit")
    func turnProbabilityUpdatesAndResets() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"partial_transcript","text":"almost","segment_index":0,"turn_probability":0.7}"#
        ))
        #expect(service.turnProbability == 0.7)
        #expect(service.partialTranscriptText == "almost")

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"partial_transcript","text":"almost done","segment_index":0,"turn_probability":0.93}"#
        ))
        #expect(service.turnProbability == 0.93)
        #expect(service.partialTranscriptText == "almost done")

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"committed_transcript","text":"almost done","segment_index":0}"#
        ))
        #expect(service.turnProbability == nil)
        #expect(service.partialTranscriptText.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Partial words keep a stable entry id across updates")
    func partialEntryKeepsStableID() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"partial_transcript","text":"a","segment_index":0,"words":[{"text":"a","type":"word","speaker_id":"speaker_0"}]}"#
        ))
        let firstID = try #require(service.partialTranscriptEntry?.id)

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"partial_transcript","text":"a b","segment_index":0,"words":[{"text":"a","type":"word","speaker_id":"speaker_0"},{"text":" b","type":"word"}]}"#
        ))

        #expect(service.partialTranscriptEntry?.id == firstID)
        #expect(service.partialTranscriptEntry?.isFinal == false)
        #expect(service.partialTranscriptEntry?.sourceID == "segment:0")
        #expect(service.partialTranscriptEntry?.words.map(\.speaker) == ["speaker_0", nil])
    }

    @MainActor
    @Test("Committed transcript entities are collected in order")
    func committedEntitiesAreCollected() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"committed_transcript_entities","segment_index":0,"entities":[
              {"text":"Jane","entity_type":"name","start_char":0,"end_char":4},
              {"text":"Paris","entity_type":"location","start_char":10,"end_char":15}
            ]}
            """
        ))

        #expect(service.entityDetections.map(\.text) == ["Jane", "Paris"])
        #expect(service.entityDetections.map(\.entityType) == ["name", "location"])
    }

    @MainActor
    @Test("Every server error type ends the session without leaking vendor text")
    func serverErrorsEndSessionSafely() throws {
        for type in ElevenLabsMessage.serverErrorTypes {
            let service = ElevenLabsService(apiKey: "eleven-key")
            service.setLifecycleStateForTesting(.listening)

            service.handleMessageForTesting(try realtimeMessage(
                #"{"message_type":"\#(type)","error":"vendor detail abc123"}"#
            ))

            guard let serverError = service.lastError as? ElevenLabsError,
                  case .serverError(let reportedType) = serverError else {
                Issue.record("expected serverError for \(type), got \(String(describing: service.lastError))")
                continue
            }
            #expect(reportedType == type)
            #expect(service.lastError?.localizedDescription.contains("vendor detail") == false)
            if case .error = service.connectionState {} else {
                Issue.record("expected error state for \(type), got \(service.connectionState)")
            }
        }
    }

    @MainActor
    @Test("Warnings are logged, not surfaced")
    func warningsAreNotSurfaced() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")
        service.setLifecycleStateForTesting(.listening)

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"warning","message":"slow consumer"}"#
        ))

        #expect(service.lastError == nil)
        #expect(service.connectionState == .listening)
    }

    @MainActor
    @Test("Unknown message types are ignored")
    func unknownMessagesAreIgnored() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(
            #"{"message_type":"future_message","data":"anything"}"#
        ))

        #expect(service.lastError == nil)
        #expect(service.transcriptEntries.isEmpty)
    }

    @Test("Session started tolerates a renamed or minimal session config")
    func sessionStartedToleratesMinimalConfig() throws {
        let message = try realtimeMessage(
            #"{"message_type":"session_started","session_id":"s-1","config":{"model_id":"scribe_v3_live","commit_strategy":"turn_prediction"}}"#
        )
        guard case .sessionStarted(let started) = message else {
            Issue.record("expected session_started")
            return
        }
        #expect(started.sessionID == "s-1")
        #expect(started.config.modelID == "scribe_v3_live")
        #expect(started.config.commitStrategy == "turn_prediction")
        #expect(started.config.sampleRate == nil)
    }

    @MainActor
    @Test("Committed transcript with timestamps carries words and the segment index")
    func committedTranscriptWithTimestampsApplies() throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        service.handleMessageForTesting(try realtimeMessage(
            """
            {"message_type":"committed_transcript_with_timestamps","text":"timed words","language_code":"en","segment_index":2,"words":[
              {"text":"timed","type":"word","start":0.0,"end":0.4},
              {"text":" words","type":"word","start":0.4,"end":0.9}
            ]}
            """
        ))

        let entry = try #require(service.transcriptEntries.first)
        #expect(entry.text == "timed words")
        #expect(entry.sourceID == "segment:2")
        #expect(entry.words.count == 2)
        #expect(entry.start == 0.0)
        #expect(entry.duration == 0.9)
    }

    @MainActor
    @Test("Manual commit requires the manual strategy and an active session")
    func manualCommitRequiresManualStrategy() async throws {
        let service = ElevenLabsService(apiKey: "eleven-key")

        await #expect {
            try await service.commitRealtimeSegment()
        } throws: { error in
            guard case ElevenLabsError.disconnected = error else { return false }
            return true
        }

        service.setLifecycleStateForTesting(.listening)
        await #expect(throws: invalidOptionsError) {
            try await service.commitRealtimeSegment()
        }

        let manualService = ElevenLabsService(
            apiKey: "eleven-key",
            options: ElevenLabsRealtimeOptions(commitStrategy: .manual)
        )
        manualService.setLifecycleStateForTesting(.listening)
        // Reaches the socket layer, which fails because no session is open.
        await #expect {
            try await manualService.commitRealtimeSegment()
        } throws: { error in
            guard case ElevenLabsError.disconnected = error else { return false }
            return true
        }
    }

    // MARK: - Configuration resolution

    @MainActor
    @Test("Resolved file options merge per-request overrides over the configuration")
    func resolvedFileOptionsMergeOverrides() {
        var fileOptions = ElevenLabsFileTranscriptionOptions(diarize: true, keyterms: ["default"])
        fileOptions.timeoutInterval = 42
        let service = SpeechService(
            elevenLabs: ElevenLabsConfiguration(
                apiKey: "eleven-key",
                fileTranscriptionModelID: .scribeV2,
                fileOptions: fileOptions
            )
        )
        let config = service.elevenLabs!

        // No request options: configuration wins, and the model field stays
        // the configuration's single source of truth.
        let defaults = service.resolvedElevenLabsOptions(from: nil, config: config)
        #expect(defaults.modelID == .scribeV2)
        #expect(defaults.diarize)
        #expect(defaults.keyterms == ["default"])
        #expect(defaults.timeoutInterval == 42)

        let resolved = service.resolvedElevenLabsOptions(
            from: .elevenLabs(modelID: .scribeV3, numbersFormat: .digits, diarize: false),
            config: config
        )
        #expect(resolved.modelID == .scribeV3)
        #expect(resolved.diarize == false)
        #expect(resolved.numbersFormat == .digits)
        // Untouched fields keep the configured default.
        #expect(resolved.keyterms == ["default"])
        #expect(resolved.timeoutInterval == 42)
    }
}

// MARK: - Helpers

private var invalidOptionsError: SpeechError {
    .providerFailure(provider: .elevenLabs, reason: .invalidOptions)
}

private func makeConnectURL(
    modelID: ElevenLabsModelID,
    options: ElevenLabsRealtimeOptions = ElevenLabsRealtimeOptions()
) throws -> URL {
    let request = try ElevenLabsWebSocket.makeConnectRequest(
        credential: .apiKey("eleven-key"),
        modelID: modelID,
        options: options
    )
    return try #require(request.url)
}

private func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == name })?.value
}

private func realtimeMessage(_ json: String) throws -> ElevenLabsMessage {
    try JSONDecoder().decode(ElevenLabsMessage.self, from: Data(json.utf8))
}

private func partOccurrences(_ name: String, in body: String) -> Int {
    body.components(separatedBy: "name=\"\(name)\"").count - 1
}

private func temporaryWAVFile(named fileName: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(fileName)
    try? elevenLabsTestWAVData().write(to: url)
    return url
}

/// A valid 16 kHz, 16-bit, mono PCM WAV holding 0.1 seconds of silence.
private func elevenLabsTestWAVData() -> Data {
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

private extension Data {
    var utf8String: String {
        String(decoding: self, as: UTF8.self)
    }
}
