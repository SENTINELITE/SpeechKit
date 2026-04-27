import Foundation
import Testing
@testable import SpeechKit

@Suite("File Transcription Clients")
struct FileTranscriptionClientTests {
    @Test("Aqua multipart request includes Avalon model and omits language by default")
    func aquaRequestIncludesAvalonModelAndOmitsLanguageByDefault() throws {
        let client = AquaFileTranscriptionClient(apiKey: "aqua-key")
        let fileURL = temporaryAudioFileURL(named: "sample.mp3")

        let request = try client.makeRequest(file: fileURL)
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer aqua-key")
        #expect(body.contains("name=\"file\"; filename=\"sample.mp3\""))
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("\r\n\r\navalon-v1.5\r\n"))
        #expect(!body.contains("name=\"language\""))
    }

    @Test("Aqua multipart request includes explicit language")
    func aquaRequestIncludesExplicitLanguage() throws {
        let client = AquaFileTranscriptionClient(apiKey: "aqua-key")
        let fileURL = temporaryAudioFileURL(named: "sample.webm")

        let request = try client.makeRequest(
            file: fileURL,
            options: AquaFileTranscriptionOptions(language: .french)
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nfr\r\n"))
    }

    @Test("Aqua rejects unsupported file extension before request creation")
    func aquaRejectsUnsupportedFileExtension() {
        let client = AquaFileTranscriptionClient(apiKey: "aqua-key")
        let fileURL = temporaryAudioFileURL(named: "sample.aac")

        #expect(throws: SpeechError.providerFailure(provider: .aqua, reason: "Unsupported file extension: aac.")) {
            _ = try client.makeRequest(file: fileURL)
        }
    }

    @Test("Aqua response decodes usage and request id")
    func aquaResponseDecodesUsageAndRequestID() throws {
        let data = Data(
            """
            {"text":"hello","usage":{"type":"duration","seconds":170.11},"_request_id":"req-123"}
            """.utf8
        )

        let response = try JSONDecoder().decode(AquaFileTranscriptionResponse.self, from: data)

        #expect(response.text == "hello")
        #expect(response.usage.type == "duration")
        #expect(response.usage.seconds == 170.11)
        #expect(response.requestId == "req-123")
    }

    @Test("Cohere multipart request includes required fields")
    func cohereRequestIncludesRequiredFields() async throws {
        let client = CohereFileTranscriptionClient(apiKey: "cohere-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            modelId: .transcribe032026,
            language: .english,
            temperature: 0.2
        )
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cohere-key")
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("cohere-transcribe-03-2026"))
        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"temperature\""))
        #expect(body.contains("\r\n\r\n0.2\r\n"))
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }

    @Test("Cohere rejects unsupported file extension before request creation")
    func cohereRejectsUnsupportedFileExtension() async {
        let client = CohereFileTranscriptionClient(apiKey: "cohere-key")
        let fileURL = temporaryAudioFileURL(named: "sample.m4a")

        await #expect(throws: SpeechError.providerFailure(provider: .cohere, reason: "Unsupported file extension: m4a.")) {
            _ = try await client.makeRequest(
                file: fileURL,
                modelId: .transcribe032026,
                language: .english,
                temperature: nil
            )
        }
    }

    @Test("Cohere rejects files over 25 MB before request creation")
    func cohereRejectsOversizedFile() async throws {
        let client = CohereFileTranscriptionClient(apiKey: "cohere-key")
        let fileURL = try temporarySparseFileURL(named: "large.wav", size: 25 * 1024 * 1024 + 1)

        await #expect(throws: SpeechError.uploadFailed(provider: .cohere, reason: "Audio file exceeds 26214400 byte limit.")) {
            _ = try await client.makeRequest(
                file: fileURL,
                modelId: .transcribe032026,
                language: .english,
                temperature: nil
            )
        }
    }

    @Test("Cohere language enum serializes ISO code")
    func cohereLanguageEnumSerializesISOCode() async throws {
        let client = CohereFileTranscriptionClient(apiKey: "cohere-key")
        let fileURL = temporaryAudioFileURL(named: "sample.mp3")

        let request = try await client.makeRequest(
            file: fileURL,
            modelId: .transcribe032026,
            language: .french,
            temperature: nil
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nfr\r\n"))
    }

    @Test("ElevenLabs multipart request keeps model_id contract")
    func elevenLabsRequestIncludesModelIdField() async throws {
        let client = ElevenLabsFileTranscriptionClient(apiKey: "eleven-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(file: fileURL, modelId: .scribeV1)
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "eleven-key")
        #expect(body.contains("name=\"model_id\""))
        #expect(body.contains("scribe_v1"))
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }

    @Test("Grok multipart request includes file before options")
    func grokRequestIncludesFileBeforeOptions() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(
            file: fileURL,
            options: GrokFileTranscriptionOptions(
                language: .english,
                format: true,
                multichannel: true,
                channels: 2,
                diarize: true,
                timestampGranularities: [.word],
                audioFormat: .pcm,
                sampleRate: 16000,
                timeoutInterval: 900
            )
        )
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-key")
        #expect(request.timeoutInterval == 900)
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("\r\n\r\ngrok-stt\r\n"))
        #expect(body.contains("name=\"timestamp_granularities\""))
        #expect(body.contains("\r\n\r\nword\r\n"))
        #expect(body.contains("name=\"format\""))
        #expect(body.contains("\r\n\r\ntrue\r\n"))
        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"multichannel\""))
        #expect(body.contains("name=\"channels\""))
        #expect(body.contains("\r\n\r\n2\r\n"))
        #expect(body.contains("name=\"diarize\""))
        #expect(body.contains("name=\"audio_format\""))
        #expect(body.contains("\r\n\r\npcm\r\n"))
        #expect(body.contains("name=\"sample_rate\""))
        #expect(body.contains("\r\n\r\n16000\r\n"))
        let fileFieldIndex = try #require(body.range(of: "name=\"file\"; filename=\"sample.wav\"")?.lowerBound)
        let modelIndex = try #require(body.range(of: "name=\"model\"")?.lowerBound)
        let sampleRateIndex = try #require(body.range(of: "name=\"sample_rate\"")?.lowerBound)
        #expect(fileFieldIndex < modelIndex)
        #expect(fileFieldIndex < sampleRateIndex)
    }

    @Test("Grok multipart request includes required defaults and omits default false fields")
    func grokRequestIncludesRequiredDefaultsAndOmitsDefaultFalseFields() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(file: fileURL)
        let body = try #require(request.httpBody).utf8String

        #expect(request.timeoutInterval == 600)
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("\r\n\r\ngrok-stt\r\n"))
        #expect(body.contains("name=\"timestamp_granularities\""))
        #expect(body.contains("\r\n\r\nword\r\n"))
        #expect(!body.contains("name=\"format\""))
        #expect(!body.contains("name=\"multichannel\""))
        #expect(!body.contains("name=\"diarize\""))
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }

    @Test("Grok accepts supported container extension")
    func grokAcceptsSupportedContainerExtension() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.m4a")

        let request = try client.makeRequest(file: fileURL)
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"file\"; filename=\"sample.m4a\""))
    }

    @Test("Grok rejects unsupported file extension before request creation")
    func grokRejectsUnsupportedFileExtension() {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.webm")

        #expect(throws: SpeechError.providerFailure(provider: .grok, reason: "Unsupported file extension: webm.")) {
            _ = try client.makeRequest(file: fileURL)
        }
    }

    @Test("Grok rejects files over 500 MB before request creation")
    func grokRejectsOversizedFile() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = try temporarySparseFileURL(named: "large.mp3", size: 500 * 1024 * 1024 + 1)

        #expect(throws: SpeechError.uploadFailed(provider: .grok, reason: "Audio file exceeds 524288000 byte limit.")) {
            _ = try client.makeRequest(file: fileURL)
        }
    }

    @Test("Grok rejects raw audio without sample rate")
    func grokRejectsRawAudioWithoutSampleRate() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.pcm")

        #expect(throws: SpeechError.providerFailure(provider: .grok, reason: "Raw audio requires sample_rate.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: GrokFileTranscriptionOptions(audioFormat: .pcm)
            )
        }
    }

    @Test("Grok rejects unsupported sample rate")
    func grokRejectsUnsupportedSampleRate() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.pcm")

        #expect(throws: SpeechError.providerFailure(provider: .grok, reason: "Unsupported sample_rate: 12345.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: GrokFileTranscriptionOptions(audioFormat: .pcm, sampleRate: 12345)
            )
        }
    }

    @Test("Grok language enum serializes ISO code")
    func grokLanguageEnumSerializesISOCode() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(
            file: fileURL,
            options: GrokFileTranscriptionOptions(language: .filipino)
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nfil\r\n"))
    }
}

private func temporaryAudioFileURL(named fileName: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    try? minimalWAVData().write(to: url)
    return url
}

private func temporarySparseFileURL(named fileName: String, size: UInt64) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + fileName)
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: size)
    try handle.close()
    return url
}

private extension Data {
    var utf8String: String {
        String(decoding: self, as: UTF8.self)
    }
}

private func minimalWAVData() -> Data {
    Data([
        0x52, 0x49, 0x46, 0x46,
        0x24, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45,
        0x66, 0x6D, 0x74, 0x20,
        0x10, 0x00, 0x00, 0x00,
        0x01, 0x00,
        0x01, 0x00,
        0x40, 0x1F, 0x00, 0x00,
        0x40, 0x1F, 0x00, 0x00,
        0x01, 0x00,
        0x08, 0x00,
        0x64, 0x61, 0x74, 0x61,
        0x00, 0x00, 0x00, 0x00
    ])
}
