import Foundation
import Testing
@testable import SpeechKit

@Suite("File Transcription Clients")
struct FileTranscriptionClientTests {
    @Test("Cohere multipart request includes required fields")
    func cohereRequestIncludesRequiredFields() async throws {
        let client = CohereFileTranscriptionClient(apiKey: "cohere-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            modelId: .transcribe032026,
            language: "en",
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

    @Test("Grok multipart request includes options before file")
    func grokRequestIncludesOptionsBeforeFile() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(
            file: fileURL,
            options: GrokFileTranscriptionOptions(
                language: "en",
                format: true,
                multichannel: true,
                channels: 2,
                diarize: true,
                audioFormat: .pcm,
                sampleRate: 16000,
                timeoutInterval: 900
            )
        )
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-key")
        #expect(request.timeoutInterval == 900)
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
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))

        let fileFieldIndex = try #require(body.range(of: "name=\"file\"; filename=\"sample.wav\"")?.lowerBound)
        let sampleRateIndex = try #require(body.range(of: "name=\"sample_rate\"")?.lowerBound)
        #expect(sampleRateIndex < fileFieldIndex)
    }

    @Test("Grok multipart request omits default false fields")
    func grokRequestOmitsDefaultFalseFields() throws {
        let client = GrokFileTranscriptionClient(apiKey: "xai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(file: fileURL)
        let body = try #require(request.httpBody).utf8String

        #expect(request.timeoutInterval == 600)
        #expect(!body.contains("name=\"format\""))
        #expect(!body.contains("name=\"multichannel\""))
        #expect(!body.contains("name=\"diarize\""))
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }
}

private func temporaryAudioFileURL(named fileName: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    try? minimalWAVData().write(to: url)
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
