import Foundation
import Testing
@testable import SpeechKit

@Suite("Meta Provider")
struct MetaProviderTests {
    // MARK: - File transcription

    @Test("Meta multipart request carries a JSON request part before the audio part")
    func metaRequestCarriesJSONRequestPartBeforeAudio() async throws {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: MetaFileTranscriptionOptions(
                mode: .diarization,
                languageBias: [.english, .mandarinChinese],
                keywords: ["SpeechKit"]
            )
        )
        let body = try #require(request.httpBody).metaUTF8String

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer meta-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

        let requestPartIndex = try #require(body.range(of: "name=\"request\""))
        let audioPartIndex = try #require(body.range(of: "name=\"audio\""))
        #expect(requestPartIndex.lowerBound < audioPartIndex.lowerBound)

        #expect(body.contains("Content-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n"))
        #expect(body.contains("\"mode\":\"DIARIZATION\""))
        #expect(body.contains("\"model\":\"muse-voice-transcribe-1.0\""))
        #expect(body.contains("\"audioEncoding\":\"WAV\""))
        #expect(body.contains("\"languageBias\":[\"English\",\"Mandarin Chinese\"]"))
        #expect(body.contains("\"keywords\":[\"SpeechKit\"]"))
        #expect(body.contains("name=\"audio\"; filename=\"sample.wav\""))
        #expect(body.contains("Content-Type: audio/wav\r\n\r\n"))
    }

    @Test("Meta request defaults to endpointing mode with empty biasing arrays")
    func metaRequestDefaultsToEndpointingMode() async throws {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(file: fileURL)
        let body = try #require(request.httpBody).metaUTF8String

        #expect(body.contains("\"mode\":\"ENDPOINTING\""))
        #expect(body.contains("\"languageBias\":[]"))
        #expect(body.contains("\"keywords\":[]"))
        #expect(request.url?.absoluteString == "https://api.meta.ai/v1/asr/transcribe")
        #expect(request.timeoutInterval == 10 * 60)
    }

    @Test("Meta request appends the session identifier query item")
    func metaRequestAppendsSessionIDQuery() async throws {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            options: MetaFileTranscriptionOptions(sessionID: "9f1c")
        )

        #expect(request.url?.absoluteString == "https://api.meta.ai/v1/asr/transcribe?sessionId=9f1c")
    }

    @Test("Meta rejects non-WAV extensions for WAV uploads")
    func metaRejectsNonWAVExtension() async {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.m4a")

        await #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "Unsupported file extension: m4a.")) {
            _ = try await client.makeRequest(file: fileURL)
        }
    }

    @Test("Meta accepts raw PCM files for PCM encodings")
    func metaAcceptsRawPCMForPCMEncodings() async throws {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.pcm")

        let request = try await client.makeRequest(
            file: fileURL,
            options: MetaFileTranscriptionOptions(audioEncoding: .pcm24kHz)
        )
        let body = try #require(request.httpBody).metaUTF8String

        #expect(body.contains("\"audioEncoding\":\"PCM_24KHZ\""))
        #expect(body.contains("name=\"audio\"; filename=\"sample.pcm\""))
    }

    @Test("Meta rejects WAV files for PCM encodings")
    func metaRejectsWAVFileForPCMEncoding() async {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.wav")

        await #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "Unsupported file extension: wav.")) {
            _ = try await client.makeRequest(
                file: fileURL,
                options: MetaFileTranscriptionOptions(audioEncoding: .pcm16kHz)
            )
        }
    }

    @Test("Meta rejects files over 32 MB before request creation")
    func metaRejectsOversizedFile() async throws {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = try metaTemporarySparseFileURL(named: "large.wav", size: 32 * 1024 * 1024 + 1)

        await #expect(throws: SpeechError.uploadFailed(provider: .meta, reason: "Audio file exceeds 33554432 byte limit.")) {
            _ = try await client.makeRequest(file: fileURL)
        }
    }

    @Test("Meta rejects blank keywords, newline keywords, and non-positive timeouts")
    func metaRejectsInvalidOptions() async {
        let client = MetaFileTranscriptionClient(apiKey: "meta-key")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.wav")

        await #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "keywords cannot be empty: \"\".")) {
            _ = try await client.makeRequest(file: fileURL, options: MetaFileTranscriptionOptions(keywords: [""]))
        }

        await #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "keywords cannot contain newlines.")) {
            _ = try await client.makeRequest(file: fileURL, options: MetaFileTranscriptionOptions(keywords: ["a\nb"]))
        }

        await #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "timeoutInterval must be greater than 0.")) {
            _ = try await client.makeRequest(file: fileURL, options: MetaFileTranscriptionOptions(timeoutInterval: 0))
        }
    }

    @Test("Meta requires an API key before request creation")
    func metaRequiresAPIKey() async {
        let client = MetaFileTranscriptionClient(apiKey: "")
        let fileURL = metaTemporaryAudioFileURL(named: "sample.wav")

        await #expect(throws: SpeechError.providerNotConfigured(.meta)) {
            _ = try await client.makeRequest(file: fileURL)
        }
    }

    @Test("Meta file response decodes turns")
    func metaFileResponseDecodesTurns() throws {
        let data = Data("""
        {
          "sessionId": "9f1c",
          "transcript": "How is the weather? It is raining.",
          "audioDurationMs": 8240,
          "turns": [
            { "turnId": 1, "startMs": 1520, "endMs": 4640, "transcript": "How is the weather?", "speaker": "A" },
            { "turnId": 2, "startMs": 5900, "endMs": 8240, "transcript": "It is raining.", "speaker": "B" }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(MetaFileTranscriptionResponse.self, from: data)

        #expect(response.sessionID == "9f1c")
        #expect(response.text == "How is the weather? It is raining.")
        #expect(response.audioDurationMs == 8240)
        #expect(response.turns?.count == 2)
        #expect(response.turns?.first?.turnID == 1)
        #expect(response.turns?.first?.startMs == 1520)
        #expect(response.turns?.first?.endMs == 4640)
        #expect(response.turns?.first?.speaker == "A")
        #expect(response.turns?.last?.transcript == "It is raining.")
    }

    // MARK: - Realtime messages

    @Test("Meta realtime handshake encodes defaults")
    func metaRealtimeHandshakeEncodesDefaults() throws {
        let options = MetaRealtimeOptions()

        let data = try JSONEncoder().encode(options.handshakeMessage(secret: "meta-key"))
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"accessToken\":\"Bearer meta-key\""))
        #expect(json.contains("\"audioEncoding\":\"PCM_24KHZ\""))
        #expect(json.contains("\"mode\":\"ENDPOINTING\""))
        #expect(json.contains("\"partialMode\":\"CUMULATIVE\""))
        #expect(json.contains("\"emitAudioProgress\":false"))
        #expect(options.sampleRate == 24000)
        #expect(MetaRealtimeOptions(audioEncoding: .pcm16kHz).sampleRate == 16000)
    }

    @Test("Meta end stream message encodes the endStream type")
    func metaEndStreamMessageEncodesType() throws {
        let data = try JSONEncoder().encode(MetaEndStreamMessage())

        #expect(String(decoding: data, as: UTF8.self) == "{\"type\":\"endStream\"}")
    }

    @Test("Meta realtime options reject invalid keywords")
    func metaRealtimeOptionsRejectInvalidKeywords() {
        #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "keywords cannot be empty: \" \".")) {
            try MetaRealtimeOptions(keywords: [" "]).validate()
        }

        #expect(throws: SpeechError.providerFailure(provider: .meta, reason: "keywords cannot contain newlines.")) {
            try MetaRealtimeOptions(keywords: ["a\r\nb"]).validate()
        }
    }

    @Test("Meta realtime turn lifecycle events decode")
    func metaRealtimeTurnLifecycleEventsDecode() throws {
        let decoder = JSONDecoder()

        let start = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"speechStart","turnId":1,"audioProcessedMs":1200}
        """.utf8))
        guard case .speechStart(let startTurnID, let startMs) = start else {
            Issue.record("Expected a speech start event.")
            return
        }
        #expect(startTurnID == 1)
        #expect(startMs == 1200)

        let end = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"speechEnd","turnId":1,"audioProcessedMs":3600}
        """.utf8))
        guard case .speechEnd(let endTurnID, let endMs) = end else {
            Issue.record("Expected a speech end event.")
            return
        }
        #expect(endTurnID == 1)
        #expect(endMs == 3600)

        let finalTranscript = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"transcript","transcript":"how is the weather","final":true,"turnId":1,"audioProcessedMs":3600}
        """.utf8))
        guard case .transcript(let transcript) = finalTranscript else {
            Issue.record("Expected a transcript event.")
            return
        }
        #expect(transcript.final == true)
        #expect(transcript.turnID == 1)

        let progress = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"audioProgress","audioProcessedMs":4800}
        """.utf8))
        guard case .audioProgress(let processedMs) = progress else {
            Issue.record("Expected an audio progress event.")
            return
        }
        #expect(processedMs == 4800)

        let unknown = try decoder.decode(MetaRealtimeMessage.self, from: Data("""
        {"type":"somethingElse"}
        """.utf8))
        guard case .unknown(let type) = unknown else {
            Issue.record("Expected an unknown event.")
            return
        }
        #expect(type == "somethingElse")
    }

    // MARK: - Realtime service state machine

    @MainActor
    @Test("Meta service connects when the session acknowledgement arrives")
    func metaServiceConnectsOnSessionAcknowledgement() {
        let service = MetaRealtimeService(apiKey: "meta-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionCreated("9f1c"))

        #expect(service.connectionState == .connected(sessionID: "9f1c"))
    }

    @MainActor
    @Test("Meta service ignores a duplicate session acknowledgement")
    func metaServiceIgnoresDuplicateSessionAcknowledgement() {
        let service = MetaRealtimeService(apiKey: "meta-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionCreated("9f1c"))
        service.handleMessageForTesting(.sessionCreated("other-session"))

        #expect(service.connectionState == .connected(sessionID: "9f1c"))
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("Meta service ignores a session acknowledgement while disconnected")
    func metaServiceIgnoresSessionAcknowledgementWhileDisconnected() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.sessionCreated("9f1c"))

        #expect(service.connectionState == .disconnected)
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("Meta service tracks cumulative partials with turn and speaker context")
    func metaServiceTracksCumulativePartials() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.speechStart(turnID: 1, audioProcessedMs: 1200))
        service.handleMessageForTesting(.speaker(label: "A", audioProcessedMs: 1300))
        service.handleMessageForTesting(.transcript(metaTranscript("how is", final: false)))
        service.handleMessageForTesting(.transcript(metaTranscript("how is the weather", final: false)))

        #expect(service.partialTranscriptText == "how is the weather")
        let partial = service.partialTranscriptEntry
        #expect(partial?.provider == .meta)
        #expect(partial?.sourceID == "1")
        #expect(partial?.speaker == "A")
        #expect(partial?.isFinal == false)
        #expect(service.transcriptEntries.isEmpty)
    }

    @MainActor
    @Test("Meta service appends delta partials")
    func metaServiceAppendsDeltaPartials() {
        let service = MetaRealtimeService(apiKey: "meta-key", options: MetaRealtimeOptions(partialMode: .delta))

        service.handleMessageForTesting(.speechStart(turnID: 7, audioProcessedMs: 0))
        service.handleMessageForTesting(.transcript(metaTranscript("how", final: false)))
        service.handleMessageForTesting(.transcript(metaTranscript("is", final: false)))
        service.handleMessageForTesting(.transcript(metaTranscript(" the weather", final: false)))

        #expect(service.partialTranscriptText == "how is the weather")
        #expect(service.partialTranscriptEntry?.sourceID == "7")
    }

    @MainActor
    @Test("Meta service keeps a final transcript as a partial until the turn completes")
    func metaServiceKeepsFinalTranscriptAsPartial() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.speechStart(turnID: 1, audioProcessedMs: 1000))
        service.handleMessageForTesting(.transcript(metaTranscript("how is the weather", final: true)))

        #expect(service.partialTranscriptEntry?.isFinal == true)
        #expect(service.partialTranscriptEntry?.isUtteranceFinal == false)
        #expect(service.transcriptEntries.isEmpty)
    }

    @MainActor
    @Test("Meta service commits a turn on speech completion")
    func metaServiceCommitsTurnOnSpeechCompletion() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.speechStart(turnID: 1, audioProcessedMs: 1520))
        service.handleMessageForTesting(.speaker(label: "A", audioProcessedMs: 2480))
        service.handleMessageForTesting(.transcript(metaTranscript("how is the weather", final: false)))
        service.handleMessageForTesting(.speechEnd(turnID: 1, audioProcessedMs: 4640))
        service.handleMessageForTesting(
            .speechComplete(turnID: 1, transcript: "How is the weather?", audioProcessedMs: 4640)
        )

        #expect(service.transcriptEntries.count == 1)
        let entry = service.transcriptEntries.first
        #expect(entry?.provider == .meta)
        #expect(entry?.sourceID == "1")
        #expect(entry?.text == "How is the weather?")
        #expect(entry?.start == 1.52)
        #expect(entry?.duration == 3.12)
        #expect(entry?.isFinal == true)
        #expect(entry?.isUtteranceFinal == true)
        #expect(entry?.speaker == "A")
        #expect(service.partialTranscriptText.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
        #expect(service.transcriptText == "How is the weather?")
    }

    @MainActor
    @Test("Meta service ignores duplicate turn completions and audio progress")
    func metaServiceIgnoresDuplicateTurnCompletions() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.speechStart(turnID: 1, audioProcessedMs: 0))
        service.handleMessageForTesting(.speechComplete(turnID: 1, transcript: "Hello.", audioProcessedMs: 800))
        service.handleMessageForTesting(.audioProgress(audioProcessedMs: 900))
        service.handleMessageForTesting(.speechComplete(turnID: 1, transcript: "Hello.", audioProcessedMs: 800))

        #expect(service.transcriptEntries.count == 1)
        #expect(service.connectionState == .disconnected)
    }

    @MainActor
    @Test("Meta service surfaces realtime error events")
    func metaServiceSurfacesErrorEvents() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.error("Bad audio"))

        #expect(service.connectionState == .error("Bad audio"))
        #expect(service.lastError as? MetaRealtimeError == .connectionFailed("Bad audio"))
    }

    @MainActor
    @Test("Meta service clears committed and partial transcripts")
    func metaServiceClearsTranscripts() {
        let service = MetaRealtimeService(apiKey: "meta-key")

        service.handleMessageForTesting(.speechStart(turnID: 1, audioProcessedMs: 0))
        service.handleMessageForTesting(.speechComplete(turnID: 1, transcript: "Hello.", audioProcessedMs: 800))
        service.handleMessageForTesting(.transcript(metaTranscript("next turn", final: false)))
        service.clearTranscript()

        #expect(service.transcriptEntries.isEmpty)
        #expect(service.partialTranscriptText.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Meta service commits the pending partial when stopping")
    func metaServiceCommitsPendingPartialWhenStopping() async {
        let service = MetaRealtimeService(apiKey: "meta-key")
        service.setLifecycleStateForTesting(.listening)

        service.handleMessageForTesting(.speechStart(turnID: 3, audioProcessedMs: 2000))
        service.handleMessageForTesting(.transcript(metaTranscript("half a sentence", final: false)))
        await service.stopListening()

        #expect(service.connectionState == .disconnected)
        #expect(service.transcriptEntries.count == 1)
        #expect(service.transcriptEntries.first?.text == "half a sentence")
        #expect(service.transcriptEntries.first?.isUtteranceFinal == true)
        #expect(service.partialTranscriptEntry == nil)
    }

    @MainActor
    @Test("Meta service stop is idempotent while disconnected")
    func metaServiceStopIsIdempotent() async {
        let service = MetaRealtimeService(apiKey: "meta-key")

        await service.stopListening()
        await service.stopListening()

        #expect(service.connectionState == .disconnected)
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("Meta service reports a missing API key before connecting")
    func metaServiceReportsMissingAPIKey() async {
        let service = MetaRealtimeService()

        await service.startListening()

        #expect(service.connectionState == .error("Meta is not configured"))
        #expect(service.lastError as? MetaRealtimeError == .apiKeyMissing)
    }

    @MainActor
    @Test("Meta service rejects WAV realtime options before connecting")
    func metaServiceRejectsWAVRealtimeOptions() async {
        let service = MetaRealtimeService(apiKey: "meta-key", options: MetaRealtimeOptions(audioEncoding: .wav))

        await service.startListening()

        #expect(service.lastError as? SpeechError == .providerFailure(
            provider: .meta,
            reason: "Realtime transcription requires a raw PCM audio encoding."
        ))
        #expect(service.connectionState.isLifecycleActive == false)
    }
}

private func metaTranscript(
    _ text: String,
    final: Bool,
    turnID: Int? = nil,
    audioProcessedMs: Int? = nil
) -> MetaTranscript {
    MetaTranscript(transcript: text, final: final, turnID: turnID, audioProcessedMs: audioProcessedMs)
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
private func metaTemporaryAudioFileURL(named fileName: String) -> URL {
    let url = uniqueTemporaryDirectory().appendingPathComponent(fileName)
    try? metaMinimalWAVData().write(to: url)
    return url
}

private func metaTemporarySparseFileURL(named fileName: String, size: UInt64) throws -> URL {
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
private func metaMinimalWAVData() -> Data {
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
    var metaUTF8String: String {
        String(decoding: self, as: UTF8.self)
    }
}
