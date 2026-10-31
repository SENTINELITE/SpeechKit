import AVFoundation
import Foundation
import Testing
@testable import SpeechKit

@Suite(.serialized)
struct SpeechRelayAudioImportTests {
    private static let signatures: [(Data, SpeechRelayAudioContainer)] = [
        (Data("fLaC".utf8), SpeechRelayAudioContainer.flac),
        (Data([0xff, 0xfb, 0x90, 0]), .mp3),
        (Data([0xff, 0xf3, 0x80, 0]), .mp3),
        (Data([0xff, 0xf1, 0x50, 0x80]), .aac),
        (Data([0, 0, 0, 24]) + Data("ftypM4A ".utf8), .mp4),
        (Data("FORM0000AIFF".utf8), .aiff),
        (Data("FORM0000AIFC".utf8), .aiff),
        (Data("caff".utf8), .caf),
        (Data([0x1a, 0x45, 0xdf, 0xa3]), .webm),
        (Data("ID3".utf8), .unknown),
        (Data([0xff, 0xfb, 0, 0]), .unknown),
        (Data("not audio.wav".utf8), .unknown)
    ]

    @Test(arguments: signatures)
    func detectsMagicBytes(bytes: Data, expected: SpeechRelayAudioContainer) {
        #expect(SpeechRelayAudioContainer.detect(bytes) == expected)
    }

    @Test func detectsWAVAndOggCodecsAndID3() throws {
        let wav = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: wav) }
        #expect(try SpeechRelayAudioContainer.read(wav) == .wav)
        for signature in [Data("OpusHead".utf8), Data([1]) + Data("vorbis".utf8)] {
            var page = Data("OggS".utf8) + Data(repeating: 0, count: 23)
            page[5] = 2
            page[26] = 1
            page.append(UInt8(signature.count))
            page.append(signature)
            #expect(SpeechRelayAudioContainer.detect(page) == .ogg)
        }
        #expect(SpeechRelayAudioContainer.detect(Data("OggS".utf8) + Data(repeating: 0, count: 64)) == .unknown)
        let tagged = wav.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp3")
        defer { try? FileManager.default.removeItem(at: tagged) }
        try (Data("ID3".utf8) + Data([4, 0, 0, 0, 0, 0, 4]) + Data(repeating: 0, count: 4) + Data([0xff, 0xfb, 0x90, 0])).write(to: tagged)
        #expect(try SpeechRelayAudioContainer.read(tagged) == .mp3)
    }

    @Test(arguments: SpeechFileTranscriptionProvider.allCases.filter { $0.rawValue != "apple" })
    func normalizesALACForEveryProvider(provider: SpeechFileTranscriptionProvider) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let original = try Data(contentsOf: source)
        let prepared = try await SpeechRelayAudioImport.prepare(file: source, provider: provider, optimizeUploads: true,
            temporaryDirectory: directory)
        let output = try AVAudioFile(forReading: prepared.file)
        #expect(output.fileFormat.sampleRate == 16_000)
        #expect(output.fileFormat.channelCount == 1)
        #expect(abs(Double(output.length) / 16_000 - 1) < 0.06)
        let container = try SpeechRelayAudioContainer.read(prepared.file)
        #expect(container == .flac || container == .wav)
        if provider == .openAI || provider == .meta {
            #expect(container == .wav)
            #expect(output.fileFormat.streamDescription.pointee.mBitsPerChannel == 16)
            let bytes = try Data(contentsOf: prepared.file)
            #expect(bytes.count == 44 + Int(output.length) * 2)
            #expect(String(decoding: bytes[12..<16], as: UTF8.self) == "fmt ")
            #expect(Array(bytes[16..<20]) == [16, 0, 0, 0])
            #expect(String(decoding: bytes[36..<40], as: UTF8.self) == "data")
            try SpeechRelayWAV.validate(prepared.file)
        }
        #expect(try Data(contentsOf: source) == original)
        let permissions = try FileManager.default.attributesOfItem(atPath: prepared.file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        let privateDirectory = try #require(prepared.directory)
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: privateDirectory.path)[.posixPermissions] as? NSNumber
        #expect(directoryPermissions?.intValue == 0o700)
        prepared.remove()
        #expect(!FileManager.default.fileExists(atPath: prepared.file.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try children(directory) == [source])
    }

    @Test func disabledRejectsContentNotFilenameAndDirectRemainsUnchanged() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let disguised = directory.appendingPathComponent("misleading.wav")
        try FileManager.default.copyItem(at: source, to: disguised)
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await SpeechRelayAudioImport.prepare(file: disguised, provider: .openAI, optimizeUploads: false,
                temporaryDirectory: directory)
        }
        let direct = try await SpeechRelayAudioImport.prepare(file: source, provider: .openAI, optimizeUploads: nil,
            maxUploadBytes: 1, temporaryDirectory: directory)
        #expect(direct.file == source && direct.directory == nil)
        direct.remove()
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func meterableFilesPassThroughAndMislabeledWAVIsCopied() async throws {
        let source = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let prepared = try await SpeechRelayAudioImport.prepare(file: source, provider: .meta, optimizeUploads: false)
        #expect(prepared.file == source && prepared.directory == nil)
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disguised = directory.appendingPathComponent("actually.m4a")
        try FileManager.default.copyItem(at: source, to: disguised)
        let copied = try await SpeechRelayAudioImport.prepare(file: disguised, provider: .meta, optimizeUploads: true,
            temporaryDirectory: directory)
        defer { copied.remove() }
        #expect(copied.file.pathExtension == "wav")
        #expect(try Data(contentsOf: copied.file) == Data(contentsOf: source))
    }

    @Test func preflightsSizeAndDurationWithoutLeavingFiles() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await SpeechRelayAudioImport.prepare(file: source, provider: .openAI, optimizeUploads: true,
                maxUploadBytes: 10_000, temporaryDirectory: directory)
        }
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await SpeechRelayAudioImport.prepare(file: source, provider: .fishAudio, optimizeUploads: true,
                maxDuration: 0.5, temporaryDirectory: directory)
        }
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await SpeechRelayAudioImport.prepare(file: source, provider: .cohere, optimizeUploads: true,
                maxUploadBytes: 1, temporaryDirectory: directory)
        }
        #expect(try children(directory) == [source])
    }

    @Test func openAISizeAndFishDurationLimitsFailBeforeHTTP() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("large.wav")
        let small = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: small) }
        var largeHeader = Data(try Data(contentsOf: small).prefix(44))
        let largeBytes: UInt32 = 25 * 1024 * 1024 + 2
        var largeRIFFSize = (largeBytes - 8).littleEndian
        var largeDataSize = (largeBytes - 44).littleEndian
        withUnsafeBytes(of: &largeRIFFSize) { largeHeader.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: &largeDataSize) { largeHeader.replaceSubrange(40..<44, with: $0) }
        try largeHeader.write(to: source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(largeBytes))
        try handle.close()
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected upload"); return .init() }
        let credential = relayCredential()
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await OpenAIFileTranscriptionClient(credential: credential, endpoint: fixture.url,
                urlSession: fixture.session()).transcribeAudioFile(file: source)
        }
        let long = directory.appendingPathComponent("long.wav")
        var header = Data(try Data(contentsOf: small).prefix(44))
        let audioBytes: UInt32 = 3601 * 16_000 * 2
        var riffSize = (audioBytes + 36).littleEndian
        var dataSize = audioBytes.littleEndian
        withUnsafeBytes(of: &riffSize) { header.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: &dataSize) { header.replaceSubrange(40..<44, with: $0) }
        try header.write(to: long)
        let longHandle = try FileHandle(forWritingTo: long)
        try longHandle.truncate(atOffset: UInt64(audioBytes) + 44)
        try longHandle.close()
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await FishAudioFileTranscriptionClient(credential: credential, endpoint: fixture.url,
                urlSession: fixture.session()).transcribeAudioFile(file: long)
        }
        #expect(fixture.requests.isEmpty)
        #expect(try children(directory).count == 2)
    }

    @Test func decodingFailureCleansUpAndDoesNotLeakFilename() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("PRIVATE_RECORDING.m4a")
        try Data("not audio".utf8).write(to: file)
        await #expect(throws: SpeechFailure(.audioNormalizationFailed)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI, optimizeUploads: true,
                temporaryDirectory: directory)
        }
        #expect(try children(directory) == [file])
        #expect(!SpeechFailure(.audioNormalizationFailed).localizedDescription.contains("PRIVATE_RECORDING"))
    }

    @Test(arguments: [16_000, 24_000])
    func wrapsRawPCMAsWAV(sampleRate: Int) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("audio.raw")
        try Data(repeating: 0, count: sampleRate * 2).write(to: raw)
        let prepared = try await SpeechRelayAudioImport.prepare(file: raw, provider: .meta, optimizeUploads: true,
            rawPCM: .init(sampleRate: sampleRate), temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.wrappedRawPCM)
        #expect(try SpeechRelayAudioContainer.read(prepared.file) == .wav)
        let output = try AVAudioFile(forReading: prepared.file)
        #expect(abs(Double(output.length) / 16_000 - 1) < 0.01)
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await SpeechRelayAudioImport.prepare(file: raw, provider: .meta, optimizeUploads: false,
                rawPCM: .init(sampleRate: sampleRate), temporaryDirectory: directory)
        }
    }

    @Test(arguments: [200, 500, 415])
    @MainActor func uploadRemovesTemporaryAudioOnSuccessAndFailure(status: Int) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let before = try imports()
        let observed = ImportDirectories()
        let fixture = SecurityHTTPFixture { request in
            observed.store(try Self.imports().subtracting(before))
            #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("filename=\"audio.wav\""))
            let body = status == 200 ? #"{"text":"ok"}"# : #"{"error":{"code":"unsupported_media_type","message":"PRIVATE_SERVER_TEXT"}}"#
            return .init(status: status, body: Data(body.utf8))
        }
        let client = OpenAIFileTranscriptionClient(credential: relayCredential(origin: fixture.url),
            endpoint: fixture.endpoint("speechkit/v1/openai/v1/audio/transcriptions"),
            urlSession: fixture.session())
        if status == 200 {
            #expect(try await client.transcribeAudioFile(file: source) == "ok")
        } else if status == 415 {
            await #expect(throws: SpeechFailure(.unsupportedMediaType, statusCode: 415)) {
                try await client.transcribeAudioFile(file: source)
            }
        } else {
            await #expect(throws: SpeechFailure(.server, statusCode: status)) {
                try await client.transcribeAudioFile(file: source)
            }
        }
        #expect(fixture.requests.count == 1)
        #expect(!observed.value.isEmpty)
        for created in observed.value { #expect(!FileManager.default.fileExists(atPath: created.path)) }
        #expect(FileManager.default.fileExists(atPath: source.path))
        let service = SpeechService()
        #expect(service.wrap(SpeechFailure(.unsupportedMediaType, statusCode: 415), for: .openAI) as? SpeechFailure == SpeechFailure(.unsupportedMediaType, statusCode: 415))
    }

    @Test func disabledClientRejectsBeforeCredentialResolutionOrHTTP() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected upload"); return .init() }
        let credential = SpeechCredential.relay(SpeechTokenResolver { _ in
            Issue.record("Unexpected credential resolution")
            return "synthetic"
        }).withRelayTransport(origin: fixture.url, pinnedPublicKeyHashes: [], optimizeUploads: false)
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await OpenAIFileTranscriptionClient(credential: credential, endpoint: fixture.url,
                urlSession: fixture.session()).transcribeAudioFile(file: source)
        }
        #expect(fixture.requests.isEmpty)
        #expect(SpeechRelay(url: fixture.url).optimizedUploads == .on)
    }

    @Test func cancellationDuringConversionRemovesPartialOutput() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("long.raw")
        try Data().write(to: source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 3600 * 16_000 * 2)
        try handle.close()
        let task = Task {
            try await SpeechRelayAudioImport.prepare(file: source, provider: .grok, optimizeUploads: true,
                rawPCM: .init(sampleRate: 16_000), temporaryDirectory: directory)
        }
        var started = false
        for _ in 0..<10_000 {
            if try children(directory).contains(where: {
                $0.lastPathComponent.hasPrefix("SpeechKit-import-") &&
                    FileManager.default.fileExists(atPath: $0.appendingPathComponent("audio.wav").path)
            }) {
                started = true
                break
            }
            await Task.yield()
        }
        #expect(started)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try children(directory) == [source])
    }

    @Test func transportMapsOnlyRelayUnsupportedMediaAndNeverRetries() async throws {
        let fixture = SecurityHTTPFixture { _ in
            .init(status: 415, body: Data(#"{"error":{"code":"unsupported_media_type","message":"PRIVATE_SERVER_TEXT"}}"#.utf8))
        }
        let request = URLRequest(url: fixture.url)
        await #expect(throws: SpeechFailure(.unsupportedMediaType, statusCode: 415)) {
            try await SpeechTransport.data(for: request, session: fixture.session(), prepare: { .init(request: $0) })
        }
        let direct = try await SpeechTransport.data(for: request, session: fixture.session())
        #expect((direct.1 as? HTTPURLResponse)?.statusCode == 415)
        #expect(fixture.requests.count == 2)
        #expect(!SpeechRelayRetry.permitsRenewal(statusCode: 415, audioSent: false, accepted: false, attempt: 0))
        #expect(!SpeechFailure(.unsupportedMediaType).localizedDescription.contains("PRIVATE_SERVER_TEXT"))
    }

    @Test(arguments: SpeechFileTranscriptionProvider.allCases.filter { $0.rawValue != "apple" })
    @MainActor func everyCloudClientNormalizesM4AThroughFacade(provider: SpeechFileTranscriptionProvider) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-ticket")
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(!body.contains("voice-memo.m4a"))
            if provider == .gemini {
                let unescaped = body.replacingOccurrences(of: "\\/", with: "/")
                #expect(unescaped.contains("audio/flac") || unescaped.contains("audio/wav"))
            } else {
                #expect(body.contains("filename=\"audio.flac\"") || body.contains("filename=\"audio.wav\""))
            }
            return .init(body: Data(#"{"text":"ok","transcript":"ok","usage":{"type":"audio","seconds":1},"_request_id":"synthetic","status":"completed","steps":[{"content":[{"text":"ok"}]}]}"#.utf8))
        }
        let relay = SpeechRelay(url: fixture.url, authentication: .none)
        let service = SpeechService(urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        service.relay = relay
        service.relaySession = SpeechRelaySession(relay: relay, session: fixture.session())
        #expect(try await service.transcribeAudioFile(provider: provider, file: source) == "ok")
        #expect(fixture.requests.count == 2)
    }

    @Test @MainActor func disabledRelayOptionReachesFileClient() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected network request"); return .init() }
        let relay = SpeechRelay(url: fixture.url, authentication: .none, optimizedUploads: .off)
        let service = SpeechService(urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        service.relay = relay
        service.relaySession = SpeechRelaySession(relay: relay, session: fixture.session())
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await service.transcribeAudioFile(provider: .openAI, file: source)
        }
        #expect(fixture.requests.isEmpty)
    }

    @Test func directM4AUploadKeepsOriginalBytes() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let original = try Data(contentsOf: source)
        let fixture = SecurityHTTPFixture { request in
            let body = request.httpBody ?? Data()
            #expect(body.range(of: original) != nil)
            #expect(String(decoding: body, as: UTF8.self).contains("filename=\"voice-memo.m4a\""))
            return .init(body: Data(#"{"text":"ok"}"#.utf8))
        }
        let client = OpenAIFileTranscriptionClient(apiKey: "synthetic-key", endpoint: fixture.url,
            urlSession: fixture.session())
        #expect(try await client.transcribeAudioFile(file: source) == "ok")
        #expect(try children(directory) == [source])
        #expect(try Data(contentsOf: source) == original)
    }

    @Test(arguments: [16_000, 24_000])
    func metaRawRequestDeclaresWAV(sampleRate: Int) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("audio.pcm")
        try Data(repeating: 0, count: sampleRate * 2).write(to: source)
        let fixture = SecurityHTTPFixture { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("\"audio_encoding\":\"WAV\"") || body.contains("\"audioEncoding\":\"WAV\""))
            #expect(!body.contains("PCM_16KHZ") && !body.contains("PCM_24KHZ"))
            #expect(body.contains("Content-Type: audio/wav"))
            return .init(body: Data(#"{"transcript":"ok"}"#.utf8))
        }
        let options = MetaFileTranscriptionOptions(audioEncoding: sampleRate == 16_000 ? .pcm16kHz : .pcm24kHz)
        let client = MetaFileTranscriptionClient(credential: relayCredential(origin: fixture.url),
            endpoint: fixture.endpoint("speechkit/v1/meta/v1/asr/transcribe"), urlSession: fixture.session())
        #expect(try await client.transcribeAudioFile(file: source, options: options) == "ok")
        #expect(fixture.requests.count == 1)
    }

    @Test func grokRawRequestUsesContainerWithoutDecoderOverrides() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("audio.pcm")
        try Data(repeating: 0, count: 48_000).write(to: source)
        let fixture = SecurityHTTPFixture { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("filename=\"audio.wav\""))
            #expect(!body.contains("audio_format") && !body.contains("sample_rate"))
            return .init(body: Data(#"{"text":"ok"}"#.utf8))
        }
        let client = GrokFileTranscriptionClient(credential: relayCredential(origin: fixture.url),
            endpoint: fixture.endpoint("speechkit/v1/grok/v1/stt"), urlSession: fixture.session())
        #expect(try await client.transcribeAudioFile(file: source,
            options: .init(audioFormat: .pcm, sampleRate: 24_000)) == "ok")
        for format in [GrokAudioFormat.mulaw, .alaw] {
            await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
                try await client.transcribeAudioFile(file: source, options: .init(audioFormat: format, sampleRate: 16_000))
            }
        }
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await client.transcribeAudioFile(file: source,
                options: .init(multichannel: true, channels: 2, audioFormat: .pcm, sampleRate: 16_000))
        }
        #expect(fixture.requests.count == 1)
    }

    @Test @MainActor func cancellingUploadRemovesTemporaryAudio() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        let before = try imports()
        let gate = SecurityGate()
        let fixture = SecurityHTTPFixture(beforeResponse: { _ in await gate.wait() }) { _ in
            .init(body: Data(#"{"text":"ok"}"#.utf8))
        }
        let service = SpeechService(openAI: OpenAIConfiguration(credential: relayCredential(origin: fixture.url),
            fileEndpoint: fixture.endpoint("speechkit/v1/openai/v1/audio/transcriptions")),
            urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        let task = Task { try await service.transcribeAudioFile(provider: .openAI, file: source) }
        while !(await gate.entered) { await Task.yield() }
        let created = try imports().subtracting(before)
        #expect(!created.isEmpty)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await gate.open()
        for output in created { #expect(!FileManager.default.fileExists(atPath: output.path)) }
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(fixture.requests.count == 1)
    }

    @Test(arguments: [SpeechFileTranscriptionProvider.openAI, .mistral])
    func decodedOutputByteCeilingCleansTemporaryFiles(provider: SpeechFileTranscriptionProvider) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await SpeechRelayAudioImport.prepare(file: source, provider: provider, optimizeUploads: true,
                workLimits: .init(maxOutputBytes: 9000), temporaryDirectory: directory)
        }
        #expect(try children(directory) == [source])
    }

    @Test(arguments: SpeechFileTranscriptionProvider.allCases.filter { $0 != .apple })
    func unconditionalFrameCeilingAppliesWithoutProviderLimits(provider: SpeechFileTranscriptionProvider) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try alac(in: directory)
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await SpeechRelayAudioImport.prepare(file: source, provider: provider, optimizeUploads: true,
                workLimits: .init(maxFrames: 8000), temporaryDirectory: directory)
        }
        #expect(try children(directory) == [source])
        #expect(SpeechRelayAudioImport.WorkLimits(maxFrames: .max, maxOutputBytes: .max).maxFrames == 57_600_000)
        #expect(SpeechRelayAudioImport.WorkLimits(maxFrames: .max, maxOutputBytes: .max).maxOutputBytes == 128 * 1024 * 1024)
    }

    @Test func highlyCompressedLongInputFailsMistralPreflightWithoutHTTPOrTemporaryFiles() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("compressed-long.flac")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = buffer.frameCapacity
        try #require(buffer.floatChannelData)[0].initialize(repeating: 0, count: 16_000)
        do {
            let writer = try AVAudioFile(forWriting: source, settings: [AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16],
                commonFormat: .pcmFormatFloat32, interleaved: false)
            for _ in 0..<3601 { try writer.write(from: buffer) }
        }
        #expect(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize! < 1_000_000)
        let before = try imports()
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected Mistral upload"); return .init() }
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await MistralFileTranscriptionClient(credential: relayCredential(origin: fixture.url),
                endpoint: fixture.url, urlSession: fixture.session()).transcribeAudioFile(file: source)
        }
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await SpeechRelayAudioImport.prepare(file: source, provider: .mistral, optimizeUploads: true,
                temporaryDirectory: directory)
        }
        #expect(fixture.requests.isEmpty)
        #expect(try imports() == before)
        #expect(try children(directory) == [source])
    }

    @Test func mistralOversizedFileFailsBeforeWholeFileRead() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("oversized.wav")
        try Data().write(to: source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(MistralFileTranscriptionClient.maxUploadBytes) + 1)
        try handle.close()
        let before = try imports()
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected Mistral upload"); return .init() }
        let client = MistralFileTranscriptionClient(apiKey: "synthetic-key", endpoint: fixture.url, urlSession: fixture.session())
        #expect(throws: SpeechError.uploadFailed(provider: .mistral, reason: .uploadFailed)) {
            try client.makeRequest(file: source, secret: "synthetic-key")
        }
        #expect(fixture.requests.isEmpty)
        #expect(try imports() == before)
        #expect(try children(directory) == [source])
    }

    @Test(arguments: ["FLLR", "abcd"])
    func invalidWAVChunksFailBeforeUpload(chunk: String) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: valid) }
        var bytes = try Data(contentsOf: valid)
        let size = chunk == "FLLR" ? 4097 : 2
        bytes.append(Data(chunk.utf8))
        var chunkSize = UInt32(size).littleEndian
        withUnsafeBytes(of: &chunkSize) { bytes.append(contentsOf: $0) }
        bytes.append(Data(repeating: 0, count: size + size % 2))
        var riffSize = UInt32(bytes.count - 8).littleEndian
        withUnsafeBytes(of: &riffSize) { bytes.replaceSubrange(4..<8, with: $0) }
        let source = directory.appendingPathComponent("invalid.wav")
        try bytes.write(to: source)
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected WAV upload"); return .init() }
        let before = try imports()
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await OpenAIFileTranscriptionClient(credential: relayCredential(origin: fixture.url),
                endpoint: fixture.url, urlSession: fixture.session()).transcribeAudioFile(file: source)
        }
        #expect(fixture.requests.isEmpty)
        #expect(try imports() == before)
        #expect(try children(directory) == [source])
    }

    private static func imports() throws -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("SpeechKit-import-") })
    }

    private func imports() throws -> Set<URL> { try Self.imports() }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func children(_ directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.standardizedFileURL)
    }

    private func relayCredential(origin: URL = URL(string: "https://relay.invalid")!) -> SpeechCredential {
        SpeechCredential.relay(SpeechTokenResolver { _ in "synthetic-ticket" })
            .withRelayTransport(origin: origin, pinnedPublicKeyHashes: [],
                prepare: { .init(request: $0) })
    }

    private func alac(in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent("voice-memo.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = buffer.frameCapacity
        let channels = try #require(buffer.floatChannelData)
        for index in 0..<Int(buffer.frameLength) {
            channels[0][index] = sin(Float(index) * 440 * 2 * .pi / 44_100) * 0.2
            channels[1][index] = channels[0][index]
        }
        let writer = try AVAudioFile(forWriting: file, settings: [AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2, AVEncoderBitDepthHintKey: 16])
        try writer.write(from: buffer)
        return file
    }
}

private final class ImportDirectories: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Set<URL> = []
    var value: Set<URL> { lock.withLock { stored } }
    func store(_ directories: Set<URL>) { lock.withLock { stored = directories } }
}
