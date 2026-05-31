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

    @Test("Aqua rejects files over 25 MB before request creation")
    func aquaRejectsOversizedFile() throws {
        let client = AquaFileTranscriptionClient(apiKey: "aqua-key")
        let fileURL = try temporarySparseFileURL(named: "large.mp3", size: 25 * 1024 * 1024 + 1)

        #expect(throws: SpeechError.uploadFailed(provider: .aqua, reason: "Audio file exceeds 26214400 byte limit.")) {
            _ = try client.makeRequest(file: fileURL)
        }
    }

    @Test("Aqua response decodes usage and request ID")
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
        #expect(response.requestID == "req-123")
    }

    @Test("Cohere multipart request includes required fields")
    func cohereRequestIncludesRequiredFields() async throws {
        let client = CohereFileTranscriptionClient(apiKey: "cohere-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(
            file: fileURL,
            modelID: .transcribe032026,
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
                modelID: .transcribe032026,
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
                modelID: .transcribe032026,
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
            modelID: .transcribe032026,
            language: .french,
            temperature: nil
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nfr\r\n"))
    }

    @Test("ElevenLabs multipart request keeps model_id contract")
    func elevenLabsRequestIncludesModelIDField() async throws {
        let client = ElevenLabsFileTranscriptionClient(apiKey: "eleven-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try await client.makeRequest(file: fileURL, modelID: .scribeV1)
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "eleven-key")
        #expect(body.contains("name=\"model_id\""))
        #expect(body.contains("scribe_v1"))
        #expect(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }

    @Test("OpenAI multipart request includes model, response format, and optional fields")
    func openAIRequestIncludesModelResponseFormatAndOptionalFields() throws {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.webm")

        let request = try client.makeRequest(
            file: fileURL,
            options: OpenAIFileTranscriptionOptions(
                modelID: .gpt4oTranscribe,
                language: "en",
                prompt: "Use product spellings.",
                temperature: 0.2,
                includeLogprobs: true,
                timeoutInterval: 45
            )
        )
        let body = try #require(request.httpBody).utf8String

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-key")
        #expect(request.timeoutInterval == 45)
        #expect(body.contains("name=\"file\"; filename=\"sample.webm\""))
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("\r\n\r\ngpt-4o-transcribe\r\n"))
        #expect(body.contains("name=\"response_format\""))
        #expect(body.contains("\r\n\r\njson\r\n"))
        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"prompt\""))
        #expect(body.contains("Use product spellings."))
        #expect(body.contains("name=\"temperature\""))
        #expect(body.contains("\r\n\r\n0.2\r\n"))
        #expect(body.contains("name=\"include[]\""))
        #expect(body.contains("\r\n\r\nlogprobs\r\n"))
    }

    @Test("OpenAI Whisper timestamp request uses verbose JSON")
    func openAIWhisperTimestampRequestUsesVerboseJSON() throws {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(
            file: fileURL,
            options: OpenAIFileTranscriptionOptions(
                modelID: .whisper1,
                timestampGranularities: [.word, .segment]
            )
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"response_format\""))
        #expect(body.contains("\r\n\r\nverbose_json\r\n"))
        #expect(body.contains("name=\"timestamp_granularities[]\""))
        #expect(body.contains("\r\n\r\nword\r\n"))
        #expect(body.contains("\r\n\r\nsegment\r\n"))
    }

    @Test("OpenAI diarize model requests diarized JSON")
    func openAIDiarizeModelRequestsDiarizedJSON() throws {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.mp3")

        let request = try client.makeRequest(
            file: fileURL,
            options: OpenAIFileTranscriptionOptions(modelID: .gpt4oTranscribeDiarize)
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"response_format\""))
        #expect(body.contains("\r\n\r\ndiarized_json\r\n"))
        #expect(body.contains("name=\"chunking_strategy\""))
        #expect(body.contains("\r\n\r\nauto\r\n"))
    }

    @Test("OpenAI diarize request includes VAD chunking and known speakers")
    func openAIDiarizeRequestIncludesVADChunkingAndKnownSpeakers() throws {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        let request = try client.makeRequest(
            file: fileURL,
            options: OpenAIFileTranscriptionOptions(
                modelID: .gpt4oTranscribeDiarize,
                diarizationChunkingStrategy: .serverVAD(
                    OpenAIDiarizationVADOptions(
                        threshold: 0.4,
                        prefixPaddingMilliseconds: 250,
                        silenceDurationMilliseconds: 600
                    )
                ),
                knownSpeakers: [
                    OpenAIKnownSpeaker(name: "agent", referenceDataURL: "data:audio/wav;base64,AAA"),
                    OpenAIKnownSpeaker(name: "customer", referenceDataURL: "data:audio/wav;base64,BBB")
                ]
            )
        )
        let body = try #require(request.httpBody).utf8String

        #expect(body.contains("name=\"chunking_strategy\""))
        #expect(body.contains("\"type\":\"server_vad\""))
        #expect(body.contains("\"threshold\":0.4"))
        #expect(body.contains("\"prefix_padding_ms\":250"))
        #expect(body.contains("\"silence_duration_ms\":600"))
        #expect(body.contains("name=\"known_speaker_names[]\""))
        #expect(body.contains("\r\n\r\nagent\r\n"))
        #expect(body.contains("\r\n\r\ncustomer\r\n"))
        #expect(body.contains("name=\"known_speaker_references[]\""))
        #expect(body.contains("\r\n\r\ndata:audio/wav;base64,AAA\r\n"))
        #expect(body.contains("\r\n\r\ndata:audio/wav;base64,BBB\r\n"))
    }

    @Test("OpenAI rejects unsupported file extension before request creation")
    func openAIRejectsUnsupportedFileExtension() {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.flac")

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "Unsupported file extension: flac.")) {
            _ = try client.makeRequest(file: fileURL)
        }
    }

    @Test("OpenAI rejects files over 25 MB before request creation")
    func openAIRejectsOversizedFile() throws {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = try temporarySparseFileURL(named: "large.mp3", size: 25 * 1024 * 1024 + 1)

        #expect(throws: SpeechError.uploadFailed(provider: .openAI, reason: "Audio file exceeds 26214400 byte limit.")) {
            _ = try client.makeRequest(file: fileURL)
        }
    }

    @Test("OpenAI rejects timestamp granularities for GPT models")
    func openAIRejectsTimestampGranularitiesForGPTModels() {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "timestampGranularities are only supported with whisper-1.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(timestampGranularities: [.word])
            )
        }
    }

    @Test("OpenAI rejects diarize-only options with non-diarize models")
    func openAIRejectsDiarizeOnlyOptionsWithNonDiarizeModels() {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers require gpt-4o-transcribe-diarize.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(
                    knownSpeakers: [OpenAIKnownSpeaker(name: "agent", referenceDataURL: "data:audio/wav;base64,AAA")]
                )
            )
        }
    }

    @Test("OpenAI rejects unsupported diarize prompt and logprobs")
    func openAIRejectsUnsupportedDiarizePromptAndLogprobs() {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "prompt is not supported with gpt-4o-transcribe-diarize.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(
                    modelID: .gpt4oTranscribeDiarize,
                    prompt: "Use product spelling."
                )
            )
        }

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "includeLogprobs is not supported with gpt-4o-transcribe-diarize.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(
                    modelID: .gpt4oTranscribeDiarize,
                    includeLogprobs: true
                )
            )
        }
    }

    @Test("OpenAI rejects invalid diarize VAD and speaker references")
    func openAIRejectsInvalidDiarizeVADAndSpeakerReferences() {
        let client = OpenAIFileTranscriptionClient(apiKey: "openai-key")
        let fileURL = temporaryAudioFileURL(named: "sample.wav")

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers supports at most 4 speakers.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(
                    modelID: .gpt4oTranscribeDiarize,
                    knownSpeakers: (0..<5).map { index in
                        OpenAIKnownSpeaker(name: "speaker\(index)", referenceDataURL: "data:audio/wav;base64,AAA")
                    }
                )
            )
        }

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "diarization VAD threshold must be between 0 and 1.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(
                    modelID: .gpt4oTranscribeDiarize,
                    diarizationChunkingStrategy: .serverVAD(OpenAIDiarizationVADOptions(threshold: 1.5))
                )
            )
        }

        #expect(throws: SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers referenceDataURL must be an audio data URL.")) {
            _ = try client.makeRequest(
                file: fileURL,
                options: OpenAIFileTranscriptionOptions(
                    modelID: .gpt4oTranscribeDiarize,
                    knownSpeakers: [OpenAIKnownSpeaker(name: "agent", referenceDataURL: "data:text/plain;base64,AAA")]
                )
            )
        }
    }

    @Test("OpenAI detailed response decodes metadata")
    func openAIDetailedResponseDecodesMetadata() throws {
        let data = Data(
            """
            {
              "text":"hello",
              "language":"en",
              "duration":1.2,
              "usage":{"type":"tokens","input_tokens":10,"output_tokens":2,"total_tokens":12},
              "logprobs":[{"token":"hello","logprob":-0.1,"bytes":[104,101]}],
              "words":[{"word":"hello","start":0.0,"end":0.5}],
              "segments":[{"id":0,"start":0.0,"end":0.5,"text":"hello"}],
              "diarized_segments":[{"speaker":"speaker_0","start":0.0,"end":0.5,"text":"hello"}]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(OpenAIFileTranscriptionResponse.self, from: data)

        #expect(response.text == "hello")
        #expect(response.language == "en")
        #expect(response.usage?.totalTokens == 12)
        #expect(response.logprobs?.first?.token == "hello")
        #expect(response.words?.first?.word == "hello")
        #expect(response.segments?.first?.text == "hello")
        #expect(response.diarizedSegments?.first?.speaker == "speaker_0")
    }

    @Test("OpenAI current diarized response decodes speaker segments without losing timestamp segments")
    func openAICurrentDiarizedResponseDecodesSpeakerSegments() throws {
        let data = Data(
            """
            {
              "task": "transcribe",
              "duration": 42.7,
              "text": "Agent: hello",
              "usage": {"type":"tokens","total_tokens":12},
              "segments": [
                {
                  "type": "transcript.text.segment",
                  "id": "seg_001",
                  "speaker": "agent",
                  "start": 0.0,
                  "end": 1.5,
                  "text": "Agent: hello"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(OpenAIFileTranscriptionResponse.self, from: data)

        #expect(response.text == "Agent: hello")
        #expect(response.segments?.first?.text == "Agent: hello")
        #expect(response.segments?.first?.id == nil)
        #expect(response.diarizedSegments?.first?.speaker == "agent")
        #expect(response.diarizedSegments?.first?.start == 0.0)
        #expect(response.diarizedSegments?.first?.end == 1.5)
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
