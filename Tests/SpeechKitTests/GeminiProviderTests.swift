import Foundation
import Testing
@testable import SpeechKit

@Suite("Gemini File Transcription")
struct GeminiFileTranscriptionTests {
    @Test("Gemini inline request encodes the model, audio, and transcription config")
    func geminiInlineRequestEncodesModelAudioAndConfig() async throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: GeminiFileTranscriptionOptions(
                languageCodes: ["en-US"],
                mode: .verbatim,
                diarize: true,
                timestampGranularities: [.word]
            )
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try geminiJSONObject(from: #require(request.httpBody))
        #expect(body["model"] as? String == "gemini-3.5-transcribe")
        #expect(body["background"] as? Bool == false)

        let input = try #require((body["input"] as? [[String: Any]])?.first)
        #expect(input["type"] as? String == "audio")
        #expect(input["mime_type"] as? String == "audio/wav")
        #expect(input["uri"] == nil)
        let expectedAudio = try Data(contentsOf: fileURL).base64EncodedString()
        #expect(input["data"] as? String == expectedAudio)

        let generationConfig = try #require(body["generation_config"] as? [String: Any])
        let transcriptionConfig = try #require(generationConfig["transcription_config"] as? [String: Any])
        #expect(transcriptionConfig["language_codes"] as? [String] == ["en-US"])
        #expect(transcriptionConfig["custom_vocabulary"] == nil)

        let mode = try #require(transcriptionConfig["mode"] as? [String: Any])
        #expect(mode["type"] as? String == "verbatim")
        #expect(mode["diarization_mode"] as? String == "speaker")
        #expect(mode["timestamp_granularities"] as? [String] == ["word"])
    }

    @Test("Gemini request encodes custom vocabulary and omits unused mode fields")
    func geminiRequestEncodesCustomVocabulary() async throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-vocabulary.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: GeminiFileTranscriptionOptions(customVocabulary: ["SpeechKit"], mode: .smart)
        )

        let body = try geminiJSONObject(from: #require(request.httpBody))
        let generationConfig = try #require(body["generation_config"] as? [String: Any])
        let transcriptionConfig = try #require(generationConfig["transcription_config"] as? [String: Any])
        #expect(transcriptionConfig["custom_vocabulary"] as? [String] == ["SpeechKit"])
        #expect(transcriptionConfig["language_codes"] == nil)

        let mode = try #require(transcriptionConfig["mode"] as? [String: Any])
        #expect(mode["type"] as? String == "smart")
        #expect(mode["diarization_mode"] == nil)
        #expect(mode["timestamp_granularities"] == nil)
    }

    @Test("Gemini background processing sets the background flag")
    func geminiBackgroundProcessingSetsBackgroundFlag() async throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-background.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: GeminiFileTranscriptionOptions(processingMode: .background(pollInterval: 5))
        )

        let body = try geminiJSONObject(from: #require(request.httpBody))
        #expect(body["background"] as? Bool == true)
    }

    @Test("Gemini rejects custom vocabulary combined with diarization")
    func geminiRejectsCustomVocabularyWithDiarization() async {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-invalid-vocabulary.wav")

        await #expect(
            throws: SpeechError.providerFailure(
                provider: .gemini,
                reason: "customVocabulary cannot be combined with diarization or word timestamps."
            )
        ) {
            _ = try await client.makeRequest(
                file: fileURL,
                options: GeminiFileTranscriptionOptions(customVocabulary: ["SpeechKit"], diarize: true)
            )
        }
    }

    @Test("Gemini rejects smart mode combined with word timestamps")
    func geminiRejectsSmartModeWithWordTimestamps() async {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-invalid-smart.wav")

        await #expect(
            throws: SpeechError.providerFailure(
                provider: .gemini,
                reason: "smart mode cannot be combined with diarization or word timestamps."
            )
        ) {
            _ = try await client.makeRequest(
                file: fileURL,
                options: GeminiFileTranscriptionOptions(mode: .smart, timestampGranularities: [.word])
            )
        }
    }

    @Test("Gemini rejects more than 1000 custom vocabulary terms")
    func geminiRejectsOversizedCustomVocabulary() async {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-vocabulary-limit.wav")
        let terms = (0..<1001).map { "term-\($0)" }

        await #expect(
            throws: SpeechError.providerFailure(
                provider: .gemini,
                reason: "customVocabulary cannot contain more than 1000 terms."
            )
        ) {
            _ = try await client.makeRequest(
                file: fileURL,
                options: GeminiFileTranscriptionOptions(customVocabulary: terms)
            )
        }
    }

    @Test("Gemini rejects unsupported file extensions before request creation")
    func geminiRejectsUnsupportedFileExtension() async {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-sample.mp4")

        await #expect(throws: SpeechError.providerFailure(provider: .gemini, reason: "Unsupported file extension: mp4.")) {
            _ = try await client.makeRequest(file: fileURL)
        }
    }

    @Test("Gemini automatic upload strategy switches to the Files API above the inline threshold")
    func geminiAutomaticUploadStrategySwitchesAboveThreshold() throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let smallFile = geminiTemporaryAudioFileURL(named: "gemini-small.wav")
        let largeFile = try geminiTemporarySparseFileURL(named: "gemini-large.wav", size: 8192)
        // The stub WAV is ~3.2 KB, so the threshold sits between the two files.
        let options = GeminiFileTranscriptionOptions(inlineUploadThresholdBytes: 4096)

        #expect(try client.resolvedUploadStrategy(for: smallFile, options: options) == .inline)
        #expect(try client.resolvedUploadStrategy(for: largeFile, options: options) == .filesAPI)
    }

    @Test("Gemini explicit upload strategies ignore the inline threshold")
    func geminiExplicitUploadStrategiesIgnoreThreshold() throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let largeFile = try geminiTemporarySparseFileURL(named: "gemini-explicit.wav", size: 4096)

        let inlineOptions = GeminiFileTranscriptionOptions(
            uploadStrategy: .inline,
            inlineUploadThresholdBytes: 2048
        )
        let filesOptions = GeminiFileTranscriptionOptions(
            uploadStrategy: .filesAPI,
            inlineUploadThresholdBytes: 10 * 1024 * 1024
        )

        #expect(try client.resolvedUploadStrategy(for: largeFile, options: inlineOptions) == .inline)
        #expect(try client.resolvedUploadStrategy(for: largeFile, options: filesOptions) == .filesAPI)
    }

    @Test("Gemini Files API request references the uploaded URI instead of inline data")
    func geminiFilesAPIRequestReferencesURI() throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")

        let request = try client.makeRequest(
            fileURI: "https://generativelanguage.googleapis.com/v1beta/files/abc123",
            mimeType: "audio/flac"
        )

        let body = try geminiJSONObject(from: #require(request.httpBody))
        let input = try #require((body["input"] as? [[String: Any]])?.first)
        #expect(input["uri"] as? String == "https://generativelanguage.googleapis.com/v1beta/files/abc123")
        #expect(input["mime_type"] as? String == "audio/flac")
        #expect(input["data"] == nil)
    }

    @Test("Gemini poll request targets the interaction resource")
    func geminiPollRequestTargetsInteractionResource() throws {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")

        let prefixed = try client.makePollRequest(interactionID: "interactions/abc123")
        let bare = try client.makePollRequest(interactionID: "abc123")

        #expect(prefixed.httpMethod == "GET")
        #expect(prefixed.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
        #expect(prefixed.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions/abc123")
        #expect(bare.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions/abc123")
    }

    @Test("Gemini poll request rejects an empty interaction identifier")
    func geminiPollRequestRejectsEmptyIdentifier() {
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key")

        #expect(
            throws: SpeechError.providerFailure(
                provider: .gemini,
                reason: "The Gemini response did not include an interaction identifier."
            )
        ) {
            _ = try client.makePollRequest(interactionID: "  ")
        }
    }

    @Test("Gemini response decodes output text and word annotations")
    func geminiResponseDecodesOutputTextAndWordAnnotations() throws {
        let data = Data(
            """
            {
              "id": "interactions/abc123xyz",
              "status": "completed",
              "output_text": "Hello world",
              "detected_languages": ["en-US"],
              "steps": [{
                "type": "model_output",
                "content": [{
                  "type": "text",
                  "text": "Hello world",
                  "annotations": [
                    {
                      "type": "word_info", "text": "Hello", "speaker": "spk_1",
                      "start_offset": "0.100s", "end_offset": "0.450s",
                      "start_index": 0, "end_index": 5
                    },
                    { "type": "other", "text": "ignored" }
                  ]
                }]
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(GeminiFileTranscriptionResponse.self, from: data)

        #expect(response.id == "interactions/abc123xyz")
        #expect(response.status == "completed")
        #expect(response.text == "Hello world")
        #expect(response.detectedLanguages == ["en-US"])
        #expect(response.words.count == 1)
        #expect(response.words.first?.text == "Hello")
        #expect(response.words.first?.speaker == "spk_1")
        #expect(response.words.first?.start == 0.1)
        #expect(response.words.first?.end == 0.45)
    }

    @Test("Gemini response falls back to step text when output text is missing")
    func geminiResponseFallsBackToStepText() throws {
        let data = Data(
            """
            {"id":"interactions/abc","status":"completed","steps":[{"content":[{"text":"Hello"},{"text":"world"}]}]}
            """.utf8
        )

        let response = try JSONDecoder().decode(GeminiFileTranscriptionResponse.self, from: data)

        #expect(response.text == "Hello world")
        #expect(response.words.isEmpty)
    }
}

@Suite("Gemini Files API Upload")
struct GeminiFilesClientTests {
    @Test("Gemini resumable upload start request carries the resumable headers")
    func geminiResumableUploadStartRequestCarriesHeaders() throws {
        let client = GeminiFilesClient(apiKey: "gemini-key")

        let request = try client.makeStartRequest(
            file: URL(fileURLWithPath: "/tmp/gemini-upload.flac"),
            mimeType: "audio/flac",
            byteCount: 4096,
            timeoutInterval: 60
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/upload/v1beta/files")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Protocol") == "resumable")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length") == "4096")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type") == "audio/flac")

        let body = try geminiJSONObject(from: #require(request.httpBody))
        let file = try #require(body["file"] as? [String: Any])
        #expect(file["display_name"] as? String == "gemini-upload.flac")
    }

    @Test("Gemini resumable upload finalize request sends the offset and command")
    func geminiResumableUploadFinalizeRequestSendsOffsetAndCommand() throws {
        let client = GeminiFilesClient(apiKey: "gemini-key")
        let sessionURL = try #require(URL(string: "https://upload.example/session"))

        let request = client.makeUploadRequest(sessionURL: sessionURL, byteCount: 4096, timeoutInterval: 60)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Offset") == "0")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "upload, finalize")
    }

    @Test("Gemini file state request targets the file resource")
    func geminiFileStateRequestTargetsFileResource() throws {
        let client = GeminiFilesClient(apiKey: "gemini-key")

        let request = try client.makeStateRequest(fileName: "files/abc123", timeoutInterval: 60)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/files/abc123")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
    }

    @Test("Gemini file resources decode wrapped and bare payloads")
    func geminiFileResourcesDecodeWrappedAndBarePayloads() throws {
        let client = GeminiFilesClient(apiKey: "gemini-key")

        let wrapped = try client.decodeFileResource(
            from: Data(
                """
                {"file":{"name":"files/abc","uri":"https://files.example/abc","mimeType":"audio/wav","state":"PROCESSING"}}
                """.utf8
            )
        )
        let bare = try client.decodeFileResource(
            from: Data(
                """
                {"name":"files/abc","uri":"https://files.example/abc","mimeType":"audio/wav","state":"ACTIVE"}
                """.utf8
            )
        )

        #expect(wrapped.name == "files/abc")
        #expect(wrapped.state == "PROCESSING")
        #expect(bare.uri == "https://files.example/abc")
        #expect(bare.state == "ACTIVE")
    }
}

@Suite("Gemini Interaction Responses", .serialized)
struct GeminiInteractionResponseTests {
    @Test("Gemini maps a failed interaction status to a provider failure")
    func geminiMapsFailedStatusToProviderFailure() async throws {
        GeminiStubURLProtocol.reset()
        GeminiStubURLProtocol.enqueue(
            statusCode: 200,
            body: Data(#"{"id":"interactions/abc123","status":"failed"}"#.utf8)
        )

        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key", urlSession: geminiStubbedURLSession())
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-failed.wav")

        await #expect(
            throws: SpeechError.providerFailure(
                provider: .gemini,
                reason: "Interaction interactions/abc123 finished with status failed."
            )
        ) {
            _ = try await client.transcribeAudioFileDetailed(file: fileURL)
        }

        GeminiStubURLProtocol.reset()
    }

    @Test("Gemini surfaces API error messages as an upload failure")
    func geminiSurfacesAPIErrorMessages() async throws {
        GeminiStubURLProtocol.reset()
        GeminiStubURLProtocol.enqueue(
            statusCode: 400,
            body: Data(#"{"error":{"code":"INVALID_ARGUMENT","message":"Unsupported audio"}}"#.utf8)
        )

        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key", urlSession: geminiStubbedURLSession())
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-bad-request.wav")

        await #expect(throws: SpeechError.uploadFailed(provider: .gemini, reason: "Unsupported audio")) {
            _ = try await client.transcribeAudioFileDetailed(file: fileURL)
        }

        GeminiStubURLProtocol.reset()
    }

    @Test("Gemini background processing polls the interaction until it completes")
    func geminiBackgroundProcessingPollsUntilCompletion() async throws {
        GeminiStubURLProtocol.reset()
        GeminiStubURLProtocol.enqueue(
            statusCode: 200,
            body: Data(#"{"id":"interactions/abc123","status":"in_progress"}"#.utf8)
        )
        GeminiStubURLProtocol.enqueue(
            statusCode: 200,
            body: Data(#"{"id":"interactions/abc123","status":"completed","output_text":"Hello world"}"#.utf8)
        )

        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key", urlSession: geminiStubbedURLSession())
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-polling.wav")

        let response = try await client.transcribeAudioFileDetailed(
            file: fileURL,
            options: GeminiFileTranscriptionOptions(processingMode: .background(pollInterval: 0.01))
        )

        #expect(response.text == "Hello world")
        #expect(response.status == "completed")

        let requests = GeminiStubURLProtocol.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.last?.httpMethod == "GET")
        #expect(requests.last?.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions/abc123")

        GeminiStubURLProtocol.reset()
    }

    @Test("Gemini background processing gives up when the timeout elapses")
    func geminiBackgroundProcessingGivesUpAfterTimeout() async throws {
        GeminiStubURLProtocol.reset()
        for _ in 0..<8 {
            GeminiStubURLProtocol.enqueue(
                statusCode: 200,
                body: Data(#"{"id":"interactions/abc123","status":"in_progress"}"#.utf8)
            )
        }

        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key", urlSession: geminiStubbedURLSession())
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-timeout.wav")

        await #expect(
            throws: SpeechError.providerFailure(
                provider: .gemini,
                reason: "Interaction interactions/abc123 did not finish within 1 seconds."
            )
        ) {
            _ = try await client.transcribeAudioFileDetailed(
                file: fileURL,
                options: GeminiFileTranscriptionOptions(
                    processingMode: .background(pollInterval: 0.6),
                    timeoutInterval: 1
                )
            )
        }

        GeminiStubURLProtocol.reset()
    }

    @Test("Cancelling a background transcription rethrows the cancellation")
    func cancellingBackgroundTranscriptionRethrowsCancellation() async throws {
        GeminiStubURLProtocol.reset()
        GeminiStubURLProtocol.enqueue(
            statusCode: 200,
            body: Data(#"{"id":"interactions/abc123","status":"in_progress"}"#.utf8)
        )

        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key", urlSession: geminiStubbedURLSession())
        let fileURL = geminiTemporaryAudioFileURL(named: "gemini-cancelled.wav")

        let task = Task {
            try await client.transcribeAudioFileDetailed(
                file: fileURL,
                options: GeminiFileTranscriptionOptions(
                    processingMode: .background(pollInterval: 30),
                    timeoutInterval: 600
                )
            )
        }

        // Let the first request land so the task is parked in the poll sleep.
        let deadline = Date().addingTimeInterval(5)
        while GeminiStubURLProtocol.recordedRequests().isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        GeminiStubURLProtocol.reset()
    }
}

@Suite("Gemini Realtime Service")
@MainActor
struct GeminiRealtimeServiceTests {
    @Test("Setup completion starts a listening session")
    func setupCompletionStartsListeningSession() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)

        #expect(service.connectionState == .listening)
        #expect(service.lastError == nil)
    }

    @Test("Interim transcriptions update the partial entry")
    func interimTranscriptionsUpdatePartialEntry() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.interimTranscription("hello th"))
        await service.handleMessageForTesting(.interimTranscription("hello there"))

        #expect(service.partialTranscriptText == "hello there")
        #expect(service.partialTranscriptEntry?.provider == .gemini)
        #expect(service.partialTranscriptEntry?.isFinal == false)
        #expect(service.partialTranscriptEntry?.isUtteranceFinal == false)
        #expect(service.transcriptEntries.isEmpty)
    }

    @Test("Final transcriptions commit an utterance and clear the partial entry")
    func finalTranscriptionsCommitUtterance() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.interimTranscription("hello there"))
        await service.handleMessageForTesting(.finalTranscription("Hello there."))

        #expect(service.partialTranscriptText.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
        #expect(service.transcriptEntries.count == 1)
        #expect(service.transcriptEntries.first?.provider == .gemini)
        #expect(service.transcriptEntries.first?.text == "Hello there.")
        #expect(service.transcriptEntries.first?.isFinal == true)
        #expect(service.transcriptEntries.first?.isUtteranceFinal == true)
        #expect(service.transcriptText == "Hello there.")
    }

    @Test("Repeated final transcriptions are separate utterances")
    func repeatedFinalTranscriptionsAreSeparateUtterances() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.finalTranscription("Hello there."))
        await service.handleMessageForTesting(.finalTranscription("Hello there."))
        await service.handleMessageForTesting(.finalTranscription(""))

        #expect(service.transcriptEntries.count == 2)
        #expect(service.transcriptEntries.map(\.text) == ["Hello there.", "Hello there."])
        #expect(service.transcriptEntries.map(\.sourceID) == ["utterance-1", "utterance-2"])
        #expect(service.transcriptText == "Hello there. Hello there.")
    }

    @Test("Repeating a final for the utterance already committed while stopping is suppressed")
    func lateFinalForCommittedUtteranceIsDeduplicated() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.interimTranscription("yes"))
        #expect(service.partialTranscriptEntry?.sourceID == "utterance-1")

        // Promotes the partial entry to a final one, as the stop path does.
        await service.stopListening()
        #expect(service.transcriptEntries.count == 1)

        // Gemini's final transcription for that same utterance arrives late.
        await service.handleMessageForTesting(.finalTranscription("yes"))

        #expect(service.transcriptEntries.count == 1)
        #expect(service.transcriptEntries.first?.sourceID == "utterance-1")
        #expect(service.transcriptEntries.first?.isFinal == true)
    }

    @Test("A new interim after a final starts the next utterance")
    func newInterimAfterFinalStartsNextUtterance() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.interimTranscription("ye"))
        await service.handleMessageForTesting(.finalTranscription("yes"))
        await service.handleMessageForTesting(.interimTranscription("ye"))
        await service.handleMessageForTesting(.finalTranscription("yes"))

        #expect(service.transcriptEntries.count == 2)
        #expect(service.transcriptEntries.map(\.sourceID) == ["utterance-1", "utterance-2"])
    }

    @Test("A duplicate setup acknowledgement does not re-run the start branch")
    func duplicateSetupCompleteDoesNotRestartCapture() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.setupComplete)

        #expect(service.setupCompleteRunCount == 1)
        #expect(service.connectionState == .listening)
        #expect(service.lastError == nil)
    }

    @Test("Manual activity detection opens an activity bracket at setup and closes it on stop")
    func manualActivityDetectionBracketsTheSession() async {
        let service = GeminiRealtimeService(
            apiKey: "gemini-key",
            options: GeminiRealtimeOptions(automaticActivityDetection: false)
        )

        await service.handleMessageForTesting(.setupComplete)

        #expect(service.connectionState == .listening)
        #expect(service.isManualActivityActive)

        await service.stopListening()

        #expect(service.isManualActivityActive == false)
        #expect(service.connectionState == .disconnected)
    }

    @Test("Automatic activity detection leaves the manual activity bracket closed")
    func automaticActivityDetectionLeavesManualBracketClosed() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)

        #expect(service.isManualActivityActive == false)
    }

    @Test("Turn completion and usage metadata do not change transcript state")
    func turnCompletionAndUsageMetadataAreIgnored() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.interimTranscription("partial"))
        await service.handleMessageForTesting(.turnComplete)
        await service.handleMessageForTesting(.usageMetadata)
        await service.handleMessageForTesting(.unknown)

        #expect(service.connectionState == .listening)
        #expect(service.partialTranscriptText == "partial")
        #expect(service.transcriptEntries.isEmpty)
    }

    @Test("Session resumption updates store the handle")
    func sessionResumptionUpdatesStoreHandle() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.sessionResumptionUpdate(handle: "handle-1", resumable: true))

        #expect(service.sessionResumptionHandle == "handle-1")
        #expect(service.connectionState == .listening)
    }

    @Test("Realtime errors surface the provider message")
    func realtimeErrorsSurfaceProviderMessage() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.error("Bad audio"))

        #expect(service.connectionState == .error("Bad audio"))
        #expect(service.lastError as? GeminiRealtimeError == .connectionFailed("Bad audio"))
    }

    @Test("A go away message commits the partial transcript and stops the session")
    func goAwayCommitsPartialAndStopsSession() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.interimTranscription("hello there"))
        await service.handleMessageForTesting(.goAway(timeLeft: "10s"))

        #expect(service.lastError as? GeminiRealtimeError == .sessionEnding("10s remaining"))
        #expect(service.partialTranscriptEntry == nil)
        #expect(service.transcriptEntries.count == 1)
        #expect(service.transcriptEntries.first?.text == "hello there")
        #expect(service.transcriptEntries.first?.isFinal == true)

        await geminiWaitForDisconnect(service)
        #expect(service.connectionState == .disconnected)
    }

    @Test("Clearing the transcript allows the same text to be committed again")
    func clearingTranscriptResetsDeduplication() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.handleMessageForTesting(.setupComplete)
        await service.handleMessageForTesting(.finalTranscription("Hello there."))
        service.clearTranscript()
        await service.handleMessageForTesting(.finalTranscription("Hello there."))

        #expect(service.transcriptEntries.count == 1)
        #expect(service.partialTranscriptText.isEmpty)
    }

    @Test("Starting without an API key reports a configuration error")
    func startingWithoutAPIKeyReportsConfigurationError() async {
        let service = GeminiRealtimeService()

        await service.startListening()

        #expect(service.connectionState == .error("Gemini is not configured"))
        #expect(service.lastError as? GeminiRealtimeError == .apiKeyMissing)
    }

    @Test("Starting with invalid options reports the validation error")
    func startingWithInvalidOptionsReportsValidationError() async {
        let options = GeminiRealtimeOptions(customVocabulary: (0..<1001).map { "term-\($0)" })
        let service = GeminiRealtimeService(apiKey: "gemini-key", options: options)

        await service.startListening()

        #expect(
            service.lastError as? SpeechError == .providerFailure(
                provider: .gemini,
                reason: "customVocabulary cannot contain more than 1000 terms."
            )
        )
        #expect(service.connectionState != .listening)
    }

    @Test("Stopping an idle service disconnects without side effects")
    func stoppingIdleServiceDisconnects() async {
        let service = GeminiRealtimeService(apiKey: "gemini-key")

        await service.stopListening()

        #expect(service.connectionState == .disconnected)
        #expect(service.transcriptEntries.isEmpty)
    }
}

@Suite("Speech Realtime Error Redaction")
struct SpeechRealtimeErrorRedactionTests {
    @Test("URL errors lose the failing URL that carries the API key")
    func urlErrorsLoseTheFailingURL() throws {
        let failingURLString = "wss://generativelanguage.googleapis.com/ws/BidiGenerateContent?key=SECRET"
        let failingURL = try #require(URL(string: failingURLString))
        let urlError = URLError(
            .badServerResponse,
            userInfo: [
                NSURLErrorFailingURLStringErrorKey: failingURLString,
                NSURLErrorFailingURLErrorKey: failingURL
            ]
        )

        #expect("\((urlError as NSError).userInfo)".contains("SECRET"))

        let redacted = SpeechRealtimeErrorRedaction.redacted(urlError)
        let redactedNSError = redacted as NSError

        #expect(!redacted.localizedDescription.contains("SECRET"))
        #expect(!"\(redacted)".contains("SECRET"))
        #expect(!"\(redactedNSError.userInfo)".contains("SECRET"))
        #expect(redactedNSError.domain == URLError.errorDomain)
        #expect(redactedNSError.code == URLError.Code.badServerResponse.rawValue)
    }

    @Test("Non-URL errors pass through unchanged")
    func nonURLErrorsPassThroughUnchanged() {
        let error = GeminiRealtimeError.connectionFailed("Bad audio")

        #expect(SpeechRealtimeErrorRedaction.redacted(error) as? GeminiRealtimeError == error)
    }
}

@Suite("Raw PCM Duration Validation")
struct SpeechFileUploadSupportRawPCMTests {
    @Test("Raw 16 kHz PCM longer than the limit fails before upload")
    func rawPCMLongerThanLimitFails() throws {
        // 16 kHz mono 16-bit PCM: 32000 bytes per second, so 96000 bytes is 3 seconds.
        let fileURL = try geminiTemporarySparseFileURL(named: "raw-pcm-long.pcm", size: 96_000)

        #expect(
            throws: SpeechError.uploadFailed(provider: .meta, reason: "Audio exceeds the 2 second limit.")
        ) {
            try SpeechFileUploadSupport.validateRawPCMDuration(
                fileURL: fileURL,
                sampleRate: 16000,
                maxDuration: 2,
                provider: .meta
            )
        }
    }

    @Test("Raw 16 kHz PCM within the limit passes")
    func rawPCMWithinLimitPasses() throws {
        let fileURL = try geminiTemporarySparseFileURL(named: "raw-pcm-short.pcm", size: 96_000)

        try SpeechFileUploadSupport.validateRawPCMDuration(
            fileURL: fileURL,
            sampleRate: 16000,
            maxDuration: 3,
            provider: .meta
        )
    }
}

@Suite("Gemini Realtime Configuration")
@MainActor
struct GeminiRealtimeConfigurationTests {
    @Test("The configuration realtime model wins over the realtime options model")
    func configurationRealtimeModelWinsOverOptionsModel() async {
        let service = SpeechService(
            gemini: GeminiConfiguration(
                apiKey: "gemini-key",
                realtimeModelID: .transcribeLive35,
                realtimeOptions: GeminiRealtimeOptions(
                    languageCodes: ["en-US"],
                    mode: .smart,
                    automaticActivityDetection: false
                )
            )
        )

        let options = service.geminiRealtimeService.options
        #expect(options.modelID == .transcribeLive35)
        #expect(options.languageCodes == ["en-US"])
        #expect(options.mode == .smart)
        #expect(options.automaticActivityDetection == false)
    }

    @Test("Starting a Gemini session applies the configured realtime model")
    func startingGeminiSessionAppliesConfiguredRealtimeModel() async throws {
        let service = SpeechService()
        service.gemini = GeminiConfiguration(
            apiKey: "gemini-key",
            realtimeModelID: .transcribeLive35,
            realtimeOptions: GeminiRealtimeOptions(customVocabulary: ["SpeechKit"])
        )

        let configuration = try #require(service.gemini)
        let resolved = service.resolvedGeminiRealtimeOptions(from: configuration)
        #expect(resolved.modelID == service.gemini?.realtimeModelID)
        #expect(resolved.customVocabulary == ["SpeechKit"])
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
/// Tests run in parallel and assert on the multipart `filename`, so the
/// directory is unique while the last path component stays `fileName`.
private func geminiTemporaryAudioFileURL(named fileName: String) -> URL {
    let url = uniqueTemporaryDirectory().appendingPathComponent(fileName)
    try? geminiMinimalWAVData().write(to: url)
    return url
}

private func geminiTemporarySparseFileURL(named fileName: String, size: UInt64) throws -> URL {
    let url = uniqueTemporaryDirectory().appendingPathComponent(fileName)
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: size)
    try handle.close()
    return url
}

/// A valid 16 kHz, 16-bit, mono PCM WAV holding 0.1 seconds of silence.
///
/// AVFoundation must be able to read a real duration from this file, so the
/// RIFF and `data` chunk sizes have to match the 3,200 bytes of samples.
private func geminiMinimalWAVData() -> Data {
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

private func geminiJSONObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        struct NotAnObject: Error {}
        throw NotAnObject()
    }
    return dictionary
}

private func geminiStubbedURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GeminiStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

@MainActor
private func geminiWaitForDisconnect(_ service: GeminiRealtimeService, timeout: TimeInterval = 3) async {
    let deadline = Date().addingTimeInterval(timeout)
    while service.connectionState != .disconnected, Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private final class GeminiStubURLProtocol: URLProtocol {
    private struct Stub {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func enqueue(statusCode: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(statusCode: statusCode, body: body))
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
        requests.removeAll()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let stub = Self.stubs.isEmpty ? Stub(statusCode: 500, body: Data()) : Self.stubs.removeFirst()
        Self.lock.unlock()

        if let url = request.url,
           let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
