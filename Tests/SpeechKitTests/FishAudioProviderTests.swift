import Foundation
import Testing
@testable import SpeechKit

@Suite("Fish Audio Provider")
struct FishAudioProviderTests {
    // MARK: - Request

    @Test("Fish Audio request always sends the exact transcribe-1-pro model header")
    func fishAudioRequestSendsExactModelHeader() async throws {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")

        let request = try await client.makeRequest(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))

        // A missing or misspelled header silently bills the retired transcribe-1 model.
        #expect(request.value(forHTTPHeaderField: "model") == "transcribe-1-pro")
        #expect(request.allHTTPHeaderFields?["model"] == "transcribe-1-pro")
        #expect(FishAudioFileTranscriptionModelID.allCases.map(\.rawValue) == ["transcribe-1-pro"])
        let body = try #require(request.httpBody).fishAudioUTF8String
        #expect(!body.contains("name=\"model\""))
    }

    @Test("Fish Audio request carries the method, URL, auth, timeout, and default fields")
    func fishAudioRequestDefaults() async throws {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")

        let request = try await client.makeRequest(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))
        let body = try #require(request.httpBody).fishAudioUTF8String

        #expect(request.url?.absoluteString == "https://api.fish.audio/v1/asr")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 900)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fish-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(body.contains(fishAudioTextPart("ignore_timestamps", "false")))
        #expect(body.contains(fishAudioTextPart("tag_audio_events", "true")))
        #expect(body.contains(fishAudioTextPart("diarize", "auto")))
        #expect(body.contains("name=\"audio\"; filename=\"call.wav\""))
        #expect(body.contains("Content-Type: audio/wav\r\n\r\n"))
        #expect(!body.contains("name=\"language\""))
        #expect(!body.contains("name=\"num_speakers\""))
        #expect(!body.contains("name=\"min_speakers\""))
        #expect(!body.contains("name=\"max_speakers\""))
    }

    @Test("Fish Audio request encodes every option with string booleans")
    func fishAudioRequestEncodesOptions() async throws {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")

        let request = try await client.makeRequest(
            file: fishAudioTemporaryAudioFileURL(named: "call.m4a"),
            options: FishAudioFileTranscriptionOptions(
                language: "fr",
                timestamps: false,
                diarize: .on,
                speakerCount: .exact(3),
                tagAudioEvents: false,
                timeoutInterval: 60
            )
        )
        let body = try #require(request.httpBody).fishAudioUTF8String

        #expect(request.timeoutInterval == 60)
        #expect(body.contains(fishAudioTextPart("language", "fr")))
        #expect(body.contains(fishAudioTextPart("ignore_timestamps", "true")))
        #expect(body.contains(fishAudioTextPart("tag_audio_events", "false")))
        #expect(body.contains(fishAudioTextPart("diarize", "true")))
        #expect(body.contains(fishAudioTextPart("num_speakers", "3")))
        #expect(body.contains("name=\"audio\"; filename=\"call.m4a\""))
        #expect(body.contains("Content-Type: audio/mp4\r\n\r\n"))
    }

    @Test("Fish Audio request encodes speaker ranges and diarize off")
    func fishAudioRequestEncodesSpeakerRange() async throws {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")
        let fileURL = fishAudioTemporaryAudioFileURL(named: "call.mp3")

        let range = try await client.makeRequest(
            file: fileURL,
            options: FishAudioFileTranscriptionOptions(speakerCount: .range(min: 2, max: 4))
        )
        let rangeBody = try #require(range.httpBody).fishAudioUTF8String
        #expect(rangeBody.contains(fishAudioTextPart("min_speakers", "2")))
        #expect(rangeBody.contains(fishAudioTextPart("max_speakers", "4")))
        #expect(!rangeBody.contains("name=\"num_speakers\""))

        let minimumOnly = try await client.makeRequest(
            file: fileURL,
            options: FishAudioFileTranscriptionOptions(speakerCount: .range(min: 2, max: nil))
        )
        let minimumBody = try #require(minimumOnly.httpBody).fishAudioUTF8String
        #expect(minimumBody.contains(fishAudioTextPart("min_speakers", "2")))
        #expect(!minimumBody.contains("name=\"max_speakers\""))

        let off = try await client.makeRequest(file: fileURL, options: FishAudioFileTranscriptionOptions(diarize: .off))
        #expect(try #require(off.httpBody).fishAudioUTF8String.contains(fishAudioTextPart("diarize", "false")))
    }

    @Test("Fish Audio sends a resolved token as a bearer token")
    func fishAudioSendsResolvedTokenAsBearer() async throws {
        let client = FishAudioFileTranscriptionClient(credential: .bearer(SpeechTokenResolver { _ in "fish-token" }), endpoint: URL(string: "https://proxy.example.com/fish"))

        let request = try await client.makeRequest(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fish-token")
        #expect(request.value(forHTTPHeaderField: "model") == "transcribe-1-pro")
    }

    @Test("Fish Audio honors an endpoint override")
    func fishAudioHonorsEndpointOverride() async throws {
        let endpoint = try #require(URL(string: "https://proxy.example.com/fish/asr"))
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key", endpoint: endpoint)

        let request = try await client.makeRequest(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))

        #expect(request.url == endpoint)
    }

    @Test("Fish Audio requires an API key before request creation")
    func fishAudioRequiresAPIKey() async {
        let client = FishAudioFileTranscriptionClient(apiKey: "")

        await #expect(throws: SpeechError.providerNotConfigured(.fishAudio)) {
            _ = try await client.makeRequest(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))
        }
    }

    // MARK: - Validation

    @Test("Fish Audio rejects invalid languages and non-positive timeouts")
    func fishAudioRejectsInvalidOptions() async {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")
        let fileURL = fishAudioTemporaryAudioFileURL(named: "call.wav")

        for language in ["EN", "eng", "en-US", "e", "é1"] {
            await #expect(throws: SpeechError.providerFailure(
                provider: .fishAudio,
                reason: .requestFailed)) {
                _ = try await client.makeRequest(file: fileURL, options: FishAudioFileTranscriptionOptions(language: language))
            }
        }

        await #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            _ = try await client.makeRequest(file: fileURL, options: FishAudioFileTranscriptionOptions(timeoutInterval: 0))
        }
    }

    @Test("Fish Audio rejects speaker hints that conflict or are out of range")
    func fishAudioRejectsInvalidSpeakerHints() throws {
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.exact(2), diarize: .off)
        }
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.range(min: 1, max: 3), diarize: .off)
        }
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.exact(0), diarize: .auto)
        }
        #expect(throws: SpeechError.providerFailure(
            provider: .fishAudio,
            reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.range(min: nil, max: nil), diarize: .auto)
        }
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.range(min: 0, max: 2), diarize: .on)
        }
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.range(min: nil, max: 0), diarize: .on)
        }
        #expect(throws: SpeechError.providerFailure(
            provider: .fishAudio,
            reason: .requestFailed)) {
            try FishAudioValidation.validateSpeakerCount(.range(min: 4, max: 2), diarize: .on)
        }

        try FishAudioValidation.validateSpeakerCount(nil, diarize: .off)
        try FishAudioValidation.validateSpeakerCount(.exact(1), diarize: .auto)
        try FishAudioValidation.validateSpeakerCount(.range(min: 2, max: 2), diarize: .on)
        try FishAudioValidation.validateLanguage("en")
        try FishAudioValidation.validateLanguage(nil)
    }

    @Test("Fish Audio rejects AIFF and CAF files before uploading")
    func fishAudioRejectsAIFFAndCAF() async {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")

        for fileExtension in ["aif", "aiff", "AIFF", "aifc", "caf"] {
            await #expect(throws: SpeechError.providerFailure(
                provider: .fishAudio,
                reason: .requestFailed)) {
                _ = try await client.makeRequest(file: fishAudioTemporaryAudioFileURL(named: "memo.\(fileExtension)"))
            }
        }
    }

    @Test("Fish Audio rejects audio longer than 60 minutes before uploading")
    func fishAudioRejectsLongAudio() async throws {
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key")
        let fileURL = try fishAudioSparseWAVFileURL(named: "long.wav", seconds: 3601)

        await #expect(throws: SpeechError.uploadFailed(provider: .fishAudio, reason: .uploadFailed)) {
            _ = try await client.makeRequest(file: fileURL)
        }
    }

    // MARK: - Response parsing

    @Test("Fish Audio diarized response keeps raw fields and derives text and words")
    func fishAudioParsesDiarizedResponse() throws {
        let response = try fishAudioDecode("""
        {
          "text": "<|speaker:0|>Thanks for calling, how can I help? <|speaker:1|>Hi. [laughter] It costs 3.5 dollars.",
          "duration": 6.2,
          "segments": [
            { "text": "thanks", "start": 0.0, "end": 0.4 },
            { "text": "for", "start": 0.4, "end": 0.6 },
            { "text": "calling", "start": 0.6, "end": 1.1 },
            { "text": "how", "start": 1.3, "end": 1.5 },
            { "text": "can", "start": 1.5, "end": 1.7 },
            { "text": "i", "start": 1.7, "end": 1.8 },
            { "text": "help", "start": 1.8, "end": 2.2 },
            { "text": "hi", "start": 3.0, "end": 3.3 },
            { "text": "it", "start": 4.0, "end": 4.2 },
            { "text": "costs", "start": 4.2, "end": 4.6 },
            { "text": "35", "start": 4.6, "end": 5.2 },
            { "text": "dollars", "start": 5.2, "end": 5.8 }
          ],
          "speaker_turns": [
            { "speaker": "speaker:0", "text": "Thanks for calling, how can I help?", "start": 0.0, "end": 2.2 },
            { "speaker": "speaker:1", "text": "Hi. [laughter] It costs 3.5 dollars.", "start": 2.9, "end": 6.0 }
          ],
          "language": "English",
          "language_code": "en",
          "request_id": "req-123"
        }
        """)

        #expect(response.text.hasPrefix("<|speaker:0|>Thanks"))
        #expect(response.transcriptText == "Thanks for calling, how can I help? Hi. [laughter] It costs 3.5 dollars.")
        #expect(response.duration == 6.2)
        #expect(response.segments.count == 12)
        #expect(response.segments[10] == FishAudioTranscriptionSegment(text: "35", start: 4.6, end: 5.2))
        #expect(response.speakerTurns.count == 2)
        #expect(response.speakerTurns[1].speaker == "speaker:1")
        #expect(response.language == "English")
        #expect(response.languageCode == "en")
        #expect(response.requestID == "req-123")

        #expect(response.words.map(\.text) == [
            "Thanks", "for", "calling,", "how", "can", "I", "help?", "Hi.", "It", "costs", "3.5", "dollars."
        ])
        #expect(response.words.map(\.speaker) == Array(repeating: "speaker:0", count: 7) + Array(repeating: "speaker:1", count: 5))
        #expect(response.words[0] == FishAudioTranscriptWord(text: "Thanks", start: 0.0, end: 0.4, speaker: "speaker:0"))
        #expect(response.words[11].start == 5.2)
        #expect(response.words[11].end == 5.8)
    }

    @Test("Fish Audio undiarized response takes punctuation from the top-level text")
    func fishAudioParsesUndiarizedResponse() throws {
        let response = try fishAudioDecode("""
        {
          "text": "Hello there. Good morning!",
          "duration": 2.0,
          "segments": [
            { "text": "hello", "start": 0.0, "end": 0.3 },
            { "text": "there", "start": 0.3, "end": 0.6 },
            { "text": "good", "start": 1.0, "end": 1.3 },
            { "text": "morning", "start": 1.3, "end": 1.8 }
          ],
          "language_code": "en"
        }
        """)

        #expect(response.transcriptText == "Hello there. Good morning!")
        #expect(response.speakerTurns.isEmpty)
        #expect(response.words.map(\.text) == ["Hello", "there.", "Good", "morning!"])
        #expect(response.words.allSatisfy { $0.speaker == nil })
        #expect(response.language == nil)
        #expect(response.requestID == nil)
    }

    @Test("Fish Audio response with empty segments has no words")
    func fishAudioParsesEmptySegments() throws {
        let response = try fishAudioDecode("""
        { "text": "<|speaker:0|>Hello.", "duration": 1.0, "segments": [], "speaker_turns": [], "request_id": "req-1" }
        """)

        #expect(response.transcriptText == "Hello.")
        #expect(response.segments.isEmpty)
        #expect(response.words.isEmpty)
    }

    @Test("Fish Audio response tolerates missing optional fields")
    func fishAudioParsesMissingFields() throws {
        let textOnly = try fishAudioDecode(#"{ "text": "Hello." }"#)
        #expect(textOnly.text == "Hello.")
        #expect(textOnly.transcriptText == "Hello.")
        #expect(textOnly.duration == nil)
        #expect(textOnly.segments.isEmpty)
        #expect(textOnly.speakerTurns.isEmpty)
        #expect(textOnly.languageCode == nil)
        #expect(textOnly.words.isEmpty)

        let empty = try fishAudioDecode("{}")
        #expect(empty.text.isEmpty)
        #expect(empty.transcriptText.isEmpty)

        let sparse = try fishAudioDecode("""
        { "text": "Hi.", "segments": [{ "text": "hi" }], "speaker_turns": [{ "text": "Hi." }] }
        """)
        #expect(sparse.words == [FishAudioTranscriptWord(text: "Hi.")])
    }

    @Test("Fish Audio strips speaker markers but keeps sound cues")
    func fishAudioStripsSpeakerMarkers() {
        #expect(FishAudioTranscriptMapping.removingSpeakerMarkers(from: "<|speaker:0|>Hi.  <|speaker:12|> [laughs] Yes.")
            == "Hi. [laughs] Yes.")
        #expect(FishAudioTranscriptMapping.removingSpeakerMarkers(from: "<|speaker:0|>Line one.\n<|speaker:1|>Line two.")
            == "Line one.\nLine two.")
        #expect(FishAudioTranscriptMapping.removingSpeakerMarkers(from: "No markers.") == "No markers.")
    }

    @Test("Fish Audio assigns each word the speaker whose turn contains its midpoint")
    func fishAudioAssignsSpeakersByMidpoint() {
        let words = FishAudioTranscriptMapping.words(
            segments: [
                FishAudioTranscriptionSegment(text: "one", start: 0.0, end: 1.0),
                // Starts in speaker 0's turn, but its midpoint (2.1) is in speaker 1's.
                FishAudioTranscriptionSegment(text: "two", start: 1.8, end: 2.4),
                // Midpoint 5.0 falls in a gap between turns.
                FishAudioTranscriptionSegment(text: "three", start: 4.8, end: 5.2),
                FishAudioTranscriptionSegment(text: "four", start: 6.0, end: 6.5),
                FishAudioTranscriptionSegment(text: "five")
            ],
            speakerTurns: [
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "One", start: 0.0, end: 2.0),
                FishAudioSpeakerTurn(speaker: "speaker:1", text: "two", start: 2.0, end: 4.0),
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "three four five", start: 5.5, end: 7.0)
            ],
            fallbackText: ""
        )

        #expect(words.map(\.speaker) == ["speaker:0", "speaker:1", nil, "speaker:0", nil])
    }

    @Test("Fish Audio punctuation transfer resyncs after a normalisation mismatch")
    func fishAudioPunctuationTransferResyncs() {
        let words = FishAudioTranscriptMapping.words(
            segments: [
                FishAudioTranscriptionSegment(text: "it", start: 0.0, end: 0.2),
                FishAudioTranscriptionSegment(text: "costs", start: 0.2, end: 0.5),
                FishAudioTranscriptionSegment(text: "three", start: 0.5, end: 0.8),
                FishAudioTranscriptionSegment(text: "fifty", start: 0.8, end: 1.1),
                FishAudioTranscriptionSegment(text: "ok", start: 1.2, end: 1.4),
                FishAudioTranscriptionSegment(text: "[laughs]", start: 1.4, end: 1.6),
                FishAudioTranscriptionSegment(text: "thanks", start: 1.6, end: 2.0)
            ],
            speakerTurns: [
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "It costs $3.50, ok? [laughs] Thanks!", start: 0.0, end: 2.0)
            ],
            fallbackText: ""
        )

        // "three fifty" never matches "$3.50", so those words keep their segment text,
        // and the walk resyncs on "ok?" and "Thanks!". The cue segment is left alone.
        #expect(words.map(\.text) == ["It", "costs", "three", "fifty", "ok?", "[laughs]", "Thanks!"])
        #expect(words.map(\.start) == [0.0, 0.2, 0.5, 0.8, 1.2, 1.4, 1.6])
    }

    @Test("Fish Audio punctuation transfer matches a normalised number to its punctuated form")
    func fishAudioPunctuationTransferNormalisedNumber() {
        let words = FishAudioTranscriptMapping.words(
            segments: [
                FishAudioTranscriptionSegment(text: "version", start: 0.0, end: 0.4),
                FishAudioTranscriptionSegment(text: "35", start: 0.4, end: 0.9),
                FishAudioTranscriptionSegment(text: "shipped", start: 0.9, end: 1.3)
            ],
            speakerTurns: [
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "Version 3.5, shipped.", start: 0.0, end: 1.3)
            ],
            fallbackText: ""
        )

        // "35" and "3.5," compare equal once punctuation is removed, so the word takes the punctuated token.
        #expect(words.map(\.text) == ["Version", "3.5,", "shipped."])
    }

    @Test("Fish Audio punctuation transfer leaves extra segment words unchanged without losing sync")
    func fishAudioPunctuationTransferExtraWords() {
        let words = FishAudioTranscriptMapping.words(
            segments: [
                FishAudioTranscriptionSegment(text: "um", start: 0.0, end: 0.2),
                FishAudioTranscriptionSegment(text: "hello", start: 0.2, end: 0.5),
                FishAudioTranscriptionSegment(text: "world", start: 0.5, end: 0.9)
            ],
            speakerTurns: [
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "Hello, world.", start: 0.0, end: 1.0)
            ],
            fallbackText: ""
        )

        #expect(words.map(\.text) == ["um", "Hello,", "world."])
    }

    // MARK: - Errors

    @Test("Fish Audio maps every documented error code")
    func fishAudioMapsDocumentedErrorCodes() {
        let cases: [(status: Int, code: String, summary: String, retryable: Bool)] = [
            (400, "invalid_request", "The request was invalid", false),
            (400, "invalid_parameter", "A request parameter was invalid", false),
            (400, "invalid_audio", "The audio could not be decoded", false),
            (400, "audio_too_long", "The audio exceeds Fish Audio's 60-minute limit", false),
            (400, "audio_too_short", "The audio is too short to transcribe", false),
            (503, "upstream_unavailable", "The transcription service is temporarily unavailable; retry later", true),
            (504, "upstream_timeout", "The transcription service timed out; retry later", true),
            (500, "excessive_repetition", "The transcription stopped because of excessive repetition; retry later", true),
            (500, "diarization_failed", "Speaker diarization failed; retry later or turn diarization off", true)
        ]

        for testCase in cases {
            let body = Data("""
            {"status": \(testCase.status), "message": "Details here", "code": "\(testCase.code)", "request_id": "req-9"}
            """.utf8)
            let failure = FishAudioAPIFailure(statusCode: testCase.status, body: body)

            #expect(failure.code == testCase.code)
            #expect(failure.requestID == "req-9")
            #expect(failure.isRetryable == testCase.retryable)
            #expect(failure.speechError == .httpFailure(provider: .fishAudio, statusCode: testCase.status))
        }
    }

    @Test("Fish Audio maps errors without a code by HTTP status")
    func fishAudioMapsErrorsByStatus() {
        let cases: [(status: Int, summary: String, retryable: Bool)] = [
            (400, "The request was invalid", false),
            (401, "The API key is invalid", false),
            (402, "The account has no remaining credit", false),
            (413, "The audio file is too large; upload compressed audio such as MP3 or M4A", false),
            (429, "Too many concurrent requests; retry after an in-flight request finishes", true),
            (502, "Fish Audio had a server error; retry later", true),
            (418, "The request failed", false)
        ]

        for testCase in cases {
            let body = Data(#"{"status": \#(testCase.status), "message": "Platform says no"}"#.utf8)
            let failure = FishAudioAPIFailure(statusCode: testCase.status, body: body)

            #expect(failure.code == nil)
            #expect(failure.isRetryable == testCase.retryable)
            #expect(failure.speechError == .httpFailure(provider: .fishAudio, statusCode: testCase.status))
        }
    }

    @Test("Fish Audio maps an unknown code by HTTP status")
    func fishAudioMapsUnknownCodeByStatus() {
        let failure = FishAudioAPIFailure(
            statusCode: 401,
            body: Data(#"{"status": 401, "message": "Bad key", "code": "something_new"}"#.utf8)
        )

        #expect(failure.speechError == .httpFailure(provider: .fishAudio, statusCode: 401))
    }

    @Test("Fish Audio maps a 413 with no body and a non-JSON body")
    func fishAudioMapsBodylessErrors() throws {
        #expect(throws: SpeechError.httpFailure(provider: .fishAudio, statusCode: 413)) {
            _ = try FishAudioFileTranscriptionClient.decodeResponse(data: Data(), statusCode: 413)
        }

        #expect(throws: SpeechError.httpFailure(provider: .fishAudio, statusCode: 502)) {
            _ = try FishAudioFileTranscriptionClient.decodeResponse(data: Data("<html>Bad Gateway</html>\n".utf8), statusCode: 502)
        }
    }

    @Test("Fish Audio reports an undecodable success body as a decoding failure")
    func fishAudioReportsDecodingFailure() {
        #expect(performing: {
            _ = try FishAudioFileTranscriptionClient.decodeResponse(data: Data("not json".utf8), statusCode: 200)
        }, throws: { error in
            guard case .decodingFailed(provider: .fishAudio, reason: .decodingFailed) = error as? SpeechError else { return false }
            return true
        })
    }

    // MARK: - Network round trip

    @Test("Fish Audio file transcription sends the request and decodes the response")
    func fishAudioRoundTrip() async throws {
        let endpoint = try #require(URL(string: "https://stub.example.com/\(UUID().uuidString)/asr"))
        FishAudioStubURLProtocol.register(
            endpoint,
            statusCode: 200,
            body: Data(#"{"text":"<|speaker:0|>Hello.","segments":[{"text":"hello","start":0,"end":0.5}],"speaker_turns":[{"speaker":"speaker:0","text":"Hello.","start":0,"end":0.5}]}"#.utf8)
        )
        let client = FishAudioFileTranscriptionClient(apiKey: "fish-key", endpoint: endpoint, urlSession: fishAudioStubbedURLSession())

        let response = try await client.transcribeAudioFileDetailed(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))

        #expect(response.transcriptText == "Hello.")
        #expect(response.words == [FishAudioTranscriptWord(text: "Hello.", start: 0, end: 0.5, speaker: "speaker:0")])
        let request = try #require(FishAudioStubURLProtocol.recordedRequest(for: endpoint))
        #expect(request.value(forHTTPHeaderField: "model") == "transcribe-1-pro")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fish-key")
    }

    @MainActor
    @Test("Fish Audio file transcription surfaces a mapped HTTP error")
    func fishAudioRoundTripError() async throws {
        let endpoint = try #require(URL(string: "https://stub.example.com/\(UUID().uuidString)/asr"))
        FishAudioStubURLProtocol.register(
            endpoint,
            statusCode: 402,
            body: Data(#"{"status":402,"message":"Insufficient balance","request_id":"req-2"}"#.utf8)
        )
        let service = SpeechService(
            fishAudio: FishAudioConfiguration(apiKey: "fish-key", fileEndpoint: endpoint),
            urlSession: fishAudioStubbedURLSession(),
            elevenLabsRealtimeService: ElevenLabsService()
        )

        await #expect(throws: SpeechError.httpFailure(provider: .fishAudio, statusCode: 402)) {
            _ = try await service.transcribeAudioFile(provider: .fishAudio, file: fishAudioTemporaryAudioFileURL(named: "call.wav"))
        }
    }

    // MARK: - Facade

    @MainActor
    @Test("Fish Audio configuration resolves per-request options over configuration defaults")
    func fishAudioFacadeResolvesOptions() throws {
        let service = SpeechService(
            fishAudio: FishAudioConfiguration(
                apiKey: "fish",
                language: "en",
                diarize: .on,
                speakerCount: .exact(2),
                tagAudioEvents: false,
                timeoutInterval: 30
            )
        )
        let config = try #require(service.fishAudio)

        let defaults = service.resolvedFishAudioOptions(from: nil, config: config)
        #expect(defaults == FishAudioFileTranscriptionOptions(
            modelID: .transcribe1Pro,
            language: "en",
            timestamps: true,
            diarize: .on,
            speakerCount: .exact(2),
            tagAudioEvents: false,
            timeoutInterval: 30
        ))

        let overridden = service.resolvedFishAudioOptions(
            from: .fishAudio(language: "de", timestamps: false, speakerCount: .range(min: 1, max: 3)),
            config: config
        )
        #expect(overridden.language == "de")
        #expect(overridden.timestamps == false)
        #expect(overridden.speakerCount == .range(min: 1, max: 3))
        #expect(overridden.diarize == .on)
        #expect(overridden.tagAudioEvents == false)
        #expect(overridden.timeoutInterval == 30)
    }

    @MainActor
    @Test("Fish Audio configuration defaults match the plan")
    func fishAudioConfigurationDefaults() {
        let config = FishAudioConfiguration(apiKey: "fish")

        #expect(config.fileTranscriptionModelID == .transcribe1Pro)
        #expect(config.timestamps == true)
        #expect(config.diarize == .auto)
        #expect(config.tagAudioEvents == true)
        #expect(config.timeoutInterval == 900)
        #expect(config.realtimeEndpoint == nil)
        #expect(config.credential == .apiKey("fish"))
        #expect(SpeechFileTranscriptionProvider.allCases.contains(.fishAudio))
        #expect(SpeechFileTranscriptionOptions.fishAudio().provider == .fishAudio)
    }

    @MainActor
    @Test("routing rejects Mistral options for Fish Audio")
    func fishAudioRoutingRejectsMistralOptions() async {
        let service = SpeechService(fishAudio: FishAudioConfiguration(apiKey: "fish"))

        await #expect(throws: SpeechError.invalidOptionsForProvider(expected: .fishAudio, received: .mistral)) {
            _ = try await service.transcribeAudioFile(
                provider: .fishAudio,
                file: fishAudioTemporaryAudioFileURL(named: "call.wav"),
                options: .mistral()
            )
        }
    }

    @MainActor
    @Test("Fish Audio file transcription requires configuration")
    func fishAudioFileTranscriptionRequiresConfiguration() async {
        let service = SpeechService()

        await #expect(throws: SpeechError.providerNotConfigured(.fishAudio)) {
            _ = try await service.transcribeFishAudioAudioFile(file: fishAudioTemporaryAudioFileURL(named: "call.wav"))
        }
        await #expect(throws: SpeechError.providerNotConfigured(.fishAudio)) {
            _ = try await service.transcribeAudioFile(provider: .fishAudio, file: fishAudioTemporaryAudioFileURL(named: "call.wav"))
        }
    }

    @MainActor
    @Test("Fish Audio facade rejects AIFF before any network call")
    func fishAudioFacadeRejectsAIFF() async {
        let service = SpeechService(fishAudio: FishAudioConfiguration(apiKey: "fish"))

        await #expect(throws: SpeechError.providerFailure(
            provider: .fishAudio,
            reason: .requestFailed)) {
            _ = try await service.transcribeFishAudioAudioFile(file: fishAudioTemporaryAudioFileURL(named: "memo.aiff"))
        }
    }
}

private func fishAudioTextPart(_ name: String, _ value: String) -> String {
    "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
}

private func fishAudioDecode(_ json: String) throws -> FishAudioFileTranscriptionResponse {
    try JSONDecoder().decode(FishAudioFileTranscriptionResponse.self, from: Data(json.utf8))
}

/// Writes a stub audio file into a fresh per-call temporary directory.
private func fishAudioTemporaryAudioFileURL(named fileName: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(fileName)
    try? Data("RIFF".utf8).write(to: url)
    return url
}

/// Writes a silent 8 kHz, 8-bit mono WAV of the given duration as a sparse file.
private func fishAudioSparseWAVFileURL(named fileName: String, seconds: Int) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(fileName)

    let sampleRate: UInt32 = 8000
    let dataSize = sampleRate * UInt32(seconds)
    var header = Data()
    func append(_ string: String) { header.append(contentsOf: Array(string.utf8)) }
    func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
    func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
    append("RIFF"); append32(36 + dataSize); append("WAVE")
    append("fmt "); append32(16); append16(1); append16(1)
    append32(sampleRate); append32(sampleRate); append16(1); append16(8)
    append("data"); append32(dataSize)

    try header.write(to: url)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(header.count) + UInt64(dataSize))
    try handle.close()
    return url
}

private func fishAudioStubbedURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FishAudioStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// Serves canned responses keyed by URL, so parallel tests never share a stub.
private final class FishAudioStubURLProtocol: URLProtocol {
    private struct Stub {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [URL: Stub] = [:]
    nonisolated(unsafe) private static var requests: [URL: URLRequest] = [:]

    static func register(_ url: URL, statusCode: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url] = Stub(statusCode: statusCode, body: body)
    }

    static func recordedRequest(for url: URL) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[url]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requests[url] = request
        let stub = Self.stubs[url] ?? Stub(statusCode: 500, body: Data())
        Self.lock.unlock()

        if let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    var fishAudioUTF8String: String {
        String(decoding: self, as: UTF8.self)
    }
}
