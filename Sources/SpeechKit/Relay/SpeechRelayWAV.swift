import AVFoundation
import Foundation

enum SpeechRelayWAV {
    struct Format {
        let sampleRate: UInt32
        let channels: UInt32
    }

    @discardableResult
    static func validate(_ file: URL) throws -> Format {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let length = try input.seekToEnd()
        try input.seek(toOffset: 0)
        let header = try read(input, count: 12)
        guard tag(header, at: 0) == "RIFF", tag(header, at: 8) == "WAVE",
              UInt64(uint32(header, at: 4)) + 8 == length else {
            throw SpeechFailure(.unsupportedMediaType)
        }
        var offset: UInt64 = 12
        var alignment: UInt32 = 0
        var result: Format?
        var hasData = false
        while offset < length {
            try Task.checkCancellation()
            guard length - offset >= 8 else { throw SpeechFailure(.unsupportedMediaType) }
            try input.seek(toOffset: offset)
            let chunk = try read(input, count: 8)
            let name = tag(chunk, at: 0)
            let size = uint32(chunk, at: 4)
            let extent = UInt64(size) + UInt64(size & 1) + 8
            guard extent <= length - offset else { throw SpeechFailure(.unsupportedMediaType) }
            switch name {
            case "fmt ":
                guard alignment == 0, [16, 18, 40].contains(size) else { throw SpeechFailure(.unsupportedMediaType) }
                let format = try read(input, count: Int(size))
                let encoding = uint16(format, at: 0)
                let channels = uint16(format, at: 2)
                let rate = uint32(format, at: 4)
                result = Format(sampleRate: rate, channels: channels)
                let depth = uint16(format, at: 14)
                guard [1, 3, 65534].contains(encoding), (1...8).contains(channels),
                      (1...768_000).contains(rate), [8, 16, 24, 32, 64].contains(depth),
                      encoding != 3 || [32, 64].contains(depth),
                      size != 18 || uint16(format, at: 16) == 0,
                      size != 40 || encoding == 65534 else { throw SpeechFailure(.unsupportedMediaType) }
                if encoding == 65534 {
                    guard size == 40, uint16(format, at: 16) == 22,
                          uint16(format, at: 18) == depth, uint16(format, at: 24) == 1,
                          Array(format[26..<40]) == [0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113] else {
                        throw SpeechFailure(.unsupportedMediaType)
                    }
                }
                alignment = UInt32(channels) * UInt32(depth) / 8
                guard uint16(format, at: 12) == alignment,
                      uint32(format, at: 8) == rate * alignment else { throw SpeechFailure(.unsupportedMediaType) }
            case "data":
                guard alignment > 0, !hasData, size > 0, size % alignment == 0 else {
                    throw SpeechFailure(.unsupportedMediaType)
                }
                hasData = true
            case "LIST":
                guard size >= 4, tag(try read(input, count: 4), at: 0) == "INFO" else {
                    throw SpeechFailure(.unsupportedMediaType)
                }
            case "FLLR":
                guard size <= 4096 else { throw SpeechFailure(.unsupportedMediaType) }
            case "JUNK", "bext", "fact", "iXML", "PAD ": break
            default: throw SpeechFailure(.unsupportedMediaType)
            }
            offset += extent
        }
        guard hasData, let result else { throw SpeechFailure(.unsupportedMediaType) }
        return result
    }

    private static func read(_ input: FileHandle, count: Int) throws -> Data {
        let data = try input.read(upToCount: count) ?? Data()
        guard data.count == count else { throw SpeechFailure(.unsupportedMediaType) }
        return data
    }

    private static func tag(_ data: Data, at offset: Int) -> String {
        String(decoding: data[offset..<offset + 4], as: UTF8.self)
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        uint16(data, at: offset) | uint16(data, at: offset + 2) << 16
    }

    final class Writer {
        private let output: FileHandle
        private var bytes: UInt32 = 0

        init(file: URL) throws {
            output = try FileHandle(forWritingTo: file)
            try output.write(contentsOf: Self.header(bytes: 0))
        }

        deinit { try? output.close() }

        func write(_ buffer: AVAudioPCMBuffer) throws {
            guard let samples = buffer.floatChannelData?[0] else { throw SpeechFailure(.audioNormalizationFailed) }
            let count = Int(buffer.frameLength)
            guard UInt64(bytes) + UInt64(count) * 2 <= UInt32.max - 36 else { throw SpeechFailure(.audioTooLarge) }
            var pcm = Data(capacity: count * 2)
            for index in 0..<count {
                let sample = samples[index]
                guard sample.isFinite else { throw SpeechFailure(.audioNormalizationFailed) }
                let value = Int16(max(-32768, min(32767, (sample * 32768).rounded())))
                let bits = UInt16(bitPattern: value)
                pcm.append(UInt8(truncatingIfNeeded: bits))
                pcm.append(UInt8(truncatingIfNeeded: bits >> 8))
            }
            try output.write(contentsOf: pcm)
            bytes += UInt32(pcm.count)
        }

        func finish() throws {
            try output.seek(toOffset: 0)
            try output.write(contentsOf: Self.header(bytes: bytes))
            try output.close()
        }

        private static func header(bytes: UInt32) -> Data {
            var header = Data("RIFF".utf8)
            func append(_ value: UInt32, width: Int = 4) {
                for offset in 0..<width { header.append(UInt8(truncatingIfNeeded: value >> (offset * 8))) }
            }
            append(bytes + 36)
            header.append(Data("WAVEfmt ".utf8))
            append(16)
            append(1, width: 2)
            append(1, width: 2)
            append(16_000)
            append(32_000)
            append(2, width: 2)
            append(16, width: 2)
            header.append(Data("data".utf8))
            append(bytes)
            return header
        }
    }
}
