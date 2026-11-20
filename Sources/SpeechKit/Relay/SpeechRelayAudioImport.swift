import AVFoundation
import Foundation

enum SpeechRelayAudioContainer: Sendable, Hashable {
    case wav, flac, ogg, mp3, mp4, mov, aac, aiff, webm, caf, unknown

    var fileExtension: String? {
        switch self {
        case .wav: "wav"
        case .flac: "flac"
        case .ogg: "ogg"
        case .mp3: "mp3"
        case .mp4: "m4a"
        default: nil
        }
    }

    static func detect(_ data: Data) -> Self {
        let bytes = [UInt8](data)
        func matches(_ text: String, at offset: Int = 0) -> Bool {
            let signature = Array(text.utf8)
            return bytes.count >= offset + signature.count && Array(bytes[offset..<offset + signature.count]) == signature
        }
        if matches("RIFF"), matches("WAVE", at: 8) {
            var offset = 12
            while offset + 24 <= bytes.count {
                let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
                if matches("fmt ", at: offset), size >= 16 {
                    let format = Int(bytes[offset + 8]) | Int(bytes[offset + 9]) << 8
                    if format == 1 || format == 3 { return .wav }
                    if format == 0xfffe, size >= 40, offset + 48 <= bytes.count,
                       [1, 3].contains(bytes[offset + 32]), bytes[offset + 33] == 0 { return .wav }
                    return .unknown
                }
                offset += 8 + size + size % 2
            }
            return .unknown
        }
        if matches("fLaC") { return .flac }
        if matches("OggS"), bytes.count > 27, bytes[4] == 0, bytes[5] & 2 != 0 {
            let payload = 27 + Int(bytes[26])
            if matches("OpusHead", at: payload) || matches("\u{01}vorbis", at: payload) { return .ogg }
        }
        if matches("ftyp", at: 4) { return matches("qt  ", at: 8) ? .mov : .mp4 }
        if matches("moov", at: 4) || matches("wide", at: 4) || matches("mdat", at: 4) { return .mov }
        if matches("FORM"), matches("AIFF", at: 8) || matches("AIFC", at: 8) { return .aiff }
        if matches("caff") { return .caf }
        if bytes.starts(with: [0x1a, 0x45, 0xdf, 0xa3]) { return .webm }
        var offset = 0
        if matches("ID3"), bytes.count >= 10 {
            guard bytes[6...9].allSatisfy({ $0 < 128 }) else { return .unknown }
            offset = 10 + ((Int(bytes[6]) << 21) | (Int(bytes[7]) << 14) | (Int(bytes[8]) << 7) | Int(bytes[9]))
        }
        if bytes.count >= offset + 4, bytes[offset] == 0xff {
            let flags = bytes[offset + 1]
            let rates = bytes[offset + 2]
            if flags & 0xe0 == 0xe0, flags & 0x18 != 0x08, flags & 0x06 == 0x02,
               rates >> 4 != 0, rates >> 4 != 15, rates & 0x0c != 0x0c { return .mp3 }
            if flags & 0xf6 == 0xf0 { return .aac }
        }
        return .unknown
    }

    static func read(_ file: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 65_536) ?? Data()
        if header.starts(with: Data("ID3".utf8)), header.count >= 10,
           header[6...9].allSatisfy({ $0 < 128 }) {
            let size = (UInt64(header[6]) << 21) | (UInt64(header[7]) << 14) | (UInt64(header[8]) << 7) | UInt64(header[9])
            let footer: UInt64 = header[5] & 0x10 != 0 ? 10 : 0
            try handle.seek(toOffset: 10 + size + footer)
            return detect(try handle.read(upToCount: 4) ?? Data())
        }
        return detect(header)
    }
}

struct SpeechRelayPreparedAudio: Sendable {
    let file: URL
    let directory: URL?
    let wrappedRawPCM: Bool

    func remove() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

enum SpeechRelayAudioImport {
    struct RawPCM: Sendable {
        let sampleRate: Int
    }

    struct WorkLimits: Sendable {
        let maxFrames: Int64
        let maxOutputBytes: Int64
        let maxSourceBytes: Int64

        init(maxFrames: Int64 = 16_000 * 3600, maxOutputBytes: Int64 = 128 * 1024 * 1024,
             maxSourceBytes: Int64 = 512 * 1024 * 1024) {
            self.maxFrames = max(0, min(maxFrames, 16_000 * 3600))
            self.maxOutputBytes = max(0, min(maxOutputBytes, 128 * 1024 * 1024))
            self.maxSourceBytes = max(0, min(maxSourceBytes, 512 * 1024 * 1024))
        }
    }

    static func prepare(file: URL, provider: SpeechFileTranscriptionProvider,
                        optimizeUploads: Bool?, rawPCM: RawPCM? = nil,
                        maxUploadBytes: Int64? = nil, maxDuration: TimeInterval? = nil,
                        workLimits: WorkLimits = WorkLimits(),
                        temporaryDirectory: URL = FileManager.default.temporaryDirectory) async throws -> SpeechRelayPreparedAudio {
        guard let optimizeUploads else { return SpeechRelayPreparedAudio(file: file, directory: nil, wrappedRawPCM: false) }
        let worker = Task.detached {
            do {
                return try await prepareLocally(file: file, provider: provider, optimizeUploads: optimizeUploads, rawPCM: rawPCM,
                    maxUploadBytes: min(maxUploadBytes ?? Int64.max, workLimits.maxOutputBytes),
                    maxDuration: min(maxDuration ?? .infinity, Double(workLimits.maxFrames) / 16_000),
                    workLimits: workLimits, temporaryDirectory: temporaryDirectory)
            } catch is CancellationError { throw CancellationError() }
            catch let failure as SpeechFailure { throw failure }
            catch { throw SpeechFailure(.audioNormalizationFailed) }
        }
        return try await withTaskCancellationHandler {
            let prepared = try await worker.value
            if Task.isCancelled {
                prepared.remove()
                throw CancellationError()
            }
            return prepared
        } onCancel: { worker.cancel() }
    }

    private static func prepareLocally(file: URL, provider: SpeechFileTranscriptionProvider,
        optimizeUploads: Bool, rawPCM: RawPCM?, maxUploadBytes: Int64?,
        maxDuration: TimeInterval?, workLimits: WorkLimits, temporaryDirectory: URL) async throws -> SpeechRelayPreparedAudio {
        try Task.checkCancellation()
        try validateSize(file, limit: workLimits.maxSourceBytes)
        let container = try SpeechRelayAudioContainer.read(file)
        var accepted: Set<SpeechRelayAudioContainer> = switch provider {
        case .openAI: [.wav, .mp3]
        case .meta: [.wav]
        default: [.wav, .flac, .ogg, .mp3]
        }
        if acceptsM4A(provider) { accepted.insert(.mp4) }
        var meterable = rawPCM == nil && accepted.contains(container)
        var optimizeWAV = false
        var invalidMP4 = false
        if meterable, container == .mp4 {
            do {
                // Includes bounded, per-sample AAC validation before credentials or network I/O.
                let duration = try SpeechRelayMP4.duration(file)
                if let maxDuration, duration > maxDuration { throw SpeechFailure(.audioTooLong) }
            } catch let failure as SpeechFailure where failure.category == .unsupportedMediaType {
                meterable = false
                invalidMP4 = true
            }
            if file.pathExtension.lowercased() == "mov" { meterable = false }
        }
        if meterable, container == .wav {
            let format = try SpeechRelayWAV.validate(file)
            optimizeWAV = optimizeUploads && (format.sampleRate > 16_000 || format.channels > 1)
        }
        if meterable, !optimizeWAV,
           extensionMatches(file.pathExtension.lowercased(), container: container) {
            try validateSize(file, limit: maxUploadBytes)
            if container == .wav { try SpeechRelayWAV.validate(file) }
            if let maxDuration {
                try validateDuration(file, limit: maxDuration)
            }
            try Task.checkCancellation()
            return SpeechRelayPreparedAudio(file: file, directory: nil, wrappedRawPCM: false)
        }
        guard optimizeUploads else { throw SpeechFailure(.unsupportedMediaType) }
        let directory = temporaryDirectory.appendingPathComponent("SpeechKit-import-" + UUID().uuidString, isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS) || os(watchOS) || os(visionOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: attributes)
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: directory) } }
        let output: URL
        if meterable, !optimizeWAV, let suffix = container.fileExtension {
            output = directory.appendingPathComponent("audio." + suffix)
            try copy(file, to: output, limit: maxUploadBytes)
            if container == .wav { try SpeechRelayWAV.validate(output) }
            if let maxDuration { try validateDuration(output, limit: maxDuration) }
        } else if rawPCM == nil, acceptsM4A(provider),
                  container == .mp4 || container == .mov || file.pathExtension.lowercased() == "mov",
                  let repackaged = try await repackage(file, directory: directory, maxUploadBytes: maxUploadBytes,
                      maxDuration: maxDuration, workLimits: workLimits) {
            output = repackaged
        } else {
            let conversionFile = rawPCM == nil && invalidMP4
                ? try unpackAACForConversion(file, directory: directory, maxDuration: maxDuration, workLimits: workLimits) : file
            let reader = try Reader(file: conversionFile, rawPCM: rawPCM)
            let duration = Double(reader.length) / reader.format.sampleRate
            guard duration.isFinite, duration > 0 else { throw SpeechFailure(.audioNormalizationFailed) }
            guard duration <= Double(workLimits.maxFrames) / 16_000 else { throw SpeechFailure(.audioTooLong) }
            if let maxDuration, duration > maxDuration { throw SpeechFailure(.audioTooLong) }
            let allowsFLAC = provider != .openAI && provider != .meta && rawPCM == nil
            do {
                output = try convert(reader, directory: directory, allowsFLAC: allowsFLAC,
                    maxUploadBytes: maxUploadBytes, maxDuration: maxDuration, workLimits: workLimits)
            } catch {
                try Task.checkCancellation()
                if let failure = error as? SpeechFailure, failure.category != .audioNormalizationFailed { throw failure }
                guard allowsFLAC else { throw error }
                let flac = directory.appendingPathComponent("audio.flac")
                if FileManager.default.fileExists(atPath: flac.path) { try FileManager.default.removeItem(at: flac) }
                output = try convert(Reader(file: conversionFile, rawPCM: rawPCM), directory: directory, allowsFLAC: false,
                    maxUploadBytes: maxUploadBytes, maxDuration: maxDuration, workLimits: workLimits)
            }
        }
        try Task.checkCancellation()
        try validateSize(output, limit: maxUploadBytes)
        keep = true
        return SpeechRelayPreparedAudio(file: output, directory: directory, wrappedRawPCM: rawPCM != nil)
    }

    private static func extensionMatches(_ suffix: String, container: SpeechRelayAudioContainer) -> Bool {
        if container == .mp3 { return ["mp3", "mpeg", "mpga"].contains(suffix) }
        if container == .mp4 { return ["m4a", "mp4"].contains(suffix) }
        return suffix == container.fileExtension
    }

    static func acceptsM4A(_ provider: SpeechFileTranscriptionProvider) -> Bool {
        switch provider {
        // https://developers.openai.com/api/docs/guides/speech-to-text
        case .openAI: true
        // https://elevenlabs.io/docs/overview/capabilities/speech-to-text
        case .elevenLabs: true
        // https://docs.x.ai/developers/model-capabilities/audio/speech-to-text
        case .grok: true
        // https://docs.mistral.ai/studio/audio/specs-and-limits/audio-formats (M4A not verified)
        case .mistral: false
        // https://aquavoice.com/docs/api
        case .aqua: true
        // https://ai.google.dev/gemini-api/docs/audio
        case .gemini: true
        // https://docs.fish.audio/features/speech-to-text
        case .fishAudio: true
        // https://docs.cohere.com/reference/create-audio-transcription (M4A not verified)
        case .cohere: false
        // https://dev.meta.ai/docs/speech-to-text/ (WAV-only client)
        case .meta: false
        #if os(iOS) || os(macOS) || os(visionOS)
        case .apple: false
        #endif
        }
    }

    private static func repackage(_ file: URL, directory: URL, maxUploadBytes: Int64?,
                                  maxDuration: TimeInterval?, workLimits: WorkLimits) async throws -> URL? {
        #if os(watchOS)
        return nil
        #else
        let output = directory.appendingPathComponent("audio.m4a")
        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: file)
            defer { withExtendedLifetime(asset) {} }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceTrack = tracks.first else { return nil }
            let descriptions = try await sourceTrack.load(.formatDescriptions)
            guard descriptions.count == 1,
                  [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2]
                    .contains(CMFormatDescriptionGetMediaSubType(descriptions[0])) else { return nil }
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            let timeRange = try await sourceTrack.load(.timeRange)
            let duration = timeRange.duration.seconds
            guard duration.isFinite, duration > 0 else { return nil }
            guard duration <= Double(workLimits.maxFrames) / 16_000 else { throw SpeechFailure(.audioTooLong) }
            if let maxDuration, duration > maxDuration { throw SpeechFailure(.audioTooLong) }
            try track.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { return nil }
            exporter.shouldOptimizeForNetworkUse = true
            try await exporter.export(to: output, as: .m4a)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            try Task.checkCancellation()
            try validateSize(output, limit: maxUploadBytes)
            try validateSize(output, limit: workLimits.maxOutputBytes)
            // Passthrough exporters can preserve invalid sample packing. Validate
            // their output too; rejection returns nil and selects PCM conversion.
            let meteredDuration = try SpeechRelayMP4.duration(output)
            guard meteredDuration <= Double(workLimits.maxFrames) / 16_000 else { throw SpeechFailure(.audioTooLong) }
            if let maxDuration, meteredDuration > maxDuration { throw SpeechFailure(.audioTooLong) }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            try Task.checkCancellation()
            if let failure = error as? SpeechFailure,
               [.audioTooLarge, .audioTooLong].contains(failure.category) { throw failure }
            return nil
        }
        #endif
    }

    private static func unpackAACForConversion(_ file: URL, directory: URL, maxDuration: TimeInterval?,
                                              workLimits: WorkLimits) throws -> URL {
        let unpacked = directory.appendingPathComponent("conversion-input.aac")
        try createProtectedFile(unpacked)
        do {
            let output = try FileHandle(forWritingTo: unpacked)
            defer { try? output.close() }
            let packed = try SpeechRelayMP4.unpackForConversion(file, output: output,
                maximumDuration: min(maxDuration ?? .infinity, Double(workLimits.maxFrames) / 16_000),
                maximumBytes: min(workLimits.maxSourceBytes, workLimits.maxOutputBytes))
            if packed { return unpacked }
            try FileManager.default.removeItem(at: unpacked)
            return file
        } catch {
            try? FileManager.default.removeItem(at: unpacked)
            try Task.checkCancellation()
            if let failure = error as? SpeechFailure,
               [.audioTooLong, .audioTooLarge].contains(failure.category) { throw failure }
            return file
        }
    }

    private static func createProtectedFile(_ file: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS) || os(watchOS) || os(visionOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        guard FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: attributes) else {
            throw SpeechFailure(.audioNormalizationFailed)
        }
        #if os(iOS) || os(watchOS) || os(visionOS)
        try Data().write(to: file, options: .completeFileProtection)
        #endif
    }

    private static func copy(_ source: URL, to destination: URL, limit: Int64?) throws {
        try validateSize(source, limit: limit)
        try createProtectedFile(destination)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: 65_536) ?? Data()
            if data.isEmpty { break }
            total += Int64(data.count)
            if let limit, total > limit { throw SpeechFailure(.audioTooLarge) }
            try output.write(contentsOf: data)
        }
    }

    private static func validateSize(_ file: URL, limit: Int64?) throws {
        if let limit, try size(file) > limit { throw SpeechFailure(.audioTooLarge) }
    }

    private static func size(_ file: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let value = attributes[.size] as? NSNumber else { throw SpeechFailure(.audioNormalizationFailed) }
        return value.int64Value
    }

    private static func validateDuration(_ file: URL, limit: TimeInterval) throws {
        guard let audio = try? AVAudioFile(forReading: file) else { return }
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw SpeechFailure(.audioNormalizationFailed) }
        if duration > limit { throw SpeechFailure(.audioTooLong) }
    }

    private static func convert(_ reader: Reader, directory: URL, allowsFLAC: Bool,
        maxUploadBytes: Int64?, maxDuration: TimeInterval?, workLimits: WorkLimits) throws -> URL {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let converter = AVAudioConverter(from: reader.format, to: format),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw SpeechFailure(.audioNormalizationFailed)
        }
        converter.downmix = true
        let wav = directory.appendingPathComponent("audio.wav")
        let flac = directory.appendingPathComponent("audio.flac")
        var file: AVAudioFile?
        var wave: SpeechRelayWAV.Writer?
        var output = wav
        if allowsFLAC {
            try createProtectedFile(flac)
            file = try? AVAudioFile(forWriting: flac, settings: [AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16],
                commonFormat: .pcmFormatFloat32, interleaved: false)
            if file != nil { output = flac }
            else { try FileManager.default.removeItem(at: flac) }
        }
        if file == nil {
            let estimatedBytes = ceil(Double(reader.length) / reader.format.sampleRate * 16_000) * 2 + 44
            if estimatedBytes > Double(maxUploadBytes ?? Int64(UInt32.max)) { throw SpeechFailure(.audioTooLarge) }
            try createProtectedFile(wav)
            wave = try SpeechRelayWAV.Writer(file: wav)
        }
        var frames: Int64 = 0
        let maximumInputDuration = min(Double(workLimits.maxFrames) / 16_000, maxDuration ?? .infinity)
        while true {
            try Task.checkCancellation()
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { count, state in
                let input = reader.nextBuffer(count, maximumDuration: maximumInputDuration)
                state.pointee = input == nil ? .endOfStream : .haveData
                return input
            }
            if let error = reader.error { throw error }
            guard status != .error, error == nil else { throw SpeechFailure(.audioNormalizationFailed) }
            frames += Int64(buffer.frameLength)
            guard frames <= workLimits.maxFrames else { throw SpeechFailure(.audioTooLong) }
            if let maxDuration, Double(frames) / 16_000 > maxDuration { throw SpeechFailure(.audioTooLong) }
            guard frames * 2 + 44 <= workLimits.maxOutputBytes else { throw SpeechFailure(.audioTooLarge) }
            if wave != nil, frames * 2 + 44 > (maxUploadBytes ?? Int64.max) { throw SpeechFailure(.audioTooLarge) }
            if buffer.frameLength > 0 {
                try file?.write(from: buffer)
                try wave?.write(buffer)
            }
            try validateSize(output, limit: maxUploadBytes)
            if status == .endOfStream { break }
            if buffer.frameLength == 0 { throw SpeechFailure(.audioNormalizationFailed) }
        }
        file = nil
        try wave?.finish()
        try Task.checkCancellation()
        try validateSize(output, limit: maxUploadBytes)
        if output == wav { try SpeechRelayWAV.validate(output) }
        let validation = try AVAudioFile(forReading: output)
        guard frames > 0, validation.length == frames, validation.fileFormat.sampleRate == 16_000,
              validation.fileFormat.channelCount == 1,
              try SpeechRelayAudioContainer.read(output) == (output == flac ? .flac : .wav) else {
            throw SpeechFailure(.audioNormalizationFailed)
        }
        return output
    }

    // AVAudioConverter's synchronous input block is @Sendable on older SDKs.
    // The lock serializes file reads, frame accounting, and error access.
    private final class Reader: @unchecked Sendable {
        let format: AVAudioFormat
        let length: AVAudioFramePosition
        private let audio: AVAudioFile?
        private let raw: FileHandle?
        private let lock = NSLock()
        private var inputFrames: Int64 = 0
        private var readError: Error?

        var error: Error? { lock.withLock { readError } }

        init(file: URL, rawPCM: RawPCM?) throws {
            if let rawPCM {
                guard [8000, 16000, 22050, 24000, 44100, 48000].contains(rawPCM.sampleRate),
                      let format = AVAudioFormat(standardFormatWithSampleRate: Double(rawPCM.sampleRate), channels: 1) else {
                    throw SpeechFailure(.unsupportedMediaType)
                }
                let bytes = try SpeechRelayAudioImport.size(file)
                guard bytes > 0, bytes % 2 == 0 else { throw SpeechFailure(.audioNormalizationFailed) }
                self.format = format
                length = bytes / 2
                raw = try FileHandle(forReadingFrom: file)
                audio = nil
            } else {
                let audio = try AVAudioFile(forReading: file)
                self.audio = audio
                format = audio.processingFormat
                guard format.sampleRate.isFinite, (1...768_000).contains(format.sampleRate),
                      (1...8).contains(format.channelCount) else { throw SpeechFailure(.unsupportedMediaType) }
                length = audio.length
                raw = nil
            }
        }

        deinit { try? raw?.close() }

        func nextBuffer(_ count: AVAudioFrameCount, maximumDuration: TimeInterval) -> AVAudioPCMBuffer? {
            lock.withLock {
                guard readError == nil else { return nil }
                do {
                    try Task.checkCancellation()
                    let buffer = try read(min(count, 8192))
                    inputFrames += Int64(buffer.frameLength)
                    if Double(inputFrames) / format.sampleRate > maximumDuration {
                        throw SpeechFailure(.audioTooLong)
                    }
                    return buffer.frameLength == 0 ? nil : buffer
                } catch {
                    readError = error
                    return nil
                }
            }
        }

        private func read(_ count: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw SpeechFailure(.audioNormalizationFailed)
            }
            if let audio {
                let remaining = audio.length - audio.framePosition
                if remaining > 0 {
                    try audio.read(into: buffer, frameCount: AVAudioFrameCount(min(remaining, Int64(count))))
                }
            } else if let raw, let samples = buffer.floatChannelData?[0] {
                let bytes = [UInt8](try raw.read(upToCount: Int(count) * 2) ?? Data())
                guard bytes.count % 2 == 0 else { throw SpeechFailure(.audioNormalizationFailed) }
                buffer.frameLength = AVAudioFrameCount(bytes.count / 2)
                for index in 0..<Int(buffer.frameLength) {
                    samples[index] = Float(Int16(bitPattern: UInt16(bytes[index * 2]) | UInt16(bytes[index * 2 + 1]) << 8)) / 32768
                }
            }
            return buffer
        }
    }
}

extension SpeechCredential {
    func uploadFileURL(_ file: URL) -> URL {
        if kind == .relay, ["m4a", "mp4"].contains(file.pathExtension.lowercased()) {
            return URL(fileURLWithPath: "audio.m4a")
        }
        return file
    }
}
