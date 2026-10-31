import AVFoundation
import Foundation
import Testing
@testable import SpeechKit

@Suite(.serialized)
struct SpeechRelayUploadOptimizationTests {
    @Test func uploadOptimizationDefaultsOnAndCanBeDisabled() {
        let relay = SpeechRelay(url: URL(string: "https://relay.invalid")!)
        let disabled = SpeechRelay(url: relay.url, optimizedUploads: .off)
        #expect(relay.optimizedUploads == .on)
        #expect(disabled.optimizedUploads == .off)
    }

    @Test(arguments: [SpeechFileTranscriptionProvider.openAI, .elevenLabs, .aqua, .grok, .gemini, .fishAudio])
    func audioOnlyFastStartIsByteIdentical(provider: SpeechFileTranscriptionProvider) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("memo.mp4")
        try await exportAudio(original, to: file)
        #expect(try SpeechRelayMP4.duration(file) > 0.9)
        let bytes = try Data(contentsOf: file)
        for enabled in [true, false] {
            let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: provider,
                optimizeUploads: enabled, temporaryDirectory: directory)
            #expect(prepared.file == file)
            #expect(prepared.directory == nil)
            #expect(try Data(contentsOf: prepared.file) == bytes)
            prepared.remove()
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test(arguments: ["m4a", "mov"])
    func moovLastRepackagesWithoutReencoding(suffix: String) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("memo." + suffix)
        try FileManager.default.moveItem(at: original, to: file)
        try moveMoovLast(file)
        let bytes = try Data(contentsOf: file)
        #expect(throws: SpeechFailure(.unsupportedMediaType)) { try SpeechRelayMP4.duration(file) }
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.file.pathExtension == "m4a")
        #expect(try SpeechRelayMP4.duration(prepared.file) > 0.9)
        #expect(try AVAudioFile(forReading: prepared.file).fileFormat.sampleRate == 44_100)
        #expect(try await aacPackets(file) == aacPackets(prepared.file))
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: prepared.file.path)[.posixPermissions] as? NSNumber == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: #require(prepared.directory).path)[.posixPermissions] as? NSNumber == 0o700)
    }

    @Test func stripsVideoTrackWithoutReencoding() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("movie.mov")
        try await movie(audio: original, to: file, directory: directory)
        let bytes = try Data(contentsOf: file)
        #expect(throws: SpeechFailure(.unsupportedMediaType)) { try SpeechRelayMP4.duration(file) }
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.file.pathExtension == "m4a")
        #expect(try SpeechRelayMP4.duration(prepared.file) > 0.9)
        #expect(try await AVURLAsset(url: prepared.file).loadTracks(withMediaType: .video).isEmpty)
        let originalPackets = try await aacPackets(file)
        let outputPackets = try await aacPackets(prepared.file)
        #expect(originalPackets.range(of: outputPackets) != nil,
            "Encoded packet bytes before: \(originalPackets.count), after: \(outputPackets.count)")
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test(arguments: ["mov", "mp4"])
    func quickTimeRequiresRepackagingEvenWithLeadingMoov(suffix: String) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("quicktime." + suffix)
        try await exportAudio(original, to: file, type: .mov)
        let bytes = try Data(contentsOf: file)
        #expect(try SpeechRelayAudioContainer.read(file) == .mov)
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.file != file && prepared.file.pathExtension == "m4a")
        let originalPackets = try await aacPackets(file)
        let outputPackets = try await aacPackets(prepared.file)
        #expect(originalPackets.range(of: outputPackets) != nil)
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI, optimizeUploads: false)
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func highRateStereoWAVStaysUntouchedWhenOff() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try audio(in: directory, codec: kAudioFormatLinearPCM, rate: 48_000)
        let bytes = try Data(contentsOf: file)
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: false, temporaryDirectory: directory)
        #expect(prepared.file == file && prepared.directory == nil)
        #expect(try Data(contentsOf: prepared.file) == bytes)
    }

    @Test func oversizedStereoWAVIsLimitedAfterConversion() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try audio(in: directory, codec: kAudioFormatLinearPCM, rate: 48_000, seconds: 160)
        let original = try Data(contentsOf: file)
        let cap: Int64 = 25 * 1024 * 1024
        #expect(original.count > cap)
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, maxUploadBytes: cap, temporaryDirectory: directory)
        defer { prepared.remove() }
        let result = try AVAudioFile(forReading: prepared.file)
        #expect(result.fileFormat.sampleRate == 16_000)
        #expect(result.fileFormat.channelCount == 1)
        #expect(result.length == 160 * 16_000)
        #expect(try Data(contentsOf: prepared.file).count == 5_120_044)
        #expect(try Data(contentsOf: file) == original)
        let preparedBytes = try Data(contentsOf: prepared.file)
        let fixture = SecurityHTTPFixture { request in
            let body = try #require(request.httpBody)
            #expect(body.count < cap)
            #expect(body.range(of: preparedBytes) != nil)
            #expect(String(decoding: body.prefix(512), as: UTF8.self).contains("audio/wav"))
            return .init(body: Data(#"{"text":"synthetic transcript"}"#.utf8))
        }
        let credential = SpeechCredential.relay(SpeechTokenResolver { _ in "synthetic-ticket" })
            .withRelayTransport(origin: fixture.url, pinnedPublicKeyHashes: [], optimizeUploads: true,
                prepare: { .init(request: $0) })
        #expect(try await OpenAIFileTranscriptionClient(credential: credential,
            endpoint: fixture.endpoint("/speechkit/v1/openai/v1/audio/transcriptions"),
            urlSession: fixture.session()).transcribeAudioFile(file: file) == "synthetic transcript")
        #expect(fixture.requests.count == 1)
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
                optimizeUploads: false, maxUploadBytes: cap, temporaryDirectory: directory)
        }
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
                optimizeUploads: true, maxUploadBytes: 5_120_043, temporaryDirectory: directory)
        }
        await #expect(throws: SpeechFailure(.audioTooLarge)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
                optimizeUploads: true, workLimits: .init(maxSourceBytes: cap), temporaryDirectory: directory)
        }
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
                optimizeUploads: true, maxDuration: 159, temporaryDirectory: directory)
        }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: ["nonzero-slack", "odd-ftyp", "unknown-table", "repeated-edits", "merged-samples"])
    @MainActor func workerMismatchesRejectLocallyOrPrepareAcceptedOutput(kind: String) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("adversarial.m4a")
        try await exportAudio(source, to: file)
        if kind == "merged-samples" {
            try Data(contentsOf: SpeechRelayMP4Tests.realFixture("merged-samples.m4a")).write(to: file)
        } else { try mutateMP4(file, kind: kind) }
        let original = try Data(contentsOf: file)
        #expect(throws: SpeechFailure(.unsupportedMediaType)) { try SpeechRelayMP4.duration(file) }
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected HTTP"); return .init() }
        let credential = SpeechCredential.relay(SpeechTokenResolver { _ in
            Issue.record("Unexpected credential resolution")
            return "synthetic"
        }).withRelayTransport(origin: fixture.url, pinnedPublicKeyHashes: [], optimizeUploads: false,
            prepare: { .init(request: $0) })
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            _ = try await OpenAIFileTranscriptionClient(credential: credential, endpoint: fixture.url,
                urlSession: fixture.session()).transcribeAudioFile(file: file)
        }
        #expect(fixture.requests.isEmpty)
        let relay = SpeechRelay(url: fixture.url, authentication: .bearer(SpeechTokenResolver { _ in
            Issue.record("Unexpected facade credential resolution")
            return "synthetic"
        }), optimizedUploads: .off)
        let service = SpeechService(urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        service.relay = relay
        service.relaySession = SpeechRelaySession(relay: relay, session: fixture.session(), attester: ContractAppAttest())
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            _ = try await service.transcribeAudioFile(provider: .openAI, file: file)
        }
        #expect(fixture.requests.isEmpty)
        await service.clearCredentials()
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, temporaryDirectory: directory)
        #expect(prepared.file != file)
        #expect(try Data(contentsOf: prepared.file) != original)
        if kind == "merged-samples" {
            #expect(prepared.file.pathExtension == "wav", "Invalid passthrough output must fall back to PCM conversion")
        }
        if prepared.file.pathExtension == "m4a" {
            #expect(try SpeechRelayMP4.duration(prepared.file) > 0)
        } else {
            #expect(try SpeechRelayWAV.validate(prepared.file).sampleRate == 16_000)
        }
        prepared.remove()
        #expect(try Data(contentsOf: file) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix("SpeechKit-import-") })
    }

    @Test func packedAACConversionCountsActualUnitsAndCleansUpOnLimit() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("packed.m4a")
        try Data(contentsOf: SpeechRelayMP4Tests.realFixture("merged-samples.m4a")).write(to: file)
        let original = try Data(contentsOf: file)
        await #expect(throws: SpeechFailure(.audioTooLong)) {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
                optimizeUploads: true, maxDuration: 1, temporaryDirectory: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [file.lastPathComponent])
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.file.pathExtension == "wav")
        let pcm = try AVAudioFile(forReading: prepared.file)
        #expect(Double(pcm.length) / pcm.processingFormat.sampleRate > 2)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: [true, false], [GeminiFileUploadStrategy.inline, .filesAPI])
    @MainActor func geminiClientAcceptsMP4(enabled: Bool, strategy: GeminiFileUploadStrategy) async throws {
        try await geminiAcceptsMP4(enabled: enabled, strategy: strategy, facade: false)
    }

    @Test(arguments: [true, false], [GeminiFileUploadStrategy.inline, .filesAPI])
    @MainActor func geminiFacadeAcceptsMP4(enabled: Bool, strategy: GeminiFileUploadStrategy) async throws {
        try await geminiAcceptsMP4(enabled: enabled, strategy: strategy, facade: true)
    }

    @Test(arguments: ["transcribe", "inline-request", "files-request"])
    func geminiRejectsUnsupportedSuffixBeforeCredentialResolution(entry: String) async throws {
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected HTTP"); return .init() }
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ in
            Issue.record("Unexpected credential resolution")
            return "synthetic"
        })
        let client = GeminiFileTranscriptionClient(credential: credential,
            endpoint: fixture.endpoint("/v1beta/interactions"), filesEndpoint: fixture.endpoint("/upload/v1beta/files"),
            urlSession: fixture.session())
        let file = fixture.url.appendingPathComponent("unsupported.caf")
        await #expect(throws: SpeechError.providerFailure(provider: .gemini, reason: .requestFailed)) {
            switch entry {
            case "transcribe": _ = try await client.transcribeAudioFile(file: file)
            case "inline-request": _ = try await client.makeRequest(file: file)
            default: _ = try await client.makeFilesAPIRequest(file: file)
            }
        }
        #expect(fixture.requests.isEmpty)
    }

    @MainActor private func geminiAcceptsMP4(enabled: Bool, strategy: GeminiFileUploadStrategy, facade: Bool) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("memo.mp4")
        try await exportAudio(source, to: file)
        let original = try Data(contentsOf: file)
        let fixture = SecurityHTTPFixture { request in
            let path = try #require(request.url).path
            if path.hasSuffix("/session") {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
            }
            if path.hasSuffix("/upload/v1beta/files") {
                #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type") == "audio/m4a")
                let origin = try #require(request.url?.host)
                return .init(headers: ["X-Goog-Upload-URL": "https://" + origin + "/speechkit/v1/gemini/upload-sessions/synthetic"])
            }
            if path.contains("/upload-sessions/") {
                #expect(request.httpBody == original)
                return .init(body: Data(#"{"file":{"name":"files/synthetic","uri":"synthetic-uri","mimeType":"audio/m4a","state":"ACTIVE"}}"#.utf8))
            }
            let bytes = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let input = try #require((body["input"] as? [[String: Any]])?.first)
            #expect(input["mime_type"] as? String == "audio/m4a")
            if strategy == .inline { #expect(input["data"] as? String == original.base64EncodedString()) }
            else { #expect(input["uri"] as? String == "synthetic-uri") }
            return .init(body: Data(#"{"status":"completed","steps":[{"content":[{"text":"synthetic transcript"}]}]}"#.utf8))
        }
        if facade {
            let relay = SpeechRelay(url: fixture.url, authentication: .none, optimizedUploads: enabled ? .on : .off)
            let service = SpeechService(gemini: GeminiConfiguration(uploadStrategy: strategy),
                urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
            service.relay = relay
            service.relaySession = SpeechRelaySession(relay: relay, session: fixture.session(), attester: ContractAppAttest())
            #expect(try await service.transcribeAudioFile(provider: .gemini, file: file) == "synthetic transcript")
            await service.clearCredentials()
        } else {
            let credential = SpeechCredential.relay(SpeechTokenResolver { _ in "synthetic-ticket" })
                .withRelayTransport(origin: fixture.url, pinnedPublicKeyHashes: [], optimizeUploads: enabled,
                    prepare: { .init(request: $0) })
            let client = GeminiFileTranscriptionClient(credential: credential,
                endpoint: fixture.endpoint("/speechkit/v1/gemini/v1beta/interactions"),
                filesEndpoint: fixture.endpoint("/speechkit/v1/gemini/upload/v1beta/files"), urlSession: fixture.session())
            #expect(try await client.transcribeAudioFile(file: file, options: .init(uploadStrategy: strategy)) == "synthetic transcript")
        }
        #expect(fixture.requests.count == (strategy == .inline ? 1 : 3) + (facade ? 1 : 0))
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: [SpeechFileTranscriptionProvider.openAI, .meta])
    func providerAcceptance(provider: SpeechFileTranscriptionProvider) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("memo.m4a")
        try await exportAudio(original, to: file)
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: provider,
            optimizeUploads: true, temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.file.pathExtension == (provider == .openAI ? "m4a" : "wav"))
        if provider == .meta {
            await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
                try await SpeechRelayAudioImport.prepare(file: file, provider: provider, optimizeUploads: false)
            }
        }
    }

    @Test(arguments: [kAudioFormatAppleLossless, kAudioFormatLinearPCM])
    func convertsALACAnd48kStereoWAV(codec: AudioFormatID) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try audio(in: directory, codec: codec, rate: 48_000)
        let original = try Data(contentsOf: file)
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .elevenLabs,
            optimizeUploads: true, temporaryDirectory: directory)
        defer { prepared.remove() }
        #expect(prepared.file.pathExtension == "flac")
        let format = try AVAudioFile(forReading: prepared.file).fileFormat
        #expect(format.sampleRate == 16_000 && format.channelCount == 1)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: [8000.0, 16000.0])
    func monoWAVPassesUnchanged(rate: Double) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try audio(in: directory, codec: kAudioFormatLinearPCM, rate: rate, channels: 1)
        let original = try Data(contentsOf: file)
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
            optimizeUploads: true, temporaryDirectory: directory)
        #expect(prepared.file == file && prepared.directory == nil)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: ["moov-last", "video", "alac", "meta"])
    func offRefusesBeforeCredentialOrHTTP(kind: String) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var file = try audio(in: directory, codec: kind == "alac" ? kAudioFormatAppleLossless : kAudioFormatMPEG4AAC)
        if kind == "video" {
            let target = directory.appendingPathComponent("video.mov")
            try await movie(audio: file, to: target, directory: directory)
            file = target
        } else if kind == "meta" {
            let target = directory.appendingPathComponent("fast.m4a")
            try await exportAudio(file, to: target)
            file = target
        }
        if kind == "moov-last" { try moveMoovLast(file) }
        let bytes = try Data(contentsOf: file)
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unexpected HTTP"); return .init() }
        let credential = SpeechCredential.relay(SpeechTokenResolver { _ in
            Issue.record("Unexpected credential resolution")
            return "synthetic"
        }).withRelayTransport(origin: fixture.url, pinnedPublicKeyHashes: [], optimizeUploads: false,
            prepare: { .init(request: $0) })
        await #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            if kind == "meta" {
                _ = try await MetaFileTranscriptionClient(credential: credential, endpoint: fixture.url,
                    urlSession: fixture.session()).transcribeAudioFile(file: file)
            } else {
                _ = try await OpenAIFileTranscriptionClient(credential: credential, endpoint: fixture.url,
                    urlSession: fixture.session()).transcribeAudioFile(file: file)
            }
        }
        #expect(fixture.requests.isEmpty)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix("SpeechKit-import-") })
    }

    @Test func canonicalMultipartNameAndMIMEWithoutCopy() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try audio(in: directory, codec: kAudioFormatMPEG4AAC)
        let file = directory.appendingPathComponent("personal-filename.mp4")
        try await exportAudio(original, to: file)
        let bytes = try Data(contentsOf: file)
        let fixture = SecurityHTTPFixture { request in
            let body = request.httpBody ?? Data()
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains("filename=\"audio.m4a\""))
            #expect(text.contains("Content-Type: audio/mp4"))
            #expect(body.range(of: bytes) != nil)
            return .init(body: Data("{\"text\":\"ok\"}".utf8))
        }
        let credential = SpeechCredential.relay(SpeechTokenResolver { _ in "synthetic" })
            .withRelayTransport(origin: fixture.url, pinnedPublicKeyHashes: [], optimizeUploads: false,
                prepare: { .init(request: $0) })
        let result = try await OpenAIFileTranscriptionClient(credential: credential,
            endpoint: fixture.endpoint("/speechkit/v1/proxy/openai/v1/audio/transcriptions"),
            urlSession: fixture.session()).transcribeAudioFile(file: file)
        #expect(result == "ok")
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func cancelledRepackageCleansDirectoryAndPreservesOriginal() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try audio(in: directory, codec: kAudioFormatMPEG4AAC, seconds: 30)
        try moveMoovLast(file)
        let original = try Data(contentsOf: file)
        let task = Task {
            try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI,
                optimizeUploads: true, temporaryDirectory: directory)
        }
        for _ in 0..<10_000 {
            if try FileManager.default.contentsOfDirectory(atPath: directory.path).count > 1 { break }
            await Task.yield()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [file.lastPathComponent])
        #expect(try Data(contentsOf: file) == original)
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func audio(in directory: URL, codec: AudioFormatID, rate: Double = 44_100,
                       channels: AVAudioChannelCount = 2, seconds: Int = 1) throws -> URL {
        let file = directory.appendingPathComponent("source." + (codec == kAudioFormatLinearPCM ? "wav" : "m4a"))
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(channels) {
            let samples = try #require(buffer.floatChannelData)[channel]
            for index in 0..<Int(buffer.frameLength) { samples[index] = sin(Float(index) * 0.06) * 0.2 }
        }
        var settings: [String: Any] = [AVFormatIDKey: codec, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels]
        if codec == kAudioFormatMPEG4AAC { settings[AVEncoderBitRateKey] = 64_000 }
        if codec == kAudioFormatAppleLossless { settings[AVEncoderBitDepthHintKey] = 16 }
        if codec == kAudioFormatLinearPCM {
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
        }
        do {
            let writer = try AVAudioFile(forWriting: file, settings: settings)
            for _ in 0..<seconds { try writer.write(from: buffer) }
        }
        return file
    }

    private func exportAudio(_ source: URL, to output: URL, type: AVFileType = .m4a) async throws {
        let exporter = try #require(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: output, as: type)
    }

    private func aacPackets(_ file: URL) async throws -> Data {
        let asset = AVURLAsset(url: file)
        defer { withExtendedLifetime(asset) {} }
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        try #require(reader.startReading())
        var result = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                #expect(CMSampleBufferGetTotalSampleSize(sample) == 0)
                continue
            }
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            try #require(status == kCMBlockBufferNoErr)
            result.append(bytes)
        }
        try #require(reader.status == .completed)
        #expect(!result.isEmpty)
        return result
    }

    private func movie(audio: URL, to output: URL, directory: URL) async throws {
        let video = directory.appendingPathComponent("silent.mov")
        let writer = try AVAssetWriter(outputURL: video, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess)
        let buffer = try #require(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<2 {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed, "Video fixture writer failed: \(String(describing: writer.error))")
        let composition = AVMutableComposition()
        var assets = [AVURLAsset]()
        defer { withExtendedLifetime(assets) {} }
        for (source, type) in [(video, AVMediaType.video), (audio, AVMediaType.audio)] {
            let asset = AVURLAsset(url: source)
            assets.append(asset)
            let track = try #require(try await asset.loadTracks(withMediaType: type).first)
            let target = try #require(composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid))
            try target.insertTimeRange(try await track.load(.timeRange), of: track, at: .zero)
        }
        let exporter = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: output, as: .mov)
    }

    private func mutateMP4(_ file: URL, kind: String) throws {
        let original = try Data(contentsOf: file)
        func number(_ value: UInt64, width: Int = 4) -> Data {
            Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ((width - 1 - $0) * 8)) })
        }
        func integer(_ bytes: Data, _ offset: Int, _ width: Int = 4) -> Int {
            bytes[offset..<offset + width].reduce(0) { $0 << 8 | Int($1) }
        }
        func box(_ type: String, _ content: Data) -> Data {
            number(UInt64(content.count + 8)) + Data(type.utf8) + content
        }
        func rewrite(_ bytes: Data, delta: Int) throws -> Data {
            var result = Data()
            var offset = 0
            while offset < bytes.count {
                let short = integer(bytes, offset)
                let header = short == 1 ? 16 : 8
                let size = short == 1 ? integer(bytes, offset + 8, 8) : short == 0 ? bytes.count - offset : short
                let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
                var content = bytes.subdata(in: offset + header..<offset + size)
                if ["moov", "trak", "mdia", "minf", "stbl"].contains(type) {
                    content = try rewrite(content, delta: delta)
                }
                if type == "edts", kind == "repeated-edits" { offset += size; continue }
                if type == "stco" || type == "co64" {
                    let width = type == "co64" ? 8 : 4
                    for index in 0..<integer(content, 4) {
                        let start = 8 + index * width
                        let value = integer(content, start, width)
                        content.replaceSubrange(start..<start + width, with: number(UInt64(value + delta), width: width))
                    }
                }
                if type == "stbl", kind == "unknown-table" { content += box("zzzz", Data()) }
                if type == "ftyp", kind == "odd-ftyp" { content.append(0) }
                if type == "mdat", kind == "nonzero-slack" { content += Data([0x21, 0x10, 0x49, 0x90]) }
                if type == "trak", kind == "repeated-edits" {
                    let entry = number(100) + number(0) + number(0x0001_0000)
                    content += box("edts", box("elst", number(0) + number(2) + entry + entry))
                }
                result += box(type, content)
                offset += size
            }
            return result
        }
        func mediaStart(_ bytes: Data) throws -> Int {
            var offset = 0
            while offset < bytes.count {
                let size = integer(bytes, offset)
                let header = size == 1 ? 16 : 8
                if String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self) == "mdat" { return offset + header }
                offset += size == 1 ? integer(bytes, offset + 8, 8) : size
            }
            throw SpeechFailure(.unsupportedMediaType)
        }
        let delta = try mediaStart(rewrite(original, delta: 0)) - mediaStart(original)
        try rewrite(original, delta: delta).write(to: file)
    }

    private func moveMoovLast(_ file: URL) throws {
        var data = try Data(contentsOf: file)
        func integer(_ offset: Int, _ width: Int) -> Int {
            data[offset..<offset + width].reduce(0) { $0 << 8 | Int($1) }
        }
        var moov: Range<Int>?
        var offset = 0
        while offset + 8 <= data.count {
            let small = integer(offset, 4)
            let size = small == 1 ? integer(offset + 8, 8) : small
            if String(decoding: data[offset + 4..<offset + 8], as: UTF8.self) == "moov" { moov = offset..<offset + size; break }
            offset += size
        }
        let range = try #require(moov)
        let originalRange = range
        func adjust(_ range: Range<Int>) throws {
            var offset = range.lowerBound
            while offset < range.upperBound {
                let size = integer(offset, 4)
                try #require(size >= 8 && size <= range.upperBound - offset)
                let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
                if ["moov", "trak", "mdia", "minf", "stbl"].contains(type) {
                    try adjust(offset + 8..<offset + size)
                } else if type == "stco" || type == "co64" {
                    let width = type == "co64" ? 8 : 4
                    for index in 0..<integer(offset + 12, 4) {
                        let start = offset + 16 + index * width
                        let value = integer(start, width)
                        let shifted = value >= originalRange.upperBound ? value - originalRange.count : value
                        for byte in 0..<width { data[start + byte] = UInt8(truncatingIfNeeded: shifted >> ((width - 1 - byte) * 8)) }
                    }
                }
                offset += size
            }
        }
        try adjust(range)
        let header = data.subdata(in: range)
        data.removeSubrange(range)
        data.append(header)
        try data.write(to: file)
    }
}
